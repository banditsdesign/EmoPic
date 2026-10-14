import Foundation
import AppKit
import Combine

// MARK: - Selection model
//
// Index-based keyboard selection for the picker's results, shared by the emoji
// grid and the search list. Deliberately free of any SwiftUI or view code so the
// movement rules can be unit-tested — the picker window itself can't be.
//
// Semantics intentionally mirror ColonSuggestionViewModel (which drives the
// :colon: popup): clamps at both ends rather than wrapping, and keeps the current
// selection across list refreshes whenever the selected item survives. Two
// pickers that behave differently with the same keys would be worse than either.
final class PickerSelectionModel: ObservableObject {
    @Published private(set) var ids: [String] = []
    @Published private(set) var selectedID: String?

    /// How far ↑/↓ travel. 1 for the one-column search list; the column count
    /// for a grid, so vertical arrows follow what the eye actually sees instead
    /// of stepping sideways into the next row's neighbour.
    var verticalStride: Int = 1

    var isEmpty: Bool { ids.isEmpty }

    /// Replace the visible ids, selecting the first unless the current selection
    /// is still on screen.
    func update(_ newIDs: [String]) {
        ids = newIDs
        if let selectedID, newIDs.contains(selectedID) { return }
        selectedID = newIDs.first
    }

    func move(_ key: PickerKey) {
        guard !ids.isEmpty else { return }
        let stride: Int
        let sign: Int
        switch key {
        case .up:        stride = max(1, verticalStride); sign = -1
        case .down:      stride = max(1, verticalStride); sign =  1
        case .left:      stride = 1;                       sign = -1
        case .right:     stride = 1;                       sign =  1
        case .confirm, .dismiss, .ignored: return
        }
        let current = selectedID.flatMap { id in ids.firstIndex(of: id) } ?? 0
        let next = min(max(current + sign * stride, 0), ids.count - 1)
        selectedID = ids[next]
    }

    func select(_ id: String) {
        guard ids.contains(id) else { return }
        selectedID = id
    }

    func clear() {
        ids = []
        selectedID = nil
    }
}

// MARK: - Key mapping
//
// Translates a raw key code plus modifier flags into an intent. Split out from
// the view (and from NSEvent) so the table is testable without a window.
enum PickerKey: Equatable {
    case up, down, left, right
    case confirm      // Return / Enter / Tab — insert the highlighted emoji
    case dismiss      // Escape
    case ignored
}

enum PickerKeyMapper {
    static let up: UInt16 = 126
    static let down: UInt16 = 125
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53

    /// Command/Control/Option combinations belong to the app (⌘Q, ⌘W, ⌘,) and
    /// are never navigation, so they fall through untouched. Shift is allowed —
    /// ⇧Tab is a reasonable way to back out of a field.
    static func key(code: UInt16, modifiers: NSEvent.ModifierFlags) -> PickerKey {
        let blockers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifiers.intersection(blockers).isEmpty else { return .ignored }
        switch code {
        case up:         return .up
        case down:       return .down
        case left:       return .left
        case right:      return .right
        case returnKey, keypadEnter, tab: return .confirm
        case escape:     return .dismiss
        default:         return .ignored
        }
    }
}
