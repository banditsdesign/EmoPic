import Foundation
import SwiftUI

final class FrequentEmojiStore: ObservableObject {
    static let shared = FrequentEmojiStore()
    @Published private(set) var items: [EmojiItem] = []

    /// id → rank (0 = most recent). Precomputed once per recents change
    /// instead of being rebuilt inside EmojiDataManager's suggestion query
    /// on every keystroke (2026-10-12 code review, O1/O4).
    private(set) var rankByID: [String: Int] = [:]

    func update() {
        let recent = AppSettings.shared.recentEmojiIDs
        let byID = EmojiDataManager.shared.itemByID
        items = recent.compactMap { byID[$0] }.prefix(12).map { $0 }
        rankByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    }

    /// Recency rank of an emoji id; `.max` when not recently used.
    func rank(of id: String) -> Int { rankByID[id] ?? .max }

    func record(_ emoji: EmojiItem) {
        AppSettings.shared.recordUsage(emoji)
        update()
    }
}