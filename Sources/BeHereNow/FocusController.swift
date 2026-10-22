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
    /// When true, applications hide the moment they lose focus. Never hide still applies.
    var zazenMode: Bool {
        didSet {
            defaults.set(zazenMode, forKey: "zazenMode")
            if zazenMode { hideExpiredApplications() }
        }
    }
    private(set) var applications: [NSRunningApplication] = []
    private(set) var hideFailure: String?
    /// Menu bar icon rotation in degrees. Each hide turns it a further 180°.
    private(set) var iconAngle: Double = 0
    private var iconTarget: Double = 0
    private var spinning = false
    private let defaults: UserDefaults
    private var scheduler = HideScheduler()
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
        zazenMode = defaults.bool(forKey: "zazenMode")
        refresh()
        scheduler.handle(.woke, in: snapshot())
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
                let event = Self.event(for: notification.name, pid: pid)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.refresh()
                    if let event { self.scheduler.handle(event, in: self.snapshot()) }
                    // Zazen mode can't wait for the next one-second tick.
                    if self.zazenMode { self.hideExpiredApplications() }
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
        if neverHide.contains(identifier) { return nil }
        return zazenMode ? 0 : overrides[identifier] ?? defaultDelay
    }

    private func refresh() {
        applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }.sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private nonisolated static func event(for name: Notification.Name, pid: Int32?) -> HideScheduler.Event? {
        switch name {
        case NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification: .woke
        case NSWorkspace.didActivateApplicationNotification: .activated
        case NSWorkspace.didLaunchApplicationNotification: pid.map(HideScheduler.Event.launched)
        case NSWorkspace.didUnhideApplicationNotification: pid.map(HideScheduler.Event.unhidden)
        case NSWorkspace.didTerminateApplicationNotification: pid.map(HideScheduler.Event.terminated)
        default: nil
        }
    }

    private func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            applications: applications.compactMap { app in
                guard !app.isTerminated, let identifier = app.bundleIdentifier else { return nil }
                return ScheduledApp(pid: app.processIdentifier, bundleIdentifier: identifier, isHidden: app.isHidden)
            },
            now: ProcessInfo.processInfo.systemUptime
        )
    }

    private func hideExpiredApplications() {
        let due = scheduler.takeDue(in: snapshot(), delay: delay(for:))
        for scheduled in due {
            guard let app = applications.first(where: { $0.processIdentifier == scheduled.pid }) else { continue }
            // hide() returns false on macOS 26 even when the application hides, so check isHidden instead.
            app.hide()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !app.isTerminated, !app.isActive else { return }
                if app.isHidden {
                    self.hideFailure = nil
                    self.spin()
                } else {
                    self.hideFailure = "Could not hide \(app.localizedName ?? scheduled.bundleIdentifier)."
                    self.scheduler.handle(.failedToHide(app.processIdentifier), in: self.snapshot())
                }
            }
        }
    }

    /// Steps the icon through a half turn. Hides during a spin extend it by another half turn.
    private func spin() {
        iconTarget += 180
        guard !spinning else { return }
        spinning = true
        Task { @MainActor [weak self] in
            while let self, self.iconAngle < self.iconTarget {
                try? await Task.sleep(for: .milliseconds(16))
                self.iconAngle = min(self.iconTarget, self.iconAngle + 12)
            }
            self?.spinning = false
        }
    }
}
