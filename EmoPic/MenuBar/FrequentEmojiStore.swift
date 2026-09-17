import Foundation
import SwiftUI

final class FrequentEmojiStore: ObservableObject {
    static let shared = FrequentEmojiStore()
    @Published private(set) var items: [EmojiItem] = []

    func update() {
        let recent = AppSettings.shared.recentEmojiIDs
        let all = EmojiDataManager.shared.emojiList
        items = recent.compactMap { id -> EmojiItem? in
            all.first { $0.id == id || $0.emoji == id }
        }.prefix(12).map { $0 }
    }

    func record(_ emoji: EmojiItem) {
        AppSettings.shared.recordUsage(emoji)
        update()
    }
}
