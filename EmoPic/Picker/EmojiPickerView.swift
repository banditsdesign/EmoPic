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
    /// id of the search row currently showing the tone chooser — keyed per
    /// row so all rows don't present the popover at once.
    @State private var searchSkinToneID: String?

    /// Single pick path for every tab (grid cells and search rows), so a
    /// click behaves identically everywhere ("Keep visual and interaction
    /// behavior consistent" — apple-hig design-principles.md Familiarity).
    /// Tone-capable emoji open the chooser anchored to the source; `fromSearch`
    /// keys the popover to the clicked list row instead of the grid cell.
    private func handlePick(_ emoji: EmojiItem, fromSearch: Bool = false) {
        if emoji.supportsSkinTone {
            if fromSearch {
                searchSkinToneID = emoji.id
            } else {
                skinToneSourceID = emoji.id
                skinToneEmoji = emoji
                showSkinTonePicker = true
            }
        } else {
            onSelect(emoji)
            FrequentEmojiStore.shared.record(emoji)
        }
    }

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
    //
    // Rows used to be plain content in a `List(selection:)` — a click only
    // updated `selectedEmoji` and nothing acted on it, so nothing was ever
    // inserted (the grid tabs worked because their cells are Buttons).
    // Each row is now a full-width Button on the same pick path.
    private var searchResultsView: some View {
        let results = query.isEmpty
            ? dataManager.emojis(in: .smileys)
            : dataManager.search(query, first: 50)

        return List(results, id: \.id, selection: $selectedEmoji) { emoji in
            Button {
                selectedEmoji = emoji
                handlePick(emoji, fromSearch: true)
            } label: {
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
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle()) // whole row is clickable, not just glyphs
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: Binding(
                    get: { searchSkinToneID == emoji.id },
                    set: { if !$0 { searchSkinToneID = nil } }
                ),
                attachmentAnchor: .point(.trailing),
                arrowEdge: .trailing
            ) {
                skinToneChooser { searchSkinToneID = nil }
            }
        }
        .listStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    // MARK: - Emoji cell
    @ViewBuilder
    private func emojiCell(_ emoji: EmojiItem) -> some View {
        Button {
            handlePick(emoji)
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
            skinToneChooser {
                skinToneEmoji = nil
                skinToneSourceID = nil
                showSkinTonePicker = false
            }
        }
        .onChange(of: skinToneEmoji) {
            if let emoji = skinToneEmoji {
                presentSkinTone(emoji)
            }
        }
    }

    // MARK: - Skin tone chooser (shared by grid cells and search rows)
    private func skinToneChooser(clear: @escaping () -> Void) -> some View {
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
                        clear()
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
