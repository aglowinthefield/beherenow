import Testing
@testable import BeHereNow

private let editor = ScheduledApp(pid: 1, bundleIdentifier: "com.apple.TextEdit", isHidden: false)
private let browser = ScheduledApp(pid: 2, bundleIdentifier: "com.apple.Safari", isHidden: false)
private let notes = ScheduledApp(pid: 3, bundleIdentifier: "com.apple.Notes", isHidden: false)

private let main: DisplayID = 1
private let side: DisplayID = 2

/// One display unless `displays` says otherwise. The frontmost application's window is on `display`.
private func workspace(_ frontmost: ScheduledApp?, _ applications: [ScheduledApp] = [editor, browser],
                       on display: DisplayID? = main, displays: Set<DisplayID> = [main], at now: Double) -> WorkspaceSnapshot {
    WorkspaceSnapshot(frontmost: frontmost?.pid, frontmostDisplay: display, displays: displays, applications: applications, now: now)
}

private func sixtySeconds(_ identifier: String) -> Double? { 60 }

/// A scheduler that started at time 0 with `frontmost` focused.
private func scheduler(focused frontmost: ScheduledApp, _ applications: [ScheduledApp] = [editor, browser]) -> HideScheduler {
    var scheduler = HideScheduler()
    scheduler.handle(.woke, in: workspace(frontmost, applications, at: 0))
    return scheduler
}

@Test func backgroundApplicationHidesAfterItsDelay() {
    var scheduler = scheduler(focused: browser)
    #expect(scheduler.takeDue(in: workspace(browser, at: 59), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 60), delay: sixtySeconds) == [editor])
}

@Test func focusedApplicationNeverHides() {
    var scheduler = scheduler(focused: editor)
    #expect(scheduler.takeDue(in: workspace(editor, at: 1_000), delay: sixtySeconds) == [browser])
}

@Test func switchingBackRestartsTheDelay() {
    var scheduler = scheduler(focused: browser)
    scheduler.handle(.activated, in: workspace(editor, at: 30))
    scheduler.handle(.activated, in: workspace(browser, at: 50))
    #expect(scheduler.takeDue(in: workspace(browser, at: 109), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 110), delay: sixtySeconds) == [editor])
}

@Test func missedActivationIsCaughtWhenCollecting() {
    var scheduler = scheduler(focused: editor)
    // The browser came forward but its activation notification hasn't arrived.
    #expect(scheduler.takeDue(in: workspace(browser, at: 30), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 90), delay: sixtySeconds) == [editor])
}

@Test func applicationsUseTheirOwnDelays() {
    var scheduler = scheduler(focused: notes, [editor, browser, notes])
    let delays = ["com.apple.TextEdit": 5.0, "com.apple.Safari": 120.0]
    let due = scheduler.takeDue(in: workspace(notes, [editor, browser, notes], at: 30)) { delays[$0] }
    #expect(due == [editor])
}

@Test func neverHideApplicationsAreNeverDue() {
    var scheduler = scheduler(focused: browser)
    #expect(scheduler.takeDue(in: workspace(browser, at: 1_000)) { _ in nil }.isEmpty)
}

@Test func dueApplicationsAreReturnedOnce() {
    var scheduler = scheduler(focused: browser)
    #expect(scheduler.takeDue(in: workspace(browser, at: 60), delay: sixtySeconds) == [editor])
    #expect(scheduler.takeDue(in: workspace(browser, at: 61), delay: sixtySeconds).isEmpty)
}

@Test func failedHideStartsAFreshDelay() {
    var scheduler = scheduler(focused: browser)
    #expect(scheduler.takeDue(in: workspace(browser, at: 60), delay: sixtySeconds) == [editor])
    scheduler.handle(.failedToHide(editor.pid), in: workspace(browser, at: 61))
    #expect(scheduler.takeDue(in: workspace(browser, at: 120), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 121), delay: sixtySeconds) == [editor])
}

@Test func hiddenApplicationsWaitUntilUnhidden() {
    let hiddenEditor = ScheduledApp(pid: 1, bundleIdentifier: "com.apple.TextEdit", isHidden: true)
    var scheduler = scheduler(focused: browser, [hiddenEditor, browser])
    #expect(scheduler.takeDue(in: workspace(browser, [hiddenEditor, browser], at: 1_000), delay: sixtySeconds).isEmpty)
    scheduler.handle(.unhidden(editor.pid), in: workspace(browser, at: 1_000))
    #expect(scheduler.takeDue(in: workspace(browser, at: 1_059), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 1_060), delay: sixtySeconds) == [editor])
}

@Test func launchedApplicationStartsItsDelayInTheBackground() {
    var scheduler = scheduler(focused: browser, [browser])
    scheduler.handle(.launched(editor.pid), in: workspace(browser, at: 10))
    #expect(scheduler.takeDue(in: workspace(browser, at: 69), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 70), delay: sixtySeconds) == [editor])
}

@Test func wakeGivesEveryBackgroundApplicationAFullDelay() {
    var scheduler = scheduler(focused: browser)
    scheduler.handle(.woke, in: workspace(browser, at: 500))
    #expect(scheduler.takeDue(in: workspace(browser, at: 559), delay: sixtySeconds).isEmpty)
    #expect(scheduler.takeDue(in: workspace(browser, at: 560), delay: sixtySeconds) == [editor])
}

@Test func terminatedApplicationForgetsItsDelay() {
    var scheduler = scheduler(focused: browser)
    scheduler.handle(.terminated(editor.pid), in: workspace(browser, [browser], at: 10))
    // A new process reusing the pid doesn't inherit the old delay.
    #expect(scheduler.takeDue(in: workspace(browser, at: 1_000), delay: sixtySeconds).isEmpty)
}

// MARK: Several displays

private let all = [editor, browser, notes]
private let both: Set<DisplayID> = [main, side]

/// Editor in use on the main display, then browser on the side display, from time 0.
private func twoDisplays() -> HideScheduler {
    var scheduler = HideScheduler()
    scheduler.handle(.woke, in: workspace(editor, all, on: main, displays: both, at: 0))
    scheduler.handle(.activated, in: workspace(browser, all, on: side, displays: both, at: 0))
    return scheduler
}

@Test func eachDisplayKeepsItsCurrentApplication() {
    var scheduler = twoDisplays()
    #expect(scheduler.takeDue(in: workspace(browser, all, on: side, displays: both, at: 1_000), delay: sixtySeconds) == [notes])
}

@Test func usingAnotherApplicationOnTheSameDisplayReplacesItsCurrentApplication() {
    var scheduler = twoDisplays()
    scheduler.handle(.activated, in: workspace(notes, all, on: main, displays: both, at: 10))
    #expect(scheduler.takeDue(in: workspace(notes, all, on: main, displays: both, at: 69), delay: sixtySeconds).isEmpty)
    // The browser stays current on the side display.
    #expect(scheduler.takeDue(in: workspace(notes, all, on: main, displays: both, at: 70), delay: sixtySeconds) == [editor])
}

@Test func hiddenCurrentApplicationIsNotReplaced() {
    var scheduler = twoDisplays()
    let hiddenEditor = ScheduledApp(pid: 1, bundleIdentifier: "com.apple.TextEdit", isHidden: true)
    let apps = [hiddenEditor, browser, notes]
    _ = scheduler.takeDue(in: workspace(browser, apps, on: side, displays: both, at: 5), delay: sixtySeconds)
    scheduler.handle(.unhidden(editor.pid), in: workspace(browser, all, on: side, displays: both, at: 10))
    // The editor is back but no longer current, so its delay starts.
    #expect(scheduler.takeDue(in: workspace(browser, all, on: side, displays: both, at: 69), delay: sixtySeconds) == [notes])
    #expect(scheduler.takeDue(in: workspace(browser, all, on: side, displays: both, at: 70), delay: sixtySeconds) == [editor])
}

@Test func disconnectedDisplayReleasesItsCurrentApplication() {
    var scheduler = twoDisplays()
    _ = scheduler.takeDue(in: workspace(browser, all, on: main, displays: [main], at: 10), delay: sixtySeconds)
    #expect(scheduler.takeDue(in: workspace(browser, all, on: main, displays: [main], at: 70), delay: sixtySeconds) == [editor, notes])
}

@Test func applicationWithoutWindowsLeavesCurrentApplicationsAlone() {
    var scheduler = twoDisplays()
    scheduler.handle(.activated, in: workspace(notes, all, on: nil, displays: both, at: 10))
    #expect(scheduler.takeDue(in: workspace(notes, all, on: nil, displays: both, at: 1_000), delay: sixtySeconds).isEmpty)
}

@Test func untrackedFrontmostApplicationLeavesCurrentApplicationsAlone() {
    var scheduler = twoDisplays()
    let settings = ScheduledApp(pid: 9, bundleIdentifier: "BeHereNow", isHidden: false)
    scheduler.handle(.activated, in: workspace(settings, all, on: main, displays: both, at: 10))
    #expect(scheduler.takeDue(in: workspace(settings, all, on: main, displays: both, at: 1_000), delay: sixtySeconds) == [notes])
}
