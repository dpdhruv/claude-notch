import XCTest
@testable import NotchCore

final class AlertEngineTests: XCTestCase {
    private let t0 = Fixture.t0

    func testTheFirstSnapshotIsABaselineAndNeverAlerts() {
        let engine = AlertEngine()
        XCTAssertTrue(engine.alerts(forChangesIn: [Fixture.session(state: .needsYou)]).isEmpty)
    }

    func testNeedingYouAlertsOnce() {
        let engine = AlertEngine()
        _ = engine.alerts(forChangesIn: [Fixture.session(state: .working)])
        XCTAssertEqual(engine.alerts(forChangesIn: [Fixture.session(state: .needsYou)]).map(\.kind), [.needsYou])
        XCTAssertTrue(engine.alerts(forChangesIn: [Fixture.session(state: .needsYou)]).isEmpty)
    }

    func testFinishingAfterWorkAlerts() {
        let engine = AlertEngine()
        _ = engine.alerts(forChangesIn: [Fixture.session(state: .working)])
        XCTAssertEqual(engine.alerts(forChangesIn: [Fixture.session(state: .done)]).map(\.kind), [.done])
    }

    func testBecomingDoneWithoutHavingWorkedDoesNotAlert() {
        let engine = AlertEngine()
        _ = engine.alerts(forChangesIn: [Fixture.session(state: .idle)])
        XCTAssertTrue(engine.alerts(forChangesIn: [Fixture.session(state: .done)]).isEmpty)
    }

    // MARK: Cache

    private func cacheSession(expiresIn seconds: TimeInterval, longLived: Bool = false, state: SessionState = .idle) -> ClaudeSession {
        Fixture.session(state: state, cache: PromptCache(expiresAt: t0.addingTimeInterval(seconds), isLongLived: longLived))
    }

    func testWarnsOnceWhenAShortCacheIsAboutToExpire() {
        let engine = AlertEngine()
        let session = cacheSession(expiresIn: 50)
        XCTAssertEqual(engine.alerts(forCachesIn: [session], now: t0).map(\.kind), [.cacheLow])
        XCTAssertTrue(engine.alerts(forCachesIn: [session], now: t0.addingTimeInterval(1)).isEmpty)
    }

    func testDoesNotWarnTooEarly() {
        XCTAssertTrue(AlertEngine().alerts(forCachesIn: [cacheSession(expiresIn: 200)], now: t0).isEmpty)
    }

    func testLongCachesWarnFiveMinutesAhead() {
        XCTAssertEqual(AlertEngine().alerts(forCachesIn: [cacheSession(expiresIn: 280, longLived: true)], now: t0).map(\.kind), [.cacheLow])
    }

    func testAnnouncesWhenTheCacheGoesCold() {
        let engine = AlertEngine()
        XCTAssertEqual(engine.alerts(forCachesIn: [cacheSession(expiresIn: -5)], now: t0).map(\.kind), [.cacheCold])
        XCTAssertTrue(engine.alerts(forCachesIn: [cacheSession(expiresIn: -5)], now: t0).isEmpty)
    }

    func testIgnoresCachesLongSinceCold() {
        XCTAssertTrue(AlertEngine().alerts(forCachesIn: [cacheSession(expiresIn: -500)], now: t0).isEmpty)
    }

    func testWorkingSessionsKeepTheirCacheWarm() {
        XCTAssertTrue(AlertEngine().alerts(forCachesIn: [cacheSession(expiresIn: 30, state: .working)], now: t0).isEmpty)
    }

    func testRefreshedCacheCanWarnAgain() {
        let engine = AlertEngine()
        XCTAssertEqual(engine.alerts(forCachesIn: [cacheSession(expiresIn: 50)], now: t0).count, 1)
        // A new reply pushed the expiry out, then it ran down again: a new cache generation.
        XCTAssertEqual(engine.alerts(forCachesIn: [cacheSession(expiresIn: 1000 + 50)], now: t0.addingTimeInterval(1000)).count, 1)
    }
}
