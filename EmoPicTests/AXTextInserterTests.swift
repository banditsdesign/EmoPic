// AXTextInserterTests.swift
// Pure before-the-caret verification used by the keystroke fallback path —
// the guard that decides whether deleting `count` characters is safe when an
// app refuses AX range selection/writes. Everything here must fail closed:
// any doubt about what precedes the caret means no deletion.

import XCTest
@testable import EmoPic

final class AXTextInserterTests: XCTestCase {

    func testExactMatchBeforeCaret() {
        XCTAssertTrue(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: "hello :smi", caretLocation: 10, expected: ":smi"))
    }

    func testMismatchAborts() {
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: "hello :smi", caretLocation: 10, expected: ":smile"))
        // Same length, different content — would silently destroy user text.
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: "hello :xyz!", caretLocation: 10, expected: ":smi"))
    }

    func testCaseSensitivity() {
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: "hello :SMI", caretLocation: 10, expected: ":smi"))
    }

    func testCaretTooEarlyAborts() {
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: ":s", caretLocation: 1, expected: ":smi"))
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: "", caretLocation: 0, expected: ":smi"))
    }

    func testCaretBeyondValueAborts() {
        // Caret index disagreeing with the value string (app indexing
        // attachments differently, stale range) must never green-light deletion.
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: ":smi", caretLocation: 99, expected: ":smi"))
    }

    func testEmptyExpectedAborts() {
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: "hello", caretLocation: 5, expected: ""))
    }

    /// Offsets are UTF-16 units, matching how callers compute `count`
    /// (`buffer.name.utf16.count + 1`) and how AX reports the caret —
    /// emoji (surrogate pairs) count as 2 units, not 1 character.
    func testOffsetsAreUTF16Units() {
        let value = "😀 :smi"
        let units = value.utf16.count // 2 (emoji) + 5
        XCTAssertTrue(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: value, caretLocation: units, expected: ":smi"))
        // The same offset interpreted as Character count (6) points at the
        // wrong slice and must not match.
        XCTAssertFalse(AXTextInserter.textMatchesExpectedBeforeCaret(
            value: value, caretLocation: 6, expected: ":smi"))
    }
}
