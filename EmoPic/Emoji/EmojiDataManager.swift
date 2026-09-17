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
        let t = text.hasPrefix(":") ? String(text.dropFirst()) : text
        let t = t.hasSuffix(":") ? String(t.dropLast()) : t
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
        return parseEmojiJSON(data)
    }

    private func loadFromDiskCache() -> [EmojiItem]? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("emopic-emoji-data.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseEmojiJSON(data)
    }

    private func downloadFromGitHub(_ completion: @escaping () -> Void) {
        let url = URL(string: "https://raw.githubusercontent.com/iamcal/emoji-data/master/emoji.json")!
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheURL = dir.appendingPathComponent("emopic-emoji-data.json")
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let items = self.parseEmojiJSON(data) else { return }
            try? data.write(to: cacheURL)
            DispatchQueue.main.async {
                self.emojiList = items; self.rebuildIndexes(); self.loaded = true
                completion()
            }
        }
        task.resume()
    }

    private func parseEmojiJSON(_ data: Data) -> [EmojiItem]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return json.compactMap { j -> EmojiItem? in
            let emoji = j["emoji"] as? String ?? j["unified"] as? String ?? ""
            guard !emoji.isEmpty else { return nil }
            let name = j["name"] as? String ?? ""
            let tags = (j["tags"] as? [String] ?? []) + (j["shortcode"] as? [String] ?? [])
            let group = j["category"] as? String ?? j["group"] as? String ?? ""
            return EmojiItem(emoji: emoji, name: name, aliases: tags, version: "1.0",
                           category: EmojiCategory.from(group: group))
        }
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
        for key in byCategory.keys {
            byCategory[key]?.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
