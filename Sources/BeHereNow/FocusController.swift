import AppKit
import Observation

@MainActor @Observable
final class FocusController {
    var defaultDelay: Double {
        didSet { defaults.set(defaultDelay, forKey: "defaultDelay") }
    }
    var overrides: [String: Double] {
        didSet { defaults.set(overrides, forKey: "applicationDelays") }
    }
    var neverHide: Set<String> {
        didSet { defaults.set(neverHide.sorted(), forKey: "neverHideApplications") }
    }
    private(set) var applications: [NSRunningApplication] = []
    private(set) var hideFailure: String?
    private let defaults: UserDefaults
    private var inactivity = Inactivity()
    private var focusedPID: Int32?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: "defaultDelay")
        defaultDelay = saved > 0 ? saved : 60
        overrides = (defaults.dictionary(forKey: "applicationDelays") ?? [:])
            .compactMapValues { value in
                guard let seconds = value as? Double, seconds.isFinite, seconds > 0 else { return nil }
                return seconds
            }
        neverHide = Set(defaults.stringArray(forKey: "neverHideApplications") ?? [])
        refresh()
        resetTimers()
        let workspace = NSWorkspace.shared
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let event = notification.name
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.refresh()
                    if event == NSWorkspace.didWakeNotification || event == NSWorkspace.sessionDidBecomeActiveNotification {
                        self.resetTimers()
                    } else if event == NSWorkspace.didActivateApplicationNotification {
                        self.updateFocus()
                    } else if let pid {
                        self.inactivity.focus(pid)
                        if event != NSWorkspace.didTerminateApplicationNotification && pid != self.focusedPID {
                            self.inactivity.leave(pid, at: ProcessInfo.processInfo.systemUptime)
                        }
                    }
                }
            })
        }
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.hideExpiredApplications()
            }
        }
    }

    /// The time out of focus before an application hides, or nil if it never hides.
    func delay(for identifier: String) -> Double? {
        neverHide.contains(identifier) ? nil : overrides[identifier] ?? defaultDelay
    }

    private func refresh() {
        applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }.sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func resetTimers() {
        inactivity.reset()
        focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let now = ProcessInfo.processInfo.systemUptime
        for app in applications where app.processIdentifier != focusedPID && !app.isHidden {
            inactivity.leave(app.processIdentifier, at: now)
        }
    }

    private func updateFocus() {
        let next = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard next != focusedPID else { return }
        if let previous = focusedPID {
            inactivity.leave(previous, at: ProcessInfo.processInfo.systemUptime)
        }
        if let next { inactivity.focus(next) }
        focusedPID = next
    }

    private func hideExpiredApplications() {
        updateFocus()
        let now = ProcessInfo.processInfo.systemUptime
        for app in applications {
            guard !app.isHidden, !app.isTerminated,
                  app.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  let identifier = app.bundleIdentifier,
                  let delay = delay(for: identifier),
                  inactivity.isDue(app.processIdentifier, delay: delay, at: now)
            else { continue }
            if app.hide() {
                inactivity.focus(app.processIdentifier)
                hideFailure = nil
            } else {
                hideFailure = "Could not hide \(app.localizedName ?? identifier)."
                inactivity.leave(app.processIdentifier, at: now)
            }
        }
    }
}
