import XCTest
@testable import NotchCore

final class NotchGeometryTests: XCTestCase {
    private let geometry = NotchGeometry(notchWidth: 190, notchHeight: 32)

    func testCollapsedHugsTheNotchWithWings() {
        let size = geometry.size(for: .collapsed, sessionCount: 3, requestCount: 0)
        XCTAssertEqual(size, CGSize(width: 190 + 148, height: 32))
    }

    func testListHeightGrowsPerSessionAndIsCapped() {
        let three = geometry.size(for: .expanded, sessionCount: 3, requestCount: 0)
        XCTAssertEqual(three.height, 32 + 3 * 74 + 20)
        XCTAssertEqual(geometry.size(for: .expanded, sessionCount: 50, requestCount: 0).height, 32 + 6 * 74 + 20)
        XCTAssertEqual(geometry.size(for: .expanded, sessionCount: 0, requestCount: 0).height, 32 + 74 + 20, "room for the empty message")
    }

    func testRequestListIsCappedWithAnOverflowLine() {
        let four = geometry.size(for: .request, sessionCount: 0, requestCount: 4)
        let five = geometry.size(for: .request, sessionCount: 0, requestCount: 5)
        XCTAssertEqual(five.height - four.height, NotchGeometry.requestOverflowHeight)
    }

    func testEveryModeFitsInsideThePanel() {
        for mode in [NotchMode.collapsed, .peek, .expanded, .request] {
            let size = geometry.size(for: mode, sessionCount: 99, requestCount: 99)
            XCTAssertLessThanOrEqual(size.width, NotchGeometry.panelSize.width, "\(mode)")
            XCTAssertLessThanOrEqual(size.height, NotchGeometry.panelSize.height, "\(mode)")
        }
    }

    func testRowHitTesting() {
        let firstRowCentre = CGPoint(x: 220, y: 32 + 34)
        let secondRowCentre = CGPoint(x: 220, y: 32 + 74 + 34)
        XCTAssertEqual(geometry.sessionRowIndex(at: firstRowCentre, sessionCount: 3), 0)
        XCTAssertEqual(geometry.sessionRowIndex(at: secondRowCentre, sessionCount: 3), 1)
    }

    func testHitTestingMissesGapsMarginsHeaderAndEmptyRows() {
        XCTAssertNil(geometry.sessionRowIndex(at: CGPoint(x: 220, y: 32 + 70), sessionCount: 3), "the gap between cards")
        XCTAssertNil(geometry.sessionRowIndex(at: CGPoint(x: 5, y: 60), sessionCount: 3), "left margin")
        XCTAssertNil(geometry.sessionRowIndex(at: CGPoint(x: 435, y: 60), sessionCount: 3), "right margin")
        XCTAssertNil(geometry.sessionRowIndex(at: CGPoint(x: 220, y: 10), sessionCount: 3), "header")
        XCTAssertNil(geometry.sessionRowIndex(at: CGPoint(x: 220, y: 32 + 3 * 74 + 10), sessionCount: 3), "below the last card")
    }
}

final class SessionLinkerTests: TempHomeTestCase {
    private func desktopSession(file: String, local: String, cli: String, modified: Date = Date()) throws {
        let url = paths.desktopSessions.appendingPathComponent("account/workspace/\(file).json")
        try write(try JSONSerialization.data(withJSONObject: ["sessionId": local, "cliSessionId": cli]), to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func testBuildsADeepLinkForDesktopSessions() throws {
        try desktopSession(file: "local_abc", local: "local_abc", cli: "cli-1")
        XCTAssertEqual(SessionLinker(paths: paths).deepLink(forTranscript: "cli-1")?.absoluteString, "claude://code/continue?session=local_abc")
    }

    func testTerminalSessionsHaveNoDeepLink() throws {
        try desktopSession(file: "local_abc", local: "local_abc", cli: "cli-1")
        XCTAssertNil(SessionLinker(paths: paths).deepLink(forTranscript: "someone-else"))
    }

    func testWithoutTheDesktopAppThereIsNoLink() {
        XCTAssertNil(SessionLinker(paths: paths).deepLink(forTranscript: "cli-1"))
    }

    func testNewestMatchWins() throws {
        try desktopSession(file: "local_old", local: "local_old", cli: "cli-1", modified: Date(timeIntervalSinceNow: -1000))
        try desktopSession(file: "local_new", local: "local_new", cli: "cli-1", modified: Date())
        XCTAssertEqual(SessionLinker(paths: paths).desktopSessionID(forTranscript: "cli-1"), "local_new")
    }

    func testResumeCommand() {
        XCTAssertEqual(SessionLinker.resumeCommand(forTranscript: "abc"), "claude --resume abc")
    }
}

final class PathsTests: XCTestCase {
    func testDerivesEverythingFromTheHomeDirectory() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/me"))
        XCTAssertEqual(paths.transcripts.path, "/Users/me/.claude/projects")
        XCTAssertEqual(paths.settingsFile.path, "/Users/me/.claude/settings.json")
        XCTAssertEqual(paths.installedHooks.path, "/Users/me/.claude-notch/hooks")
        XCTAssertEqual(paths.desktopSessions.path, "/Users/me/Library/Application Support/Claude/claude-code-sessions")
    }

    func testOverridesAreHonoured() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/me"), claudeDir: URL(fileURLWithPath: "/cfg"), notchDir: URL(fileURLWithPath: "/data"))
        XCTAssertEqual(paths.transcripts.path, "/cfg/projects")
        XCTAssertEqual(paths.heartbeat.path, "/data/alive")
    }
}

final class NotchInteractionTests: XCTestCase {
    private let geometry = NotchGeometry(notchWidth: 190, notchHeight: 32)

    func testCollapsedOnlyReactsOnThePhysicalNotchNotTheWings() {
        let drawn = geometry.size(for: .collapsed, sessionCount: 1, requestCount: 0)
        let zone = geometry.hotZone(for: .collapsed, drawnSize: drawn)
        XCTAssertLessThan(zone.width, drawn.width, "wings must not intercept the menu bar")
        XCTAssertGreaterThanOrEqual(zone.width, 190)
    }

    func testOtherModesReactAcrossWhatIsDrawn() {
        let drawn = geometry.size(for: .expanded, sessionCount: 3, requestCount: 0)
        XCTAssertEqual(geometry.hotZone(for: .expanded, drawnSize: drawn), drawn)
    }

    func testOnlyTheListAndApprovalsAcceptClicks() {
        XCTAssertTrue(NotchGeometry.acceptsClicks(in: .expanded))
        XCTAssertTrue(NotchGeometry.acceptsClicks(in: .request))
        XCTAssertFalse(NotchGeometry.acceptsClicks(in: .collapsed))
        XCTAssertFalse(NotchGeometry.acceptsClicks(in: .peek))
    }
}
