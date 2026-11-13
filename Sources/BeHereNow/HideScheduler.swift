/// A running application as the scheduler sees it.
struct ScheduledApp: Equatable {
    let pid: Int32
    let bundleIdentifier: String
    let isHidden: Bool
}

/// A connected display, as a Core Graphics display ID.
typealias DisplayID = UInt32

/// The workspace at one moment. `now` is system uptime in seconds.
struct WorkspaceSnapshot {
    var frontmost: Int32?
    /// The display holding the frontmost application's front window, if it has one.
    var frontmostDisplay: DisplayID?
    var displays: Set<DisplayID>
    var applications: [ScheduledApp]
    var now: Double
}

/// Decides which applications are due to hide. An application's delay starts when it loses
/// focus or appears in the background, and returning to it clears the delay.
///
/// Each display keeps its current application, the one last used there. Current applications
/// count as focused, so with two displays the application you left on the other display stays.
struct HideScheduler {
    enum Event: Equatable {
        /// The frontmost application may have changed.
        case activated
        case launched(Int32)
        case unhidden(Int32)
        case terminated(Int32)
        /// The Mac woke or the session became active. Every background application starts a fresh delay.
        case woke
        /// A hide attempt from `takeDue` did not hide the application.
        case failedToHide(Int32)
    }

    private var leftAt: [Int32: Double] = [:]
    private var focused: Set<Int32> = []
    private var current: [DisplayID: Int32] = [:]

    mutating func handle(_ event: Event, in workspace: WorkspaceSnapshot) {
        switch event {
        case .activated:
            updateFocus(workspace)
        case let .launched(pid), let .unhidden(pid):
            updateFocus(workspace)
            leftAt[pid] = focused.contains(pid) ? nil : workspace.now
        case let .terminated(pid):
            current = current.filter { $0.value != pid }
            updateFocus(workspace)
            leftAt[pid] = nil
        case .woke:
            updateFocus(workspace)
            leftAt.removeAll()
            for app in workspace.applications where !focused.contains(app.pid) && !app.isHidden {
                leftAt[app.pid] = workspace.now
            }
        case let .failedToHide(pid):
            leftAt[pid] = workspace.now
        }
    }

    /// Returns the applications whose delay has run out and clears their delays, so the caller
    /// hides each one once. `delay` returns nil for applications that never hide.
    mutating func takeDue(in workspace: WorkspaceSnapshot, delay: (String) -> Double?) -> [ScheduledApp] {
        // Catch a focus change whose activation notification hasn't arrived yet.
        updateFocus(workspace)
        let due = workspace.applications.filter { app in
            guard !app.isHidden, !focused.contains(app.pid),
                  let start = leftAt[app.pid],
                  let delay = delay(app.bundleIdentifier)
            else { return false }
            return workspace.now - start >= delay
        }
        for app in due { leftAt[app.pid] = nil }
        return due
    }

    private mutating func updateFocus(_ workspace: WorkspaceSnapshot) {
        let visible = Set(workspace.applications.filter { !$0.isHidden }.map(\.pid))
        // The frontmost application becomes its display's current application. Applications
        // Be Here Now doesn't track, like itself, leave the current application alone.
        if let pid = workspace.frontmost, visible.contains(pid), let display = workspace.frontmostDisplay {
            current[display] = pid
        }
        // A display loses its current application when the display goes away or the application
        // hides or quits. Nothing takes its place until you use another application there.
        current = current.filter { workspace.displays.contains($0.key) && visible.contains($0.value) }

        var next = Set(current.values)
        if let frontmost = workspace.frontmost { next.insert(frontmost) }
        for pid in focused.subtracting(next) { leftAt[pid] = workspace.now }
        for pid in next { leftAt[pid] = nil }
        focused = next
    }
}
