import XCTest
@testable import NotchCore

final class QuietPolicyTests: XCTestCase {
    private let now = Fixture.t0

    func testApprovalsWaitQuietlyOnlyWhileTheClaudeAppIsInFront() {
        let policy = QuietPolicy()
        XCTAssertTrue(policy.holdsApprovals(frontmostBundleID: "com.anthropic.claudefordesktop"))
        XCTAssertFalse(policy.holdsApprovals(frontmostBundleID: "com.apple.Terminal"), "a terminal in front must not hide approvals")
        XCTAssertFalse(policy.holdsApprovals(frontmostBundleID: "co.zeit.hyper"))
        XCTAssertFalse(policy.holdsApprovals(frontmostBundleID: "com.google.Chrome"))
        XCTAssertFalse(policy.holdsApprovals(frontmostBundleID: nil))
    }

    func testApprovalsAreNotHeldWhenTheOptionIsOff() {
        XCTAssertFalse(QuietPolicy(quietWhenClaudeInFront: false).holdsApprovals(frontmostBundleID: "com.anthropic.claudefordesktop"))
    }

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
