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

    // MARK: - Precomputed search fields
    //
    // Search, relevance scoring, and colon-suggestion ranking run once per
    // keystroke (the event tap) or per search query over ~1,900 entries and
    // used to re-lowercase names several times each time. These forms are
    // built once at construction instead. Excluded from coding — plain
    // derivations of `name`/`aliases`, reconstructed on init.

    var nameLower: String = ""
    var aliasesLower: [String] = []
    var haystackLower: String = ""

    // MARK: - Custom description (issue #1)
    //
    // User-assigned free text for one emoji: extra keywords that search and
    // :colon: suggestions match, shown as a tooltip/label. User data lives in
    // `CustomDescriptionStore`; `EmojiDataManager` applies it onto items at
    // load and on every edit, so views just read these fields. Excluded from
    // coding — never leaves the machine, and the bundled dataset must not
    // carry it.

    /// The user's description verbatim (trimmed), "" when none is set.
    var customDescription: String = ""

    /// Whole description, lowercased — substring matching.
    var customLower: String = ""

    /// Description split into lowercase keyword words (punctuation stripped,
    /// single characters dropped) — exact-word matching and alias indexing.
    var customWordsLower: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, emoji, name, aliases, version, category, usageScore
    }

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
        let lowerAliases = aliases.map { $0.lowercased() }
        self.nameLower = name.lowercased()
        self.aliasesLower = lowerAliases
        self.haystackLower = ([name] + lowerAliases).joined(separator: " ").lowercased()
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
        ([name] + aliases + [customDescription]).joined(separator: " ")
    }

    /// What the UI shows as this emoji's label/tooltip: the user's custom
    /// description when set, otherwise the built-in name.
    var displayDescription: String {
        customDescription.isEmpty ? name : customDescription
    }

    func matchesQuery(_ query: String) -> Bool {
        let q = query.lowercased()
        return nameLower.contains(q) || aliasesLower.contains(q) || customLower.contains(q)
    }

    func relevanceScore(for query: String) -> Int {
        let q = query.lowercased()
        if nameLower == q { return 100 }
        if aliasesLower.contains(q) { return 100 }
        // A keyword the user explicitly tagged is an exact-intent match.
        if customWordsLower.contains(q) { return 100 }
        if nameLower.contains(q) { return 50 }
        if let idx = aliasesLower.firstIndex(where: { $0 == q }) {
            return 40 - idx * 5
        }
        return haystackLower.contains(q) ? 20 : 0
    }

    /// Check if this emoji supports skin tone modifiers.
    var supportsSkinTone: Bool {
        let keywords = ["hand", "person", "man", "woman", "girl", "boy",
                       "family", "people", "bowing", "shrugging",
                       "gesturing", "raising", "palming"]
        let name = self.name.lowercased()
        return keywords.contains { name.contains($0) }
    }

    /// Create a skin tone variant. The variant keeps the BASE emoji's id so
    /// usage recording stays keyed to one logical emoji — otherwise a
    /// skin-toned insert would record an id (`👋🏿`) that never matches any
    /// dataset entry and silently drop out of the recents list. Custom
    /// descriptions are keyed by the same id, so the variant inherits them.
    func withSkinTone(_ tone: SkinTone) -> EmojiItem {
        let combined = emoji + tone.emoji
        let variant = EmojiItem(
            emoji: combined,
            name: name,
            aliases: aliases,
            version: version,
            category: category,
            id: id
        )
        return customDescription.isEmpty ? variant : variant.applyingCustomDescription(customDescription)
    }

    // MARK: - Custom description (issue #1)

    /// Copy with a custom description applied and every derived search field
    /// (keyword list, haystack) recomputed. Empty/whitespace text clears it.
    func applyingCustomDescription(_ text: String) -> EmojiItem {
        var copy = self
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.customDescription = trimmed
        let lower = trimmed.lowercased()
        copy.customLower = lower
        // Keyword words: letters/digits/underscore/apostrophe runs, ≥2
        // chars, apostrophes then dropped inside the word — so "Bob's
        // wave!" indexes "bobs" and "wave" (searching "bobs" finds a
        // "Bob's" tag) without splitting on the apostrophe or keeping
        // bare noise like "!".
        copy.customWordsLower = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "'" })
            .map { word in word.filter { $0 != "'" } }
            .filter { $0.count >= 2 }
        // Fold the custom text into the haystack so partial queries score
        // like name/alias substrings.
        copy.haystackLower = ([nameLower] + aliasesLower + customWordsLower).joined(separator: " ")
        return copy
    }
}

/// One row in the colon-shortcut suggestion popup: the emoji plus the
/// alias that matched what the user typed (displayed as `:shortname:`).
struct EmojiSuggestion: Identifiable, Equatable {
    let id: String
    let emoji: EmojiItem
    let shortname: String
}
