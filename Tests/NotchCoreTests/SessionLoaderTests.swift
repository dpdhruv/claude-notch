import XCTest
@testable import NotchCore

final class SessionLoaderTests: TempHomeTestCase {
    private let t0 = Fixture.t0

    private func transcript(_ id: String, _ lines: [[String: Any]], project: String = "-Users-me-demo") throws -> URL {
        let url = paths.transcripts.appendingPathComponent("\(project)/\(id).jsonl")
        try write(Fixture.jsonl(lines), to: url)
        return url
    }

    private func load(_ url: URL, now: Date) -> ClaudeSession? {
        SessionLoader(paths: paths).load(transcript: url, fileModified: now, now: now)
    }

    func testBuildsAFullSessionFromATranscript() throws {
        let url = try transcript("abc", [
            ["customTitle": "My session"],
            Fixture.user(uuid: "u1", at: t0, content: "hello"),
            Fixture.assistant(parent: "u1", at: t0.addingTimeInterval(20), blocks: [Fixture.text("Hi there")],
                              usage: Fixture.usage(input: 5, cacheRead: 40_000, cacheCreation: 100, output: 20, created1h: 100)),
        ])
        let session = try XCTUnwrap(load(url, now: t0.addingTimeInterval(60)))
        XCTAssertEqual(session.id, "abc")
        XCTAssertEqual(session.title, "My session")
        XCTAssertEqual(session.project, "demo")
        XCTAssertEqual(session.state, .done)
        XCTAssertEqual(session.detail, "Hi there")
        XCTAssertEqual(session.model, "Sonnet 5.5")
        XCTAssertEqual(session.context.tokens, 40_125)
        XCTAssertEqual(session.cache?.isLongLived, true)
        XCTAssertEqual(session.lastActivity, t0.addingTimeInterval(20))
    }

    func testMetadataWritesDoNotMakeAnOldSessionLookActive() throws {
        // The file was touched "now" (a title update), but the last real message is an hour old.
        let url = try transcript("old", [
            Fixture.assistant(at: t0, blocks: [Fixture.toolUse("Bash")], stop: "tool_use"),
            ["customTitle": "Renamed"],
        ])
        let now = t0.addingTimeInterval(3600 + 60)
        let session = try XCTUnwrap(SessionLoader(paths: paths).load(transcript: url, fileModified: now, now: now))
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastActivity, t0)
    }

    func testSessionWithOnlyMetadataIsListedAsIdle() throws {
        let url = try transcript("meta", [["customTitle": "Just a title"], ["type": "mode", "mode": "auto"]])
        let session = try XCTUnwrap(load(url, now: t0))
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.title, "Just a title")
        XCTAssertNil(session.cache)
    }

    func testSessionStaysListedWhenTheLastLineIsLargerThanTheFirstWindow() throws {
        // A big attachment as the final line leaves the smallest tail window with no complete line in it.
        let huge: [String: Any] = ["type": "attachment", "blob": String(repeating: "x", count: Config.transcriptTailSizes[0] + 50_000)]
        let url = try transcript("big", [Fixture.assistant(at: t0, blocks: [Fixture.text("Earlier reply")]), huge])
        let session = try XCTUnwrap(load(url, now: t0.addingTimeInterval(30)))
        XCTAssertEqual(session.detail, "Earlier reply")
    }

    func testEmptyTranscriptIsSkipped() throws {
        let url = paths.transcripts.appendingPathComponent("-p/empty.jsonl")
        try write(Data(), to: url)
        XCTAssertNil(load(url, now: t0))
    }

    func testHookDataOverridesTheGuess() throws {
        let url = try transcript("hooked", [Fixture.assistant(at: t0, blocks: [Fixture.toolUse("Bash")], stop: "tool_use")])
        let state: [String: Any] = ["event": "Notification", "ts": t0.addingTimeInterval(1).timeIntervalSince1970,
                                    "payload": ["notification_type": "permission_prompt", "message": "Claude needs permission to use Bash"]]
        try write(try JSONSerialization.data(withJSONObject: state), to: paths.hookStates.appendingPathComponent("hooked.json"))

        let session = try XCTUnwrap(load(url, now: t0.addingTimeInterval(2)))
        XCTAssertEqual(session.state, .needsYou)
        XCTAssertEqual(session.detail, "Claude needs permission to use Bash")
    }

    private func touch(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testScanListsRecentSessionsMostUrgentFirst() throws {
        let quiet = try transcript("quiet", [Fixture.assistant(at: t0.addingTimeInterval(-3000))])
        let busy = try transcript("busy", [Fixture.toolResult(at: t0)], project: "-other")
        try touch(quiet, t0)
        try touch(busy, t0)

        let sessions = SessionMonitor.scan(paths: paths, now: t0.addingTimeInterval(10))
        XCTAssertEqual(sessions.map(\.id), ["busy", "quiet"])
        XCTAssertEqual(sessions.map(\.state), [.working, .idle])
    }

    func testScanSkipsTranscriptsOutsideTheWindow() throws {
        let stale = try transcript("stale", [Fixture.assistant(at: t0)])
        try touch(stale, t0)
        let sessions = SessionMonitor.scan(paths: paths, now: t0.addingTimeInterval(Config.sessionWindow + 60))
        XCTAssertTrue(sessions.isEmpty)
    }

    func testScanOfAMissingFolderIsEmpty() {
        XCTAssertEqual(SessionMonitor.scan(paths: paths, now: Date()), [])
    }
}
