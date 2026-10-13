// CustomDescriptionTests.swift
// Custom emoji descriptions (issue #1): persistence through AppSettings,
// store semantics, item-level field derivation, and search/suggestion
// integration. Integration tests drive the shared store and restore the
// developer's real data afterwards, mirroring ColonSuggestionTests.

import XCTest
@testable import EmoPic

final class CustomDescriptionTests: XCTestCase {

    private var suiteName: String!
    private var savedDescriptions: [String: String]?
    private var savedRecents: [String]?

    /// Keyword + base emoji used by the integration tests. The keyword is
    /// invented so no real iamcal alias can collide with it; 🙋 resolves to
    /// the same id as the dataset entry.
    private let keyword = "qqzxbob"
    private let emojiID = "🙋"

    override func setUp() {
        super.setUp()
        suiteName = "EmoPicTests-\(UUID().uuidString)"
        EmojiDataManager.shared.loadEmojiData()
        savedDescriptions = CustomDescriptionStore.shared.descriptions
        savedRecents = AppSettings.shared.recentEmojiIDs
        AppSettings.shared.recentEmojiIDs = []   // recency must not reorder ranking
        FrequentEmojiStore.shared.update()
    }

    override func tearDown() {
        // Put the shared store back exactly as the developer left it.
        let store = CustomDescriptionStore.shared
        for id in Array(store.descriptions.keys) { store.remove(id) }
        for (id, text) in savedDescriptions ?? [:] { store.set(text, for: id) }
        savedDescriptions = nil
        if let savedRecents {
            AppSettings.shared.recentEmojiIDs = savedRecents
            FrequentEmojiStore.shared.update()
        }
        savedRecents = nil
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        suiteName = nil
        super.tearDown()
    }

    // MARK: - AppSettings persistence (volatile injected suite)

    func testCustomDescriptionsDefaultEmptyAndRoundTrip() {
        let first = AppSettings(suiteName: suiteName)
        XCTAssertEqual(first.customEmojiDescriptions, [:])
        first.customEmojiDescriptions = ["🙋": "bob", "😄": "office mascot"]
        let second = AppSettings(suiteName: suiteName)
        XCTAssertEqual(second.customEmojiDescriptions, ["🙋": "bob", "😄": "office mascot"])
    }

    // MARK: - Item-level derivation

    private func makeRaisingHand() -> EmojiItem {
        EmojiItem(emoji: "🙋", name: "raising hand", aliases: ["hand"],
                  version: "1.0", category: .smileys, id: emojiID)
    }

    func testApplyingCustomDescriptionDerivesKeywords() {
        let item = makeRaisingHand().applyingCustomDescription("  Bob's wave!  ")
        XCTAssertEqual(item.customDescription, "Bob's wave!")
        XCTAssertEqual(item.customWordsLower, ["bobs", "wave"])
        XCTAssertTrue(item.matchesQuery("bob"))             // substring match
        XCTAssertEqual(item.relevanceScore(for: "bobs"), 100) // exact keyword
        XCTAssertEqual(item.displayDescription, "Bob's wave!")
    }

    func testClearingCustomDescriptionRestoresBaseFields() {
        let base = makeRaisingHand()
        let cleared = base.applyingCustomDescription("bob").applyingCustomDescription("   ")
        XCTAssertEqual(cleared.customDescription, "")
        XCTAssertEqual(cleared.customWordsLower, [])
        XCTAssertFalse(cleared.matchesQuery("bob"))
        XCTAssertEqual(cleared.displayDescription, base.name)
    }

    func testSkinToneVariantInheritsCustomDescription() {
        let variant = makeRaisingHand().applyingCustomDescription("bob").withSkinTone(.dark)
        XCTAssertEqual(variant.emoji, "🙋🏿")
        XCTAssertEqual(variant.id, emojiID, "variant keeps the base id (recents keying)")
        XCTAssertEqual(variant.customDescription, "bob")
        XCTAssertTrue(variant.matchesQuery("bob"))
    }

    /// The dataset codec must never carry user text (custom fields are
    /// excluded from CodingKeys, same as the derived lowercasing fields).
    func testCustomDescriptionExcludedFromCoding() throws {
        let item = makeRaisingHand().applyingCustomDescription("bob")
        let data = try JSONEncoder().encode(item)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("customDescription"), "user text must not be encoded: \(json)")
        XCTAssertFalse(json.contains("bob"), "user text must not be encoded: \(json)")
        let decoded = try JSONDecoder().decode(EmojiItem.self, from: data)
        XCTAssertEqual(decoded.id, emojiID)
        XCTAssertEqual(decoded.customDescription, "")
    }

    // MARK: - Store semantics (shared store, restored in tearDown)

    func testStoreTrimsAndEmptyTextRemoves() {
        let store = CustomDescriptionStore.shared
        store.set("  \(keyword)  ", for: emojiID)
        XCTAssertEqual(store.description(for: emojiID), keyword)
        store.set("   ", for: emojiID)
        XCTAssertNil(store.description(for: emojiID))
    }

    func testStoreClampsToMaxLength() {
        let store = CustomDescriptionStore.shared
        store.set(String(repeating: "x", count: CustomDescriptionStore.maxLength + 50), for: emojiID)
        XCTAssertEqual(store.description(for: emojiID)?.count, CustomDescriptionStore.maxLength)
        store.remove(emojiID)
        XCTAssertNil(store.description(for: emojiID))
    }

    // MARK: - Search & suggestion integration

    func testCustomKeywordMakesEmojiFindableEverywhere() throws {
        _ = try XCTUnwrap(EmojiDataManager.shared.itemByID[emojiID],
                          "\(emojiID) must exist in the bundled dataset")

        CustomDescriptionStore.shared.set("\(keyword) office mascot", for: emojiID)

        // Picker search — the exact keyword scores like an alias, so it leads.
        let results = EmojiDataManager.shared.search(keyword, first: 50)
        XCTAssertEqual(results.first?.id, emojiID)

        // A plain word of the description matches as a keyword too.
        XCTAssertTrue(EmojiDataManager.shared.search("mascot").contains { $0.id == emojiID })

        // Colon monitor buffering + the suggestion popup.
        XCTAssertTrue(EmojiDataManager.shared.hasPrefix(String(keyword.prefix(4))))
        let suggestions = EmojiDataManager.shared.suggestions(forPrefix: String(keyword.prefix(5)))
        XCTAssertTrue(suggestions.contains { $0.id == emojiID && $0.shortname == keyword })

        // Removal is as immediate as the add.
        CustomDescriptionStore.shared.remove(emojiID)
        XCTAssertFalse(EmojiDataManager.shared.search(keyword).contains { $0.id == emojiID })
        XCTAssertFalse(EmojiDataManager.shared.hasPrefix(String(keyword.prefix(4))))
        XCTAssertTrue(EmojiDataManager.shared.suggestions(forPrefix: String(keyword.prefix(5))).isEmpty)
    }

    /// While a custom keyword exactly equals a builtin alias of another
    /// emoji, the exact slot follows the user's entry — user intent wins.
    func testCustomKeywordWinsExactMatchOverBuiltinAlias() {
        CustomDescriptionStore.shared.set("grin", for: emojiID)
        XCTAssertEqual(EmojiDataManager.shared.suggestions(forPrefix: "grin").first?.id, emojiID)

        CustomDescriptionStore.shared.remove(emojiID)
        XCTAssertNotEqual(EmojiDataManager.shared.suggestions(forPrefix: "grin").first?.id, emojiID)
    }
}
