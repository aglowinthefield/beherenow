import Testing
import Foundation
@testable import BeHereNow

@MainActor @Test func neverHideApplicationsHaveNoDelayAndPersist() throws {
    let suite = "BeHereNowTests.neverHide"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let controller = FocusController(defaults: defaults)
    controller.overrides["com.apple.TextEdit"] = 5
    controller.neverHide.insert("com.apple.Notes")
    #expect(controller.delay(for: "com.apple.TextEdit") == 5)
    #expect(controller.delay(for: "com.apple.Notes") == nil)
    #expect(controller.delay(for: "com.apple.Safari") == 60)

    let reopened = FocusController(defaults: defaults)
    #expect(reopened.delay(for: "com.apple.Notes") == nil)
}

@MainActor @Test func zazenModeHidesImmediatelyExceptNeverHide() throws {
    let suite = "BeHereNowTests.zazen"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    // Set through defaults so the test doesn't hide real applications via didSet.
    defaults.set(true, forKey: "zazenMode")
    defaults.set(["com.apple.TextEdit": 5.0], forKey: "applicationDelays")
    defaults.set(["com.apple.Notes"], forKey: "neverHideApplications")

    let controller = FocusController(defaults: defaults)
    #expect(controller.zazenMode)
    #expect(controller.delay(for: "com.apple.TextEdit") == 0)
    #expect(controller.delay(for: "com.apple.Safari") == 0)
    #expect(controller.delay(for: "com.apple.Notes") == nil)
}
