/// A running application as the scheduler sees it.
struct ScheduledApp: Equatable {
    let pid: Int32
    let bundleIdentifier: String
    let isHidden: Bool
}

/// The workspace at one moment. `now` is system uptime in seconds.
struct WorkspaceSnapshot {
    var frontmost: Int32?
    var applications: [ScheduledApp]
    var now: Double
}

/// Decides which applications are due to hide. An application's delay starts when it loses
/// focus or appears in the background, and returning to it clears the delay.
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
    private var focused: Int32?

    mutating func handle(_ event: Event, in workspace: WorkspaceSnapshot) {
        switch event {
        case .activated:
            updateFocus(workspace)
        case let .launched(pid), let .unhidden(pid):
            leftAt[pid] = pid == focused ? nil : workspace.now
        case let .terminated(pid):
            leftAt[pid] = nil
        case .woke:
            leftAt.removeAll()
            focused = workspace.frontmost
            for app in workspace.applications where app.pid != focused && !app.isHidden {
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
            guard !app.isHidden, app.pid != workspace.frontmost,
                  let start = leftAt[app.pid],
                  let delay = delay(app.bundleIdentifier)
            else { return false }
            return workspace.now - start >= delay
        }
        for app in due { leftAt[app.pid] = nil }
        return due
    }

    private mutating func updateFocus(_ workspace: WorkspaceSnapshot) {
        let next = workspace.frontmost
        guard next != focused else { return }
        if let focused { leftAt[focused] = workspace.now }
        if let next { leftAt[next] = nil }
        focused = next
    }
}
