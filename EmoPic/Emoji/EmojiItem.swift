// EmojiItem.swift
// The data model representing a single emoji character with its names and aliases.

import Foundation

/// Represents a single emoji with its characters, name, aliases, and metadata.
struct EmojiItem: Identifiable, Codable, Hashable, Sendable {
    /// The unique identifier for this emoji entry.
    let id: String

    /// The Unicode emoji character(s). May be multiple code points.
    let emoji: String

    /// Human-readable name (e.g., "grinning face")
    let name: String

    /// Searchable aliases/keywords (e.g., ["grin", "happy", "smile"])
    let aliases: [String]

    /// Unicode/emoji version.
    let version: String

    /// Category this emoji belongs to.
    let category: EmojiCategory

    /// Usage score for ranking frequently used emoji.
    var usageScore: Int = 0

    // MARK: - Convenience

    init(
        emoji: String,
        name: String,
        aliases: [String],
        version: String,
        category: EmojiCategory,
        id: String? = nil
    ) {
        self.emoji = emoji
        self.name = name
        self.aliases = aliases
        self.version = version
        self.category = category
        self.id = id ?? emoji
    }

    // MARK: - Hashable, Equatable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: EmojiItem, rhs: EmojiItem) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Search helpers

    var searchableText: String {
        ([name] + aliases).joined(separator: " ")
    }

    func matchesQuery(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q) || aliases.contains { $0.lowercased() == q }
    }

    func relevanceScore(for query: String) -> Int {
        let q = query.lowercased()
        if name.lowercased() == q { return 100 }
        if aliases.contains(q) { return 100 }
        if name.lowercased().contains(q) { return 50 }
        if let idx = aliases.firstIndex(where: { $0.lowercased() == q }) {
            return 40 - idx * 5
        }
        return searchableText.lowercased().contains(q) ? 20 : 0
    }

    /// Check if this emoji supports skin tone modifiers.
    var supportsSkinTone: Bool {
        let keywords = ["hand", "person", "man", "woman", "girl", "boy",
                       "family", "people", "bowing", "shrugging",
                       "gesturing", "raising", "palming"]
        let name = self.name.lowercased()
        return keywords.contains { name.contains($0) }
    }

    /// Create a skin tone variant.
    func withSkinTone(_ tone: SkinTone) -> EmojiItem {
        let combined = emoji + tone.emoji
        return EmojiItem(
            emoji: combined,
            name: name,
            aliases: aliases,
            version: version,
            category: category
        )
    }
}
