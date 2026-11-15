import XCTest
@testable import NotchCore

final class TranscriptSnapshotTests: XCTestCase {
    private let t0 = Fixture.t0

    func testHousekeepingLinesAreNotTurns() {
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([
            Fixture.assistant(uuid: "a1", at: t0, usage: Fixture.usage()),
            Fixture.user(at: t0.addingTimeInterval(5), content: String(repeating: "summary ", count: 1000), extra: ["isCompactSummary": true]),
            Fixture.user(at: t0.addingTimeInterval(6), content: "<local-command-caveat>caveat</local-command-caveat>", extra: ["isMeta": true]),
            Fixture.user(at: t0.addingTimeInterval(7), content: "<command-name>/compact</command-name>"),
            Fixture.user(at: t0.addingTimeInterval(8), content: "<local-command-stdout>Compacted</local-command-stdout>"),
        ]))
        XCTAssertEqual(snapshot.lastTurn?.uuid, "a1")
        XCTAssertGreaterThanOrEqual(snapshot.compactedContextEstimate ?? 0, 1000)
        XCTAssertTrue(snapshot.contextUsage.isEstimate)
    }

    func testAnAssistantReplyAfterCompactionReplacesTheEstimate() {
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([
            Fixture.user(at: t0, content: "summary", extra: ["isCompactSummary": true]),
            Fixture.assistant(at: t0.addingTimeInterval(5), usage: Fixture.usage(input: 100, cacheRead: 900, output: 50)),
        ]))
        XCTAssertNil(snapshot.compactedContextEstimate)
        XCTAssertEqual(snapshot.contextUsage.tokens, 1050)
        XCTAssertFalse(snapshot.contextUsage.isEstimate)
    }

    func testSubagentTrafficIsIgnored() {
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([
            Fixture.assistant(uuid: "main", at: t0),
            Fixture.assistant(uuid: "side", at: t0.addingTimeInterval(10), stop: nil).merging(["isSidechain": true]) { $1 },
        ]))
        XCTAssertEqual(snapshot.lastTurn?.uuid, "main")
    }

    func testContextCountsInputCacheAndOutputTokens() {
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([
            Fixture.assistant(at: t0, usage: Fixture.usage(input: 3, cacheRead: 100_000, cacheCreation: 2_000, output: 500)),
        ]))
        XCTAssertEqual(snapshot.contextUsage.tokens, 102_503)
        XCTAssertEqual(snapshot.contextUsage.window, 1_000_000)
    }

    // MARK: Prompt cache

    func testCacheLifetimeFollowsTheLastRequestThatWrote() {
        let wroteOneHour = Fixture.assistant(at: t0, usage: Fixture.usage(cacheCreation: 500, created1h: 500))
        let readOnly = Fixture.assistant(at: t0.addingTimeInterval(60), usage: Fixture.usage(cacheRead: 500))
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([wroteOneHour, readOnly]))
        XCTAssertEqual(snapshot.promptCache?.isLongLived, true, "a read-only reply must not reset the lifetime to 5 minutes")
    }

    func testFiveMinuteWriteAndNoWriteBothDefaultToFiveMinutes() {
        let shortWrite = TranscriptSnapshot(entries: Fixture.entries([Fixture.assistant(at: t0, usage: Fixture.usage(cacheCreation: 10, created5m: 10))]))
        XCTAssertEqual(shortWrite.promptCache?.isLongLived, false)
        let noWrite = TranscriptSnapshot(entries: Fixture.entries([Fixture.assistant(at: t0, usage: Fixture.usage())]))
        XCTAssertEqual(noWrite.promptCache?.isLongLived, false)
    }

    func testCacheClockStartsWhenTheRequestStartedNotWhenTheReplyFinished() {
        let prompt = Fixture.user(uuid: "u1", at: t0, content: "hi")
        let reply = Fixture.assistant(parent: "u1", at: t0.addingTimeInterval(90), usage: Fixture.usage(cacheCreation: 10, created5m: 10))
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([prompt, reply]))
        XCTAssertEqual(snapshot.promptCache?.expiresAt, t0.addingTimeInterval(Config.shortCacheLifetime))
    }

    func testCacheClockUsesTheFirstEntryOfAReplySplitAcrossSeveralLines() {
        let prompt = Fixture.user(uuid: "u1", at: t0, content: "hi")
        let thinking = Fixture.assistant(parent: "u1", messageID: "m1", at: t0.addingTimeInterval(40), blocks: [["type": "thinking"]], stop: nil)
        let answer = Fixture.assistant(parent: "u2", messageID: "m1", at: t0.addingTimeInterval(80), usage: Fixture.usage(cacheCreation: 10, created5m: 10))
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([prompt, thinking, answer]))
        XCTAssertEqual(snapshot.promptCache?.expiresAt, t0.addingTimeInterval(Config.shortCacheLifetime))
    }

    func testNoAssistantReplyMeansNoCache() {
        XCTAssertNil(TranscriptSnapshot(entries: Fixture.entries([Fixture.user(at: t0, content: "hi")])).promptCache)
    }

    // MARK: Titles

    func testCustomTitleBeatsAITitleWhicheverComesFirst() {
        let aiThenCustom = TranscriptSnapshot(entries: Fixture.entries([["aiTitle": "AI"], ["customTitle": "Mine"]]))
        let customThenAI = TranscriptSnapshot(entries: Fixture.entries([["customTitle": "Mine"], ["aiTitle": "AI"]]))
        let aiOnly = TranscriptSnapshot(entries: Fixture.entries([["aiTitle": "AI"]]))
        XCTAssertEqual(aiThenCustom.title, "Mine")
        XCTAssertEqual(customThenAI.title, "Mine")
        XCTAssertEqual(aiOnly.title, "AI")
    }

    func testProjectNameComesFromTheWorkingDirectory() {
        let snapshot = TranscriptSnapshot(entries: Fixture.entries([Fixture.assistant(at: t0)]))
        XCTAssertEqual(snapshot.projectName, "demo")
    }
}
