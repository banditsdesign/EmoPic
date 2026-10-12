import SwiftUI
import Cocoa

struct EmojiPickerView: View {
    @ObservedObject private var dataManager = EmojiDataManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var query: String = ""
    @State private var selectedCategory: EmojiCategory = .smileys
    @State private var selectedEmoji: EmojiItem?
    @State private var searchMode: SearchMode = .search

    // Skin tone picker
    @State private var skinToneEmoji: EmojiItem?
    @State private var skinToneSourceID: String?
    @State private var showSkinTonePicker = false

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
                // Setting now controls what its label says: the Frequent tab
                // in the picker (the menu bar no longer lists emoji at all).
                if settings.showFrequentInPicker {
                    Text("Frequent").tag(SearchMode.frequent)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: settings.showFrequentInPicker) { visible in
                if !visible && searchMode == .frequent {
                    searchMode = .search
                }
            }

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
        VStack(spacing: 0) {
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
            if emoji.supportsSkinTone {
                skinToneSourceID = emoji.id
                skinToneEmoji = emoji
                showSkinTonePicker = true
            } else {
                onSelect(emoji)
                FrequentEmojiStore.shared.record(emoji)
            }
        } label: {
            HStack(spacing: 0) {
                Text(emoji.emoji)
                    .font(.system(size: 26))
                    .frame(maxWidth: .infinity, alignment: .center)
                if emoji.supportsSkinTone {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .opacity(skinToneSourceID == emoji.id ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: skinToneSourceID)
                        .transition(.opacity)
                        .padding(.leading, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(
            isPresented: $showSkinTonePicker,
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
        ) {
            skinTonePopoverView
        }
        .onChange(of: skinToneEmoji) {
            if let emoji = skinToneEmoji {
                presentSkinTone(emoji)
            }
        }
    }

    // MARK: - Skin tone popover
    private var skinTonePopoverView: some View {
        let settings = AppSettings.shared
        return VStack(spacing: 8) {
            Text("Select skin tone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack(spacing: 4) {
                ForEach(SkinTone.allCases) { tone in
                    Button {
                        settings.selectedSkinTone = tone
                        skinToneEmoji = nil
                        skinToneSourceID = nil
                        showSkinTonePicker = false
                    } label: {
                        VStack(spacing: 2) {
                            Text(tone.emoji).font(.system(size: 22))
                            Text(tone.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            settings.selectedSkinTone == tone
                                ? Color.blue.opacity(0.15)
                                : Color(NSColor.controlBackgroundColor)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .fixedSize()
    }
}
