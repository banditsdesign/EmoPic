// ColonBufferTests.swift
// Colon buffer state-machine rules (abort / shrink-on-delete / confirm) with
// an injectable hasPrefix, plus the real prefix index built by
// EmojiDataManager against the bundled dataset.

import XCTest
@testable import EmoPic

final class ColonBufferTests: XCTestCase {

    // Fake prefix table for the state-machine tests — prefix-closed over
    // the words we exercise.
    private func hasPrefix(_ s: String) -> Bool {
        ["smile", "thumb", "thumbsup"].contains { $0.hasPrefix(s) }
    }

    // MARK: - Starting

    func testStartsOnColonOnly() {
        var buf = ColonBuffer()
        XCTAssertEqual(buf.consume(.character("x"), hasPrefix: hasPrefix), .none)
        XCTAssertFalse(buf.isActive)
        XCTAssertEqual(buf.consume(.character(":"), hasPrefix: hasPrefix), .started)
        XCTAssertTrue(buf.isActive)
    }

    func testBufferingValidChars() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.character("s"), hasPrefix: hasPrefix), .appended)
        XCTAssertEqual(buf.consume(.character("m"), hasPrefix: hasPrefix), .appended)
        XCTAssertEqual(buf.name, "sm")
    }

    // MARK: - Abort rules

    func testAbortsOnImpossiblePrefix() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        _ = buf.consume(.character("s"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.character("z"), hasPrefix: hasPrefix), .aborted)
        XCTAssertFalse(buf.isActive)
        // Already-typed ":sz" stays as-is; nothing more is tracked.
        XCTAssertEqual(buf.consume(.character("m"), hasPrefix: hasPrefix), .none)
    }

    func testAbortsOnUppercase() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.character("S"), hasPrefix: hasPrefix), .aborted)
    }

    func testAbortsOnAppSwitchAndEscape() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        _ = buf.consume(.character("s"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.appSwitch, hasPrefix: hasPrefix), .aborted)

        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.escape, hasPrefix: hasPrefix), .aborted)
        XCTAssertFalse(buf.isActive)
    }

    // MARK: - Delete

    func testShrinkOnDelete() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        _ = buf.consume(.character("s"), hasPrefix: hasPrefix)
        _ = buf.consume(.character("m"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.delete, hasPrefix: hasPrefix), .appended)
        XCTAssertEqual(buf.name, "s")
        // Deleting the last buffered char leaves the lone ":" typed in the
        // field; buffer stays alive so retyping continues to track.
        XCTAssertEqual(buf.consume(.delete, hasPrefix: hasPrefix), .appended)
        XCTAssertEqual(buf.name, "")
        XCTAssertTrue(buf.isActive)
        // A second delete removes the visible ":" → buffer dies.
        XCTAssertEqual(buf.consume(.delete, hasPrefix: hasPrefix), .aborted)
        XCTAssertFalse(buf.isActive)
    }

    // MARK: - Confirm rules

    func testConfirmOnColonTerminator() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        for ch in "smile" { XCTAssertEqual(buf.consume(.character(ch), hasPrefix: hasPrefix), .appended) }
        // Typed ":smile" with the closing ":" landing now → replace ":smile" (6), swallow ":"
        XCTAssertEqual(
            buf.consume(.character(":"), hasPrefix: hasPrefix),
            .confirmed(name: "smile", replaceCount: 6, trailingSpace: false)
        )
        XCTAssertFalse(buf.isActive)
    }

    func testConfirmOnSpaceTerminator() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        for ch in "smile" { _ = buf.consume(.character(ch), hasPrefix: hasPrefix) }
        // space terminator on ":smile": replace ":smile" (6), emoji re-followed by a space
        XCTAssertEqual(
            buf.consume(.character(" "), hasPrefix: hasPrefix),
            .confirmed(name: "smile", replaceCount: 6, trailingSpace: true)
        )
    }

    func testConfirmOnTabAndReturn() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        for ch in "thumbsup" { _ = buf.consume(.character(ch), hasPrefix: hasPrefix) }
        XCTAssertEqual(
            buf.consume(.character("\t"), hasPrefix: hasPrefix),
            .confirmed(name: "thumbsup", replaceCount: 9, trailingSpace: false)
        )
    }

    func testEmptyBufferTerminatorAborts() {
        var buf = ColonBuffer()
        _ = buf.consume(.character(":"), hasPrefix: hasPrefix)
        XCTAssertEqual(buf.consume(.character(":"), hasPrefix: hasPrefix), .aborted)
        XCTAssertEqual(buf.consume(.character(" "), hasPrefix: hasPrefix), .none)
    }

    // MARK: - Name-char classification

    func testValidNameChars() {
        for c in "abz09+-_" { XCTAssertTrue(ColonBuffer.isNameChar(c), "\(c) should be valid") }
        for c: Character in ["A", "!", " ", ":", "é"] { XCTAssertFalse(ColonBuffer.isNameChar(c)) }
    }

    // MARK: - Real dataset prefix index (T8 acceptance)

    func testHasPrefixAgainstBundledData() {
        let manager = EmojiDataManager.shared
        manager.loadEmojiData()
        XCTAssertFalse(manager.emojiList.isEmpty, "bundled emoji-data.json must load in the test host")
        XCTAssertTrue(manager.hasPrefix("smi"))
        XCTAssertTrue(manager.hasPrefix("smile"))
        XCTAssertTrue(manager.hasPrefix("thumbsu"))
        XCTAssertTrue(manager.hasPrefix("zzz")) // "zzz" is a real iamcal shortcode for 😴
        XCTAssertFalse(manager.hasPrefix("qqq")) // only "question" starts with q
        XCTAssertFalse(manager.hasPrefix("")) // prefixes start at length 1
    }
}
