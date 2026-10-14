// PickerSelectionTests.swift
// Movement rules and key mapping for keyboard navigation in the emoji picker.
//
// The picker window itself can't be unit-tested (it needs an NSWindow, an event
// tap and Accessibility permissions), so everything that decides *what the arrows
// do* lives in PickerSelectionModel and PickerKeyMapper — pure logic, tested here.
// Nothing in this file touches the network, the keychain or the AX APIs.

import XCTest
import AppKit
@testable import EmoPic

final class PickerSelectionTests: XCTestCase {

    private func model(_ ids: [String], stride: Int = 1) -> PickerSelectionModel {
        let m = PickerSelectionModel()
        m.verticalStride = stride
        m.update(ids)
        return m
    }

    // MARK: - Selection bookkeeping

    func testFreshListSelectsFirstItem() {
        let m = model(["a", "b", "c"])
        XCTAssertEqual(m.selectedID, "a")
    }

    func testEmptyListHasNoSelection() {
        let m = model([])
        XCTAssertTrue(m.isEmpty)
        XCTAssertNil(m.selectedID)
    }

    /// Typing in the search box replaces the list on every keystroke; the
    /// highlight must not jump back to the top while the user is mid-word.
    func testUpdateKeepsSelectionWhenItemSurvives() {
        let m = model(["cat", "dog", "dove"])
        m.move(.down)
        XCTAssertEqual(m.selectedID, "dog")
        m.update(["dog", "dove"])
        XCTAssertEqual(m.selectedID, "dog")
    }

    func testUpdateFallsBackToFirstWhenSelectionVanishes() {
        let m = model(["cat", "dog"])
        m.select("dog")
        m.update(["fish", "bird"])
        XCTAssertEqual(m.selectedID, "fish")
    }

    func testSelectIgnoresUnknownID() {
        let m = model(["a", "b"])
        m.select("nope")
        XCTAssertEqual(m.selectedID, "a")
        m.select("b")
        XCTAssertEqual(m.selectedID, "b")
    }

    func testClearResetsEverything() {
        let m = model(["a", "b"])
        m.clear()
        XCTAssertTrue(m.isEmpty)
        XCTAssertNil(m.selectedID)
    }

    // MARK: - Movement

    func testMoveOnEmptyListIsANoOp() {
        let m = model([])
        m.move(.down)
        m.move(.right)
        XCTAssertNil(m.selectedID)
    }

    func testDownWalksAndStopsAtTheEnd() {
        let m = model(["a", "b", "c"])
        m.move(.down); XCTAssertEqual(m.selectedID, "b")
        m.move(.down); XCTAssertEqual(m.selectedID, "c")
        m.move(.down); XCTAssertEqual(m.selectedID, "c", "must clamp, not wrap")
    }

    func testUpStopsAtTheTop() {
        let m = model(["a", "b", "c"])
        m.move(.up)
        XCTAssertEqual(m.selectedID, "a", "must clamp at the top, not wrap to the bottom")
    }

    /// In the 4-column category grid, ↓ has to land on the emoji directly below,
    /// four ids along — not the neighbour to the right.
    func testVerticalStrideTraversesGridByRow() {
        let ids = (1...10).map { "e\($0)" }
        let m = model(ids, stride: 4)
        m.move(.down); XCTAssertEqual(m.selectedID, "e5")
        m.move(.down); XCTAssertEqual(m.selectedID, "e9")
        m.move(.down); XCTAssertEqual(m.selectedID, "e10", "clamped to the last row")
        m.move(.up); XCTAssertEqual(m.selectedID, "e6")
    }

    /// …while ←/→ always step one cell, regardless of the row width.
    func testHorizontalKeysAlwaysStepOne() {
        let ids = (1...10).map { "e\($0)" }
        let m = model(ids, stride: 4)
        m.move(.right); XCTAssertEqual(m.selectedID, "e2")
        m.move(.left); XCTAssertEqual(m.selectedID, "e1")
    }

    func testStrideOfOneMatchesTheSearchList() {
        let m = model(["x", "y", "z"], stride: 1)
        m.move(.down); XCTAssertEqual(m.selectedID, "y")
    }

    /// A zero or negative stride would spin the selection in place; the model
    /// defends against it rather than trusting the caller.
    func testNonPositiveStrideIsTreatedAsOne() {
        let m = model(["a", "b", "c"], stride: 0)
        m.move(.down); XCTAssertEqual(m.selectedID, "b")
    }

    // MARK: - Key mapping

    func testArrowKeysMapToNavigation() {
        let plain = NSEvent.ModifierFlags(rawValue: 0)
        XCTAssertEqual(PickerKeyMapper.key(code: 126, modifiers: plain), .up)
        XCTAssertEqual(PickerKeyMapper.key(code: 125, modifiers: plain), .down)
        XCTAssertEqual(PickerKeyMapper.key(code: 123, modifiers: plain), .left)
        XCTAssertEqual(PickerKeyMapper.key(code: 124, modifiers: plain), .right)
    }

    func testEnterTabAndEscapeMap() {
        let plain = NSEvent.ModifierFlags(rawValue: 0)
        XCTAssertEqual(PickerKeyMapper.key(code: 36, modifiers: plain), .confirm)   // Return
        XCTAssertEqual(PickerKeyMapper.key(code: 76, modifiers: plain), .confirm)    // keypad Enter
        XCTAssertEqual(PickerKeyMapper.key(code: 48, modifiers: plain), .confirm)    // Tab
        XCTAssertEqual(PickerKeyMapper.key(code: 53, modifiers: plain), .dismiss)    // Escape
    }

    /// ⌘Q / ⌥⌘E / ⌃↓ belong to the app and the system, never to the list.
    func testModifiedKeysWithCommandControlOrOptionAreIgnored() {
        XCTAssertEqual(PickerKeyMapper.key(code: 125, modifiers: [.command]), .ignored)
        XCTAssertEqual(PickerKeyMapper.key(code: 36, modifiers: [.control]), .ignored)
        XCTAssertEqual(PickerKeyMapper.key(code: 53, modifiers: [.option]), .ignored)
    }

    func testShiftIsNotABlockModifier() {
        XCTAssertEqual(PickerKeyMapper.key(code: 48, modifiers: [.shift]), .confirm)
    }

    func testUnrelatedKeysFallThrough() {
        let plain = NSEvent.ModifierFlags(rawValue: 0)
        XCTAssertEqual(PickerKeyMapper.key(code: 45, modifiers: plain), .ignored)  // space
        XCTAssertEqual(PickerKeyMapper.key(code: 2, modifiers: plain), .ignored)   // "A"
    }
}
