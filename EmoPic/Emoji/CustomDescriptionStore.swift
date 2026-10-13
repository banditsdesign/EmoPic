// CustomDescriptionStore.swift
// User-assigned custom descriptions for emoji (issue #1): free-form text
// whose words become extra search keywords (picker search + :colon:
// suggestions) and show as the emoji's label/tooltip.
//
// Persistence goes through `AppSettings` (same pattern as
// `FrequentEmojiStore`); on every mutation the search indexes are refreshed
// so the very next keystroke already matches the new keyword — no relaunch.

import Foundation
import SwiftUI

final class CustomDescriptionStore: ObservableObject {
    static let shared = CustomDescriptionStore()

    /// emoji id → description text (trimmed, non-empty).
    @Published private(set) var descriptions: [String: String]

    /// Free-text guard rail per emoji — generous for prose, bounded so one
    /// entry can't bloat the prefix index.
    static let maxLength = 120

    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        descriptions = settings.customEmojiDescriptions
    }

    var isEmpty: Bool { descriptions.isEmpty }
    var count: Int { descriptions.count }

    func description(for id: String) -> String? { descriptions[id] }

    /// Store `text` for `id`. Whitespace-only text removes the entry;
    /// anything longer than `maxLength` is clamped.
    func set(_ text: String, for id: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(id)
            return
        }
        let clamped = String(trimmed.prefix(Self.maxLength))
        guard descriptions[id] != clamped else { return }
        descriptions[id] = clamped
        persistAndApply()
    }

    func remove(_ id: String) {
        guard descriptions[id] != nil else { return }
        descriptions[id] = nil
        persistAndApply()
    }

    // MARK: - Private

    /// Write through to defaults, then make the change visible to search,
    /// suggestions, and the recents grid (which hold `EmojiItem` copies).
    private func persistAndApply() {
        settings.customEmojiDescriptions = descriptions
        EmojiDataManager.shared.refreshCustomDescriptions()
        FrequentEmojiStore.shared.update()
    }
}
