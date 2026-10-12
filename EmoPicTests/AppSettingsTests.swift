// AppSettingsTests.swift
// Round-trip persistence of AppSettings through an isolated UserDefaults suite.

import XCTest
import Carbon.HIToolbox
import AppKit
@testable import EmoPic

final class AppSettingsTests: XCTestCase {

    private var suiteName: String!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "EmoPicTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeEmoji(_ char: String) -> EmojiItem {
        EmojiItem(emoji: char, name: "test-\(char)", aliases: [char], version: "1.0", category: .smileys)
    }

    func testDefaultsOnFreshSuite() {
        let settings = AppSettings(suiteName: suiteName)
        XCTAssertEqual(settings.selectedSkinTone, .default)
        XCTAssertEqual(settings.recentEmojiIDs, [])
        XCTAssertEqual(settings.enabledCategories, EmojiCategory.allCases.map(\.rawValue))
        XCTAssertTrue(settings.excludedApps.contains("com.apple.Terminal"))
        XCTAssertTrue(settings.enableColonShortcuts)
        XCTAssertTrue(settings.showFrequentInPicker)
        XCTAssertTrue(settings.hotKeyEnabled)
        XCTAssertEqual(settings.settingsTab, "Emoji Picker")
    }

    /// The Settings window restores the last-opened pane (apple-hig
    /// settings.md), so the value must survive instances and launches.
    func testLaunchAtLoginDefaultsFalseAndRoundTrips() {
        let suiteName = "EmoPicTests.launchAtLogin"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let s1 = AppSettings(suiteName: suiteName)
        XCTAssertFalse(s1.launchAtLogin, "login item should default off")
        s1.launchAtLogin = true
        XCTAssertTrue(AppSettings(suiteName: suiteName).launchAtLogin)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func testSettingsTabRoundTrip() {
        let first = AppSettings(suiteName: suiteName)
        first.settingsTab = "Colon Shortcuts"
        let second = AppSettings(suiteName: suiteName)
        XCTAssertEqual(second.settingsTab, "Colon Shortcuts")
    }

    /// Every tab icon must resolve to a real SF Symbol — `colon.textbox`
    /// and `list.bullet.square` once rendered as fallback blobs because
    /// they don't exist. Also asserts pane titles are unique (they double
    /// as toolbar item identifiers and window titles).
    func testSettingsTabIconsResolveAndTitlesAreUnique() {
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.rawValue)).count, SettingsTab.allCases.count)
        for tab in SettingsTab.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.rawValue),
                "SF Symbol \(tab.icon) does not exist on this OS"
            )
        }
    }

    func testRoundTripAcrossInstances() {
        let first = AppSettings(suiteName: suiteName)
        first.selectedSkinTone = .dark
        first.recordUsage(makeEmoji("😄"))
        first.recordUsage(makeEmoji("👍"))
        first.excludedApps = ["com.example.app"]
        first.enableColonShortcuts = false

        let second = AppSettings(suiteName: suiteName)
        XCTAssertEqual(second.selectedSkinTone, .dark)
        XCTAssertEqual(second.recentEmojiIDs, ["👍", "😄"]) // most recent first
        XCTAssertEqual(second.excludedApps, ["com.example.app"])
        XCTAssertFalse(second.enableColonShortcuts)
    }

    func testRecordUsageDedupesAndMovesToFront() {
        let settings = AppSettings(suiteName: suiteName)
        settings.recordUsage(makeEmoji("😄"))
        settings.recordUsage(makeEmoji("👍"))
        settings.recordUsage(makeEmoji("😄")) // again
        XCTAssertEqual(settings.recentEmojiIDs, ["😄", "👍"])
    }

    func testRecordUsageCapsAt30() {
        let settings = AppSettings(suiteName: suiteName)
        for index in 0..<35 {
            settings.recordUsage(makeEmoji("e\(index)"))
        }
        XCTAssertEqual(settings.recentEmojiIDs.count, 30)
        XCTAssertEqual(settings.recentEmojiIDs.first, "e34") // newest kept
    }

    func testIsAppExcluded() {
        let settings = AppSettings(suiteName: suiteName)
        XCTAssertTrue(settings.isAppExcluded("com.apple.Terminal"))
        XCTAssertFalse(settings.isAppExcluded("com.apple.TextEdit"))
    }

    /// v1.0 stored settings under an entitlement-less App-Group suite; the
    /// standard domain is the store now. Migration must copy only missing
    /// known keys, never overwrite existing ones, and be idempotent.
    func testLegacySuiteMigrationCopiesMissingKeysOnly() throws {
        let legacyName = "EmoPicTests-legacy-\(UUID().uuidString)"
        let legacy = try XCTUnwrap(UserDefaults(suiteName: legacyName))
        legacy.set("dark", forKey: "selectedSkinTone")
        legacy.set(["😄", "👍"], forKey: "recentEmojiIDs")
        legacy.set(true, forKey: "enableColonShortcuts")

        let targetName = "EmoPicTests-target-\(UUID().uuidString)"
        let target = try XCTUnwrap(UserDefaults(suiteName: targetName))
        target.set("light", forKey: "selectedSkinTone") // pre-existing — must survive

        AppSettings.migrateLegacyValues(into: target, legacySuiteName: legacyName)

        XCTAssertEqual(target.string(forKey: "selectedSkinTone"), "light", "existing keys must not be overwritten")
        XCTAssertEqual(target.array(forKey: "recentEmojiIDs") as? [String], ["😄", "👍"])
        XCTAssertEqual(target.object(forKey: "enableColonShortcuts") as? Bool, true)
        XCTAssertTrue(target.bool(forKey: "migratedFromLegacyGroupSuite"))

        // Idempotent: post-migration legacy changes must not leak through.
        legacy.set("medium", forKey: "selectedSkinTone")
        AppSettings.migrateLegacyValues(into: target, legacySuiteName: legacyName)
        XCTAssertEqual(target.string(forKey: "selectedSkinTone"), "light")

        target.removePersistentDomain(forName: targetName)
        legacy.removePersistentDomain(forName: legacyName)
    }

    func testHotKeyRoundTrip() {
        let first = AppSettings(suiteName: suiteName)
        first.hotKeyCode = 40 // 'k'
        first.hotKeyModifiers = cmdKey | optionKey

        let second = AppSettings(suiteName: suiteName)
        XCTAssertEqual(second.hotKeyOption, HotKeyOption.presets.first { $0.id == "opt-cmd-k" })
    }
}
