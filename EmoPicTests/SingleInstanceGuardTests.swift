// SingleInstanceGuardTests.swift
// The flock handshake behind the "EmoPic is already running" check: first copy
// wins, a second stands down, a released lock is reusable, and a lock file that
// cannot be used never blocks launch.

import XCTest
@testable import EmoPic

final class SingleInstanceGuardTests: XCTestCase {

    private var lockURL: URL!

    override func setUpWithError() throws {
        super.setUp()
        // One private lock file per test — the real one lives in Application
        // Support and the running app may be holding it.
        lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmoPicSingleInstanceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("single-instance.lock")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: lockURL.deletingLastPathComponent())
        lockURL = nil
        super.tearDown()
    }

    // MARK: - Lock

    func testFirstCopyWinsAndTheSecondStandsDown() {
        let first = SingleInstanceGuard(lockFileURL: lockURL)
        let second = SingleInstanceGuard(lockFileURL: lockURL)

        XCTAssertEqual(first.claim(retries: 0), .unique)
        XCTAssertEqual(second.claim(retries: 0), .alreadyRunning)
    }

    func testClaimIsIdempotentForTheHolder() {
        let first = SingleInstanceGuard(lockFileURL: lockURL)
        XCTAssertEqual(first.claim(retries: 0), .unique)
        XCTAssertEqual(first.claim(retries: 0), .unique,
                       "re-claiming must not read as a duplicate of ourselves")
    }

    func testReleasedLockCanBeTakenAgain() {
        let first = SingleInstanceGuard(lockFileURL: lockURL)
        let second = SingleInstanceGuard(lockFileURL: lockURL)
        XCTAssertEqual(first.claim(retries: 0), .unique)
        first.release()
        XCTAssertEqual(second.claim(retries: 0), .unique)
    }

    /// Two guards in one process take independent locks (separate file
    /// descriptors), which is what makes `flock` a stand-in for a second copy.
    func testDeinitReleasesTheLock() {
        func launchAndForget() {
            let copy = SingleInstanceGuard(lockFileURL: lockURL)
            XCTAssertEqual(copy.claim(retries: 0), .unique)
        }
        launchAndForget()
        XCTAssertEqual(SingleInstanceGuard(lockFileURL: lockURL).claim(retries: 0), .unique)
    }

    func testClaimWaitsForALockThatIsAboutToBeFreed() {
        // The relaunch race: the old copy is still exiting when the new one
        // starts, so a short wait beats refusing to launch.
        let leaving = SingleInstanceGuard(lockFileURL: lockURL)
        XCTAssertEqual(leaving.claim(retries: 0), .unique)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { leaving.release() }

        let arriving = SingleInstanceGuard(lockFileURL: lockURL)
        XCTAssertEqual(arriving.claim(retries: 20, retryInterval: 0.05), .unique)
    }

    func testClaimGivesUpWhileTheOtherCopyStillHoldsIt() {
        let first = SingleInstanceGuard(lockFileURL: lockURL)
        XCTAssertEqual(first.claim(retries: 0), .unique)

        let start = Date()
        let second = SingleInstanceGuard(lockFileURL: lockURL)
        XCTAssertEqual(second.claim(retries: 3, retryInterval: 0.05), .alreadyRunning)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.15,
                                    "retries must actually wait before giving up")
    }

    /// Fail open: an unusable lock file must never stop the app from starting.
    func testUnusableLockFileIsNotTreatedAsADuplicate() throws {
        // Parent path is a regular file, so the directory (and the lock) can
        // never be created.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmoPicSingleInstanceTests-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let copy = SingleInstanceGuard(lockFileURL: blocker.appendingPathComponent("nested.lock"))
        switch copy.claim(retries: 0) {
        case .lockUnavailable: break
        case let other: XCTFail("expected .lockUnavailable, got \(other)")
        }
    }

    func testDefaultLockFileLivesPerUserNotPerCopy() {
        let url = SingleInstanceGuard.defaultLockFileURL()
        XCTAssertEqual(url.lastPathComponent, "single-instance.lock")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "EmoPic")
        XCTAssertFalse(url.path.contains("/Applications/EmoPic.app"),
                       "the lock must be shared by every copy of the app")
    }

    // MARK: - Developer escape hatch

    func testAllowMultipleEnvironmentSwitch() {
        for on in ["1", "true", "TRUE", " yes ", "on"] {
            XCTAssertTrue(SingleInstanceGuard.allowsMultipleInstances(["EMOPIC_ALLOW_MULTIPLE": on]))
        }
        for off in ["0", "false", "", "banana"] {
            XCTAssertFalse(SingleInstanceGuard.allowsMultipleInstances(["EMOPIC_ALLOW_MULTIPLE": off]))
        }
        XCTAssertFalse(SingleInstanceGuard.allowsMultipleInstances([:]))
    }
}
