// ColonSuggestionTests.swift
// Suggestion ranking (EmojiDataManager.suggestions(forPrefix:)) and the
// popup view-model's selection rules. Ranking tests run against the real
// bundled dataset loaded in the app-host test environment.

import XCTest
@testable import EmoPic

final class ColonSuggestionTests: XCTestCase {

    // MARK: - View model: selection retention & clamping

    private func makeItem(_ id: String) -> EmojiItem {
        EmojiItem(emoji: "😀", name: id, aliases: [id], version: "1.0", category: .smileys, id: id)
    }

    private func makeSuggestion(_ id: String) -> EmojiSuggestion {
        EmojiSuggestion(id: id, emoji: makeItem(id), shortname: id)
    }

    func testUpdateSelectsFirstAndKeepsStillPresentSelection() {
        let vm = ColonSuggestionViewModel()
        vm.update([makeSuggestion("a"), makeSuggestion("b"), makeSuggestion("c")])
        XCTAssertEqual(vm.selected?.id, "a")

        vm.moveSelection(1)
        XCTAssertEqual(vm.selected?.id, "b")

        // "b" survives an update → stays selected.
        vm.update([makeSuggestion("b"), makeSuggestion("c")])
        XCTAssertEqual(vm.selected?.id, "b")

        // "b" gone → fall back to first.
        vm.update([makeSuggestion("x"), makeSuggestion("b")])
        // "b" is still present, so it is kept.
        XCTAssertEqual(vm.selected?.id, "b")
        vm.update([makeSuggestion("x")])
        XCTAssertEqual(vm.selected?.id, "x")
    }

    func testMoveSelectionClampsAtBothEnds() {
        let vm = ColonSuggestionViewModel()
        vm.update([makeSuggestion("a"), makeSuggestion("b")])
        vm.moveSelection(-5)
        XCTAssertEqual(vm.selected?.id, "a")
        vm.moveSelection(5)
        XCTAssertEqual(vm.selected?.id, "b")
        vm.moveSelection(1)
        XCTAssertEqual(vm.selected?.id, "b")
    }

    func testSelectIgnoresUnknownID() {
        let vm = ColonSuggestionViewModel()
        vm.update([makeSuggestion("a")])
        vm.select("nope")
        XCTAssertEqual(vm.selected?.id, "a")
    }

    func testEmptyUpdateClearsSelection() {
        let vm = ColonSuggestionViewModel()
        vm.update([makeSuggestion("a")])
        vm.update([])
        XCTAssertNil(vm.selected)
    }

    // MARK: - Ranking against the real bundled dataset

    override class func setUp() {
        super.setUp()
        EmojiDataManager.shared.loadEmojiData()
    }

    func testExactAliasRanksFirst() {
        let items = EmojiDataManager.shared.suggestions(forPrefix: "smile")
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.first?.shortname, "smile")
    }

    func testPrefixMatchesContainKnownShortcodes() {
        let items = EmojiDataManager.shared.suggestions(forPrefix: "smi")
        let names = items.map(\.shortname)
        XCTAssertTrue(names.contains("smile"), "got \(names)")
        XCTAssertTrue(names.contains("smiley"), "got \(names)")
        XCTAssertEqual(names.first, "smile", "exact-ish alias should lead")
    }

    func testImpossiblePrefixIsEmpty() {
        XCTAssertEqual(EmojiDataManager.shared.suggestions(forPrefix: "qqq"), [])
    }

    func testEmptyPrefixIsEmpty() {
        XCTAssertEqual(EmojiDataManager.shared.suggestions(forPrefix: ""), [])
    }

    func testNoDuplicateEmojiAcrossResults() {
        let items = EmojiDataManager.shared.suggestions(forPrefix: "s", limit: 8)
        XCTAssertEqual(items.count, Set(items.map(\.id)).count, "duplicate emoji in suggestions")
    }

    func testLimitRespected() {
        let items = EmojiDataManager.shared.suggestions(forPrefix: "a", limit: 3)
        XCTAssertLessThanOrEqual(items.count, 3)
        XCTAssertFalse(items.isEmpty)
    }
}
