// HotKeyOptionTests.swift
// Guards the hotkey preset table: no system-reserved combos, unique presets,
// and default = ⌥⌘E.

import XCTest
import Carbon.HIToolbox
@testable import EmoPic

final class HotKeyOptionTests: XCTestCase {

    func testDefaultIsOptionCommandE() {
        XCTAssertEqual(HotKeyOption.defaultOption.keyCode, kVK_ANSI_E)
        XCTAssertEqual(HotKeyOption.defaultOption.modifiers, cmdKey | optionKey)
    }

    func testNoReservedSystemCombos() {
        // ⌘Space is Spotlight, ⌃⌘Space is the system Character Viewer.
        let forbidden: [(keyCode: Int, modifiers: Int)] = [
            (kVK_Space, cmdKey),
            (kVK_Space, cmdKey | controlKey),
        ]
        for preset in HotKeyOption.presets {
            for combo in forbidden {
                XCTAssertFalse(
                    preset.keyCode == combo.keyCode && preset.modifiers == combo.modifiers,
                    "Preset \(preset.label) collides with a reserved system shortcut"
                )
            }
        }
    }

    func testPresetsAreUnique() {
        let ids = Set(HotKeyOption.presets.map(\.id))
        XCTAssertEqual(ids.count, HotKeyOption.presets.count)
        let combos = Set(HotKeyOption.presets.map { "\($0.keyCode):\($0.modifiers)" })
        XCTAssertEqual(combos.count, HotKeyOption.presets.count)
        XCTAssertTrue(HotKeyOption.presets.count >= 3 && HotKeyOption.presets.count <= 4)
    }

    func testOptionLookupFallsBackToDefault() {
        let known = HotKeyOption.presets[2]
        XCTAssertEqual(HotKeyOption.option(keyCode: known.keyCode, modifiers: known.modifiers), known)

        let bogus = HotKeyOption.option(keyCode: -1, modifiers: 0xFFFF)
        XCTAssertEqual(bogus, HotKeyOption.defaultOption)
    }
}
