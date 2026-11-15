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
        let full = geometry.size(for: .request, sessionCount: 0, requestCount: NotchGeometry.maxRequestRows)
        let over = geometry.size(for: .request, sessionCount: 0, requestCount: NotchGeometry.maxRequestRows + 1)
        XCTAssertEqual(over.height - full.height, NotchGeometry.requestOverflowHeight)
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

final class RequestDetailTests: XCTestCase {
    func testBashShowsTheCommandAndClaudesExplanation() {
        let detail = ToolDescriber.detail(of: "Bash", input: ["command": "make test\nmake lint", "description": "Run checks"])
        XCTAssertEqual(detail.headline, "Run shell command")
        XCTAssertEqual(detail.explanation, "Run checks")
        XCTAssertEqual(detail.lines.map(\.text), ["make test", "make lint"])
    }

    func testLongCommandsAreCappedWithAMoreLine() {
        let command = (1...12).map { "step \($0)" }.joined(separator: "\n")
        let lines = ToolDescriber.detail(of: "Bash", input: ["command": command]).lines
        XCTAssertEqual(lines.count, ToolDescriber.maxDetailLines)
        XCTAssertEqual(lines.last, .init(kind: .note, text: "+8 more lines"))
    }

    func testEditShowsRemovedThenAddedLines() {
        let detail = ToolDescriber.detail(of: "Edit", input: ["file_path": "/a/b/Foo.swift", "old_string": "let x = 1", "new_string": "let x = 2"])
        XCTAssertEqual(detail.headline, "Edit Foo.swift")
        XCTAssertEqual(detail.lines, [.init(kind: .removed, text: "let x = 1"), .init(kind: .added, text: "let x = 2")])
    }

    func testWriteCountsLines() {
        let detail = ToolDescriber.detail(of: "Write", input: ["file_path": "/a/new.txt", "content": "a\nb\nc"])
        XCTAssertTrue(detail.location?.hasSuffix("3 lines") ?? false)
        XCTAssertEqual(detail.lines.filter { $0.kind == .added }.count, 3)
    }

    func testUnknownToolsListTheirArguments() {
        let detail = ToolDescriber.detail(of: "mcp__github__create_issue", input: ["title": "Bug", "repo": "x/y"])
        XCTAssertEqual(detail.lines.map(\.text), ["repo: x/y", "title: Bug"])
    }

    func testApprovalCardHeightGrowsWithItsLines() {
        let geometry = NotchGeometry(notchWidth: 190, notchHeight: 32)
        let short = geometry.size(for: .request, sessionCount: 0, requestCount: 1, requestBodyLines: [1])
        let tall = geometry.size(for: .request, sessionCount: 0, requestCount: 1, requestBodyLines: [5])
        XCTAssertEqual(tall.height - short.height, 4 * NotchGeometry.requestLineHeight)
    }
}
