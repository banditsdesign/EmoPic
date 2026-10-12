import Foundation

final class EmojiDataManager: ObservableObject {
    static let shared = EmojiDataManager()

    @Published private(set) var emojiList: [EmojiItem] = []
    @Published private(set) var byCategory: [EmojiCategory: [EmojiItem]] = [:]
    @Published private(set) var aliasMap: [String: EmojiItem] = [:]

    /// Every prefix of every alias/name, for O(1) "could this buffer still
    /// match something?" checks on each keystroke in the colon monitor.
    /// ~1,919 entries × a few short aliases → low megabytes, fine.
    private var shortcutPrefixes: Set<String> = []

    /// All alias keys, sorted once at load. The suggestion query finds its
    /// hits as one contiguous run via a binary search instead of filtering
    /// and sorting every key on each keystroke (docs/CODE_REVIEW_2026-10-12.md O1).
    private var sortedAliases: [String] = []

    /// id → item, plus emoji → item (recents may be recorded as either
    /// form). Lets FrequentEmojiStore resolve recents in O(1) per id
    /// instead of scanning the full list per recent (O4).
    private(set) var itemByID: [String: EmojiItem] = [:]

    private var loaded = false

    /// True if any known emoji alias/name starts with `buffer`.
    /// Used by EmojiShortcutMonitor to decide "keep buffering vs abort".
    func hasPrefix(_ buffer: String) -> Bool {
        shortcutPrefixes.contains(buffer.lowercased())
    }

    func search(_ query: String, first count: Int = 20) -> [EmojiItem] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        if let exact = aliasMap[q] { return [exact] }
        return emojiList
            .map { ($0, $0.relevanceScore(for: q)) }
            .filter { $0.1 > 0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.nameLower < b.0.nameLower
            }
            .prefix(count).map { $0.0 }
    }

    func emojis(in category: EmojiCategory) -> [EmojiItem] { byCategory[category] ?? [] }

    func sortedByFrequency(_ count: Int = 50) -> [EmojiItem] {
        emojiList.sorted {
            if $0.usageScore != $1.usageScore { return $0.usageScore > $1.usageScore }
            return $0.nameLower < $1.nameLower
        }.prefix(count).map { $0 }
    }

    func suggested(for text: String) -> EmojiItem? {
        var t = text
        if t.hasPrefix(":") { t = String(t.dropFirst()) }
        if t.hasSuffix(":") { t = String(t.dropLast()) }
        let q = t.lowercased()
        return aliasMap[q] ?? search(q, first: 1).first
    }

    /// Ranked autocomplete candidates for a partially typed colon shortcut,
    /// used by the Slack-style suggestion popup. Order: exact alias, then
    /// alias-prefix matches (recently-used first, then shorter, then alpha),
    /// then name-substring fillers. Never returns duplicate emoji.
    ///
    /// Hot path: runs once per keystroke inside the event tap, so all heavy
    /// structures (sorted alias index, lowercase search fields, recency
    /// ranks) are precomputed and the query itself is a binary search plus a
    /// small sort (docs/CODE_REVIEW_2026-10-12.md O1).
    func suggestions(forPrefix prefix: String, limit: Int = 8) -> [EmojiSuggestion] {
        let q = prefix.lowercased()
        guard !q.isEmpty else { return [] }

        var used = Set<String>()   // emoji ids already claimed
        var out: [EmojiSuggestion] = []

        func add(_ item: EmojiItem?, alias: String) {
            guard out.count < limit, let item, used.insert(item.id).inserted else { return }
            out.append(EmojiSuggestion(id: item.id, emoji: item, shortname: alias))
        }

        // 1. Exact alias match.
        add(aliasMap[q], alias: q)

        // 2. Alias prefixes, boosted by recency (FrequentEmojiStore rank).
        // Prefix hits form one contiguous run in `sortedAliases`: binary
        // search its start, walk the run, then sort just the hits.
        if out.count < limit {
            var aliasHits: [String] = []
            var lo = 0, hi = sortedAliases.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if sortedAliases[mid] < q { lo = mid + 1 } else { hi = mid }
            }
            var i = lo
            while i < sortedAliases.count, sortedAliases[i].hasPrefix(q) {
                if sortedAliases[i] != q { aliasHits.append(sortedAliases[i]) }
                i += 1
            }
            aliasHits.sort { a, b in
                let ea = aliasMap[a]!, eb = aliasMap[b]!
                let ra = FrequentEmojiStore.shared.rank(of: ea.id)
                let rb = FrequentEmojiStore.shared.rank(of: eb.id)
                if ra != rb { return ra < rb }
                if a.count != b.count { return a.count < b.count }
                return a < b
            }
            for alias in aliasHits {
                if out.count >= limit { break }
                add(aliasMap[alias], alias: alias)
            }
        }

        // 3. Name-substring fillers while slots remain.
        if out.count < limit {
            let nameHits = emojiList
                .filter { $0.nameLower.contains(q) }
                .sorted {
                    let ra = FrequentEmojiStore.shared.rank(of: $0.id)
                    let rb = FrequentEmojiStore.shared.rank(of: $1.id)
                    if ra != rb { return ra < rb }
                    return $0.nameLower < $1.nameLower
                }
            for e in nameHits {
                if out.count >= limit { break }
                add(e, alias: (e.aliases.first ?? e.name).lowercased())
            }
        }
        return out
    }

    /// Loads the dataset fully offline: bundled JSON first, then a legacy
    /// on-disk cache from the era when the app downloaded the dataset at
    /// runtime (that path was removed — see docs/CODE_REVIEW_2026-10-12.md
    /// S1: the app should trust nothing but its own signed bundle).
    /// If both are missing the UI starts empty rather than fetching anything.
    func loadEmojiData() {
        guard !loaded else { return }
        if let items = loadBundled() {
            emojiList = items; rebuildIndexes(); loaded = true; return
        }
        if let items = loadFromDiskCache() {
            emojiList = items; rebuildIndexes(); loaded = true
            // Late load (bundled JSON missing) — recents mapped over an empty
            // list at launch; refresh them now that the dataset exists.
            FrequentEmojiStore.shared.update()
        }
    }

    private func loadBundled() -> [EmojiItem]? {
        guard let url = Bundle.main.url(forResource: "emoji-data", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return Self.parseEmojiJSON(data)
    }

    private func loadFromDiskCache() -> [EmojiItem]? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("emopic-emoji-data.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.parseEmojiJSON(data)
    }

    // Internal (not private) for unit-test access to the parsing surface.
    static func parseEmojiJSON(_ data: Data) -> [EmojiItem]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return json.compactMap { j -> EmojiItem? in
            // Build the emoji character from the `unified` hex codepoint sequence
            let emoji = Self.emojiFromUnified(j["unified"] as? String ?? "")
            guard !emoji.isEmpty else { return nil }
            let name = j["name"] as? String ?? ""
            // Aliases: read from short_names array, fallback to short_name string
            let aliases: [String] = {
                if let arr = j["short_names"] as? [String] { return arr }
                if let single = j["short_name"] as? String { return [single] }
                return []
            }()
            let group = j["category"] as? String ?? ""
            let addedIn = j["added_in"] as? String ?? "1.0"
            return EmojiItem(
                emoji: emoji,
                name: name,
                aliases: aliases,
                version: addedIn,
                category: EmojiCategory.from(group: group)
            )
        }
    }

    /// Convert a unified hex codepoint sequence (e.g. "1F600" or "1F469-200D-1F469-200D-1F467-200D-1F467")
    /// into a Unicode emoji string. Internal (not private) for unit-test access.
    static func emojiFromUnified(_ unified: String) -> String {
        let parts = unified.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return "" }
        let codepoints = parts.compactMap { UInt32($0, radix: 16) }
        guard !codepoints.isEmpty else { return "" }
        let scalars = codepoints.compactMap { UnicodeScalar($0) }
        guard !scalars.isEmpty else { return "" }
        var result = ""
        for scalar in scalars {
            result.append(String(scalar))
        }
        return result.trimmingCharacters(in: .controlCharacters)
    }

    private func rebuildIndexes() {
        byCategory = [:]; aliasMap = [:]; shortcutPrefixes = []
        itemByID = [:]
        for e in emojiList {
            byCategory[e.category, default: []].append(e)
            // Recents may be stored as either the item id or the raw emoji.
            itemByID[e.id] = e
            if itemByID[e.emoji] == nil { itemByID[e.emoji] = e }
            for alias in e.aliases {
                let k = alias.lowercased()
                if aliasMap[k] == nil { aliasMap[k] = e }
                insertPrefixes(of: k)
            }
            aliasMap[e.nameLower] = e
            insertPrefixes(of: e.nameLower)
        }
        sortedAliases = aliasMap.keys.sorted()
        for key in Array(byCategory.keys) {
            byCategory[key]?.sort { $0.nameLower < $1.nameLower }
        }
    }

    /// Insert every prefix ("s", "sm", "smi", … , word) of a lowercase word.
    private func insertPrefixes(of word: String) {
        guard !word.isEmpty else { return }
        var prefix = ""
        for ch in word {
            prefix.append(ch)
            shortcutPrefixes.insert(prefix)
        }
    }
}
