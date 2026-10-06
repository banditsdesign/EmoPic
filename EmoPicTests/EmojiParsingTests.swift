// EmojiParsingTests.swift
// Covers the bundled-data parsing surface: emojiFromUnified, parseEmojiJSON,
// and EmojiCategory.from(group:) against the iamcal/emoji-data schema.

import XCTest
@testable import EmoPic

final class EmojiParsingTests: XCTestCase {

    // MARK: - emojiFromUnified

    func testSingleCodepoint() {
        XCTAssertEqual(EmojiDataManager.emojiFromUnified("1F600"), "\u{1F600}") // 😀
    }

    func testMultipleCodepoints() {
        // flag: Sweden 🇸🇪 = 1F1F8 1F1EA
        XCTAssertEqual(EmojiDataManager.emojiFromUnified("1F1F8-1F1EA"), "\u{1F1F8}\u{1F1EA}")
    }

    func testZWJSequence() {
        // family 👨‍👩‍👧‍👦
        let unified = "1F468-200D-1F469-200D-1F467-200D-1F466"
        let expected = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        XCTAssertEqual(EmojiDataManager.emojiFromUnified(unified), expected)
    }

    func testVariationSelectors() {
        // VS16 text→emoji presentation: ❤️ = 2764 FE0F
        let vs16 = EmojiDataManager.emojiFromUnified("2764-FE0F")
        XCTAssertEqual(vs16, "\u{2764}\u{FE0F}")
        XCTAssertTrue(vs16.unicodeScalars.contains("\u{FE0F}"))

        // VS15 emoji→text presentation: ❤︎ = 2764 FE0E (must not be stripped)
        let vs15 = EmojiDataManager.emojiFromUnified("2764-FE0E")
        XCTAssertEqual(vs15, "\u{2764}\u{FE0E}")
        XCTAssertTrue(vs15.unicodeScalars.contains("\u{FE0E}"))
    }

    func testSkinToneModifierKept() {
        // 👍🏾 = 1F44D 1F3FE
        XCTAssertEqual(EmojiDataManager.emojiFromUnified("1F44D-1F3FE"), "\u{1F44D}\u{1F3FE}")
    }

    func testInvalidInputReturnsEmpty() {
        XCTAssertEqual(EmojiDataManager.emojiFromUnified(""), "")
        XCTAssertEqual(EmojiDataManager.emojiFromUnified("ZZZZ"), "")
        XCTAssertEqual(EmojiDataManager.emojiFromUnified("NOT-HEX"), "")
    }

    // MARK: - parseEmojiJSON

    func testParseIAMCalEntry() throws {
        let json = #"""
        [
          {
            "name": "grinning face",
            "unified": "1F600",
            "non_emoji": false,
            "output": true,
            "short_name": "smile",
            "short_names": ["grinning", "smile"],
            "text": ":)",
            "text_shortname": "",
            "category": "Smileys & Emotion",
            "added_in": "6.0",
            "emoji_location": [0, 0],
            "obfuscated": false,
            "keywords": ["happy"],
            "skin_tones": false,
            "obfuscated_short_name": false,
            "obfuscated_short_names": false,
            "obfuscated_name": false,
            "sort_order": 1
          }
        ]
        """#
        let items = try XCTUnwrap(EmojiDataManager.parseEmojiJSON(Data(json.utf8)))
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.emoji, "\u{1F600}")
        XCTAssertEqual(item.name, "grinning face")
        XCTAssertEqual(item.aliases, ["grinning", "smile"])
        XCTAssertEqual(item.version, "6.0")
        XCTAssertEqual(item.category, .smileys)
        XCTAssertEqual(item.id, "\u{1F600}")
    }

    func testParseSkipsEmptyUnifiedEntries() throws {
        let json = #"[{"name": "junk", "unified": "", "category": "Symbols"}]"#
        let items = try XCTUnwrap(EmojiDataManager.parseEmojiJSON(Data(json.utf8)))
        XCTAssertTrue(items.isEmpty)
    }

    func testParseMalformedJSONReturnsNil() {
        XCTAssertNil(EmojiDataManager.parseEmojiJSON(Data("not json".utf8)))
    }

    // MARK: - EmojiCategory.from(group:)

    func testCategoryMapping() {
        // Exactly the group strings shipped in iamcal/emoji-data.
        XCTAssertEqual(EmojiCategory.from(group: "Smileys & Emotion"), .smileys)
        XCTAssertEqual(EmojiCategory.from(group: "People & Body"), .people)
        XCTAssertEqual(EmojiCategory.from(group: "Animals & Nature"), .animals)
        XCTAssertEqual(EmojiCategory.from(group: "Food & Drink"), .food)
        XCTAssertEqual(EmojiCategory.from(group: "Activity"), .activities)
        XCTAssertEqual(EmojiCategory.from(group: "Travel & Places"), .travel)
        XCTAssertEqual(EmojiCategory.from(group: "Objects"), .objects)
        XCTAssertEqual(EmojiCategory.from(group: "Symbols"), .symbols)
        XCTAssertEqual(EmojiCategory.from(group: "Flags"), .flags)
        XCTAssertEqual(EmojiCategory.from(group: "???"), .symbols) // unknown → symbols
    }
}
