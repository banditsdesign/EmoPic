import Foundation

final class EmojiDataManager: ObservableObject {
    static let shared = EmojiDataManager()

    @Published private(set) var emojiList: [EmojiItem] = []
    @Published private(set) var byCategory: [EmojiCategory: [EmojiItem]] = [:]
    @Published private(set) var aliasMap: [String: EmojiItem] = [:]

    private var loaded = false

    func search(_ query: String, first count: Int = 20) -> [EmojiItem] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        if let exact = aliasMap[q] { return [exact] }
        return emojiList
            .map { ($0, $0.relevanceScore(for: q)) }
            .filter { $0.1 > 0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.name.lowercased() < b.0.name.lowercased()
            }
            .prefix(count).map { $0.0 }
    }

    func emojis(in category: EmojiCategory) -> [EmojiItem] { byCategory[category] ?? [] }

    func sortedByFrequency(_ count: Int = 50) -> [EmojiItem] {
        emojiList.sorted {
            if $0.usageScore != $1.usageScore { return $0.usageScore > $1.usageScore }
            return $0.name.lowercased() < $1.name.lowercased()
        }.prefix(count).map { $0 }
    }

    func suggested(for text: String) -> EmojiItem? {
        var t = text
        if t.hasPrefix(":") { t = String(t.dropFirst()) }
        if t.hasSuffix(":") { t = String(t.dropLast()) }
        let q = t.lowercased()
        return aliasMap[q] ?? search(q, first: 1).first
    }

    func loadEmojiData() {
        guard !loaded else { return }
        // Try bundled JSON first, then downloaded from GitHub
        if let items = loadBundled() {
            emojiList = items; rebuildIndexes(); loaded = true; return
        }
        if let items = loadFromDiskCache() {
            emojiList = items; rebuildIndexes(); loaded = true; return
        }
        downloadFromGitHub { [weak self] in
            guard let self, let items = self.loadFromDiskCache() else { return }
            self.emojiList = items; self.rebuildIndexes(); self.loaded = true
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

    private func downloadFromGitHub(_ completion: @escaping () -> Void) {
        let url = URL(string: "https://raw.githubusercontent.com/iamcal/emoji-data/master/emoji.json")!
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheURL = dir.appendingPathComponent("emopic-emoji-data.json")
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let items = EmojiDataManager.parseEmojiJSON(data) else { return }
            try? data.write(to: cacheURL)
            DispatchQueue.main.async {
                self.emojiList = items; self.rebuildIndexes(); self.loaded = true
                completion()
            }
        }
        task.resume()
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
        byCategory = [:]; aliasMap = [:]
        for e in emojiList {
            byCategory[e.category, default: []].append(e)
            for alias in e.aliases {
                let k = alias.lowercased()
                if aliasMap[k] == nil { aliasMap[k] = e }
            }
            aliasMap[e.name.lowercased()] = e
        }
        for key in Array(byCategory.keys) {
            byCategory[key]?.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
