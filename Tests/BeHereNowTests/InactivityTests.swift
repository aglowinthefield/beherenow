import Testing
@testable import BeHereNow

@Test func switchingBackRestartsTheDelay() {
    var inactivity = Inactivity()
    inactivity.leave(1, at: 10)
    #expect(!inactivity.isDue(1, delay: 60, at: 69))
    #expect(inactivity.isDue(1, delay: 60, at: 70))
    inactivity.focus(1)
    #expect(!inactivity.isDue(1, delay: 60, at: 100))
    inactivity.leave(1, at: 100)
    #expect(!inactivity.isDue(1, delay: 60, at: 159))
    #expect(inactivity.isDue(1, delay: 60, at: 160))
}

@Test func applicationsHaveIndependentDelays() {
    var inactivity = Inactivity()
    inactivity.leave(1, at: 0)
    inactivity.leave(2, at: 0)
    #expect(inactivity.isDue(1, delay: 30, at: 30))
    #expect(!inactivity.isDue(2, delay: 120, at: 30))
    inactivity.reset()
    #expect(!inactivity.isDue(1, delay: 30, at: 300))
}
