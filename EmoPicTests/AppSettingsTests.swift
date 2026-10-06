// AppSettingsTests.swift
// Round-trip persistence of AppSettings through an isolated UserDefaults suite.

import XCTest
import Carbon.HIToolbox
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

    func testHotKeyRoundTrip() {
        let first = AppSettings(suiteName: suiteName)
        first.hotKeyCode = 40 // 'k'
        first.hotKeyModifiers = cmdKey | optionKey

        let second = AppSettings(suiteName: suiteName)
        XCTAssertEqual(second.hotKeyOption, HotKeyOption.presets.first { $0.id == "opt-cmd-k" })
    }
}
