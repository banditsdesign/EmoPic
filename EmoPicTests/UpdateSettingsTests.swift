// UpdateSettingsTests.swift
// Persistence and safe defaults for the auto-update preferences (issue #2).
//
// Deliberately covers only the settings layer: the Sparkle wrapper itself needs
// a real app bundle, a feed URL and a keychain, none of which belong in a unit
// test — and none of these tests should ever be able to reach the network.

import XCTest
@testable import EmoPic

final class UpdateSettingsTests: XCTestCase {

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "EmoPicUpdateTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        suiteName = nil
        super.tearDown()
    }

    /// The privacy position depends on this: a fresh install must not have
    /// opted the user into network access.
    func testAutoUpdateChecksDefaultOff() {
        let settings = AppSettings(suiteName: suiteName)
        XCTAssertFalse(settings.automaticallyCheckForUpdates)
        XCTAssertNil(settings.lastUpdateCheck)
    }

    func testAutoUpdateChecksRoundTrip() {
        let first = AppSettings(suiteName: suiteName)
        first.automaticallyCheckForUpdates = true

        let second = AppSettings(suiteName: suiteName)
        XCTAssertTrue(second.automaticallyCheckForUpdates)
    }

    func testLastUpdateCheckRoundTripsAsDate() {
        let stamp = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let first = AppSettings(suiteName: suiteName)
        first.lastUpdateCheck = stamp

        let second = AppSettings(suiteName: suiteName)
        XCTAssertEqual(second.lastUpdateCheck, stamp)
    }

    /// Turning auto-update off must actually stick — otherwise a user who
    /// declines the opt-in keeps getting the network enabled on next launch.
    func testAutoUpdateChecksOffOverridesEarlierOptIn() {
        let optedIn = AppSettings(suiteName: suiteName)
        optedIn.automaticallyCheckForUpdates = true

        let optedOut = AppSettings(suiteName: suiteName)
        optedOut.automaticallyCheckForUpdates = false

        XCTAssertFalse(AppSettings(suiteName: suiteName).automaticallyCheckForUpdates)
    }

    /// The v1.0 → current migration copies a fixed list of keys out of the old
    /// App-Group suite. The update preferences must never be part of that list:
    /// silently inheriting an update opt-in from a stale domain would be exactly
    /// the kind of surprise this app promises not to do.
    func testUpdateKeysAreExcludedFromLegacyMigration() {
        XCTAssertFalse(AppSettings.legacyKeyNames.contains("automaticallyCheckForUpdates"))
        XCTAssertFalse(AppSettings.legacyKeyNames.contains("lastUpdateCheck"))
    }
}
