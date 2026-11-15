import XCTest
@testable import NotchCore

final class SingleInstanceTests: TempHomeTestCase {
    func testASecondCopyIsRefusedWhileTheFirstRuns() {
        let first = SingleInstance.acquire(lockFile: paths.instanceLock)
        XCTAssertNotNil(first)
        XCTAssertNil(SingleInstance.acquire(lockFile: paths.instanceLock))
        withExtendedLifetime(first) {}
    }

    func testTheLockIsReleasedWhenTheFirstCopyEnds() {
        var first = SingleInstance.acquire(lockFile: paths.instanceLock)
        XCTAssertNotNil(first)
        first = nil
        XCTAssertNotNil(SingleInstance.acquire(lockFile: paths.instanceLock), "a restart must be able to start")
    }

    func testARestartWaitsForTheOldCopyToLetGo() {
        var old = SingleInstance.acquire(lockFile: paths.instanceLock)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { old = nil }
        XCTAssertNotNil(SingleInstance.acquire(lockFile: paths.instanceLock, waitingUpTo: 3))
        _ = old
    }
}
