import SwiftUI
import Cocoa

struct EmojiPickerView: View {
    @ObservedObject private var dataManager = EmojiDataManager.shared
    @State private var query: String = ""
    @State private var selectedCategory: EmojiCategory = .smileys
    @State private var selectedEmoji: EmojiItem?
    @State private var searchMode: SearchMode = .search

    enum SearchMode {
        case search, category, frequent
    }

    var onSelect: (EmojiItem) -> Void
    var presentSkinTone: (EmojiItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search / mode bar
            Picker("", selection: $searchMode) {
                Text("Search").tag(SearchMode.search)
                Text("Categories").tag(SearchMode.category)
                Text("Frequent").tag(SearchMode.frequent)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if searchMode == .search {
                TextField("Search emoji...", text: $query)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            Divider()

            // Content area
            if searchMode == .frequent {
                frequentView
            } else if searchMode == .category {
                categoryView
            } else {
                searchResultsView
            }
        }
        .frame(width: 360, height: 420)
    }

    // MARK: - Frequent view
    private var frequentView: some View {
        let frequent = FrequentEmojiStore.shared
        return ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(frequent.items) { emoji in
                    emojiCell(emoji)
                }
            }
            .padding()
        }
    }

    // MARK: - Category view
    private var categoryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EmojiCategory.allCases) { cat in
                    VStack(spacing: 2) {
                        Text(cat.icon).font(.system(size: 24))
                        Text(cat.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .onTapGesture {
                        selectedCategory = cat
                    }
                    .overlay(
                        Rectangle()
                            .fill(selectedCategory == cat ? Color.blue : Color.clear)
                            .cornerRadius(8),
                        alignment: .top
                    )
                    .padding(.top, selectedCategory == cat ? 2 : 0)
                }
            }
            .padding(.horizontal)
        }

        ScrollView {
            let emojis = dataManager.emojis(in: selectedCategory)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(emojis) { emoji in emojiCell(emoji) }
            }
            .padding()
        }
    }

    // MARK: - Search results view
    private var searchResultsView: some View {
        let results = query.isEmpty
            ? dataManager.emojis(in: .smileys)
            : dataManager.search(query, first: 50)

        return List(results, id: \.id, selection: $selectedEmoji) { emoji in
            HStack(spacing: 8) {
                Text(emoji.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading) {
                    Text(emoji.name)
                        .font(.subheadline)
                    Text(emoji.aliases.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    // MARK: - Emoji cell
    @ViewBuilder
    private func emojiCell(_ emoji: EmojiItem) -> some View {
        Button {
            let final = emoji.supportsSkinTone ? emoji.withSkinTone(AppSettings.shared.selectedSkinTone) : emoji
            onSelect(final)
            FrequentEmojiStore.shared.record(final)
        } label: {
            Text(emoji.emoji)
                .font(.system(size: 26))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
