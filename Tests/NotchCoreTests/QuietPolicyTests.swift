import XCTest
@testable import NotchCore

final class QuietPolicyTests: XCTestCase {
    private let now = Fixture.t0

    func testNormalByDefault() {
        XCTAssertEqual(QuietPolicy().presence(fullScreenActive: false, now: now), .normal)
    }

    func testHiddenInFullScreenWhenEnabled() {
        XCTAssertEqual(QuietPolicy(quietInFullScreen: true).presence(fullScreenActive: true, now: now), .hidden)
    }

    func testFullScreenIsIgnoredWhenTheOptionIsOff() {
        XCTAssertEqual(QuietPolicy(quietInFullScreen: false).presence(fullScreenActive: true, now: now), .normal)
    }

    func testPausedIsQuietUntilItExpires() {
        let policy = QuietPolicy(pausedUntil: now.addingTimeInterval(60))
        XCTAssertEqual(policy.presence(fullScreenActive: false, now: now), .quiet)
        XCTAssertEqual(policy.presence(fullScreenActive: false, now: now.addingTimeInterval(61)), .normal)
    }

    func testFullScreenWinsOverPause() {
        let policy = QuietPolicy(pausedUntil: now.addingTimeInterval(60))
        XCTAssertEqual(policy.presence(fullScreenActive: true, now: now), .hidden)
    }

    func testPausedStateReportsItself() {
        XCTAssertTrue(QuietPolicy(pausedUntil: now.addingTimeInterval(1)).isPaused(at: now))
        XCTAssertFalse(QuietPolicy().isPaused(at: now))
    }
}
