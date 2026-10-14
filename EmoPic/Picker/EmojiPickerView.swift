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
    /// id of the tone-capable emoji whose chooser is open — the single
    /// source of truth for BOTH grid cells and search rows, so only one
    /// popover can ever be presented (review B3: a shared isPresented bool
    /// once let every grid cell try to present at the same time).
    @State private var skinToneSourceID: String?
    /// id of the search row currently showing the tone chooser — keyed per
    /// row so all rows don't present the popover at once.
    @State private var searchSkinToneID: String?
    /// Emoji whose custom-description sheet is open (issue #1). One sheet at
    /// the picker level — per-cell sheets would race with the tone popovers.
    @State private var editingEmoji: EmojiItem?

    /// Which result the keyboard is pointing at. Kept out of this view as its
    /// own object so the movement rules are unit-testable; the view decides what
    /// is visible and what a pick means.
    @StateObject private var selection = PickerSelectionModel()

    /// Single pick path for every tab (grid cells and search rows), so a
    /// click behaves identically everywhere ("Keep visual and interaction
    /// behavior consistent" — apple-hig design-principles.md Familiarity).
    /// Tone-capable emoji open the chooser anchored to the source; `fromSearch`
    /// keys the popover to the clicked list row instead of the grid cell.
    /// Keyboard confirms route through here too, so Enter inserts exactly what a
    /// click would.
    private func handlePick(_ emoji: EmojiItem, fromSearch: Bool = false) {
        if emoji.supportsSkinTone {
            if fromSearch {
                searchSkinToneID = emoji.id
            } else {
                skinToneSourceID = emoji.id
                skinToneEmoji = emoji
            }
        } else {
            onSelect(emoji)
            FrequentEmojiStore.shared.record(emoji)
        }
    }

    enum SearchMode: Equatable {
        case search, category, frequent
    }

    var onSelect: (EmojiItem) -> Void
    var presentSkinTone: (EmojiItem) -> Void
    /// Escape with nothing left to clear. Supplied by the window; defaulted so
    /// the view stays usable wherever it is embedded.
    var onDismiss: () -> Void = {}

    // MARK: - Keyboard navigation
    //
    // Exactly one list is on screen at a time, so one selection model covers all
    // three modes — the grid, the two-column Frequent grid and the search list
    // are the same problem with different widths.

    /// The visible results, in the order the user sees them.
    private var visibleEmojis: [EmojiItem] {
        switch searchMode {
        case .frequent:
            return FrequentEmojiStore.shared.items
        case .category:
            return dataManager.emojis(in: selectedCategory)
        case .search:
            return query.isEmpty
                ? dataManager.emojis(in: .smileys)
                : dataManager.search(query, first: 50)
        }
    }

    /// Columns in the visible layout. Vertical arrows step a whole row in a grid
    /// and a single item in the one-column search list.
    private var columnCount: Int {
        switch searchMode {
        case .search: return 1
        case .frequent: return 2
        case .category: return 4
        }
    }

    private var visibleIDs: [String] { visibleEmojis.map(\.id) }

    private var highlightedEmoji: EmojiItem? {
        guard let id = selection.selectedID else { return nil }
        return visibleEmojis.first { $0.id == id }
    }

    /// While a sheet or the skin-tone popover is up, the keyboard belongs to it:
    /// Return/Cancel and the arrow keys must reach the presented UI, not move the
    /// list behind it.
    private var keyboardNavBlocked: Bool {
        skinToneSourceID != nil || searchSkinToneID != nil || editingEmoji != nil
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !keyboardNavBlocked else { return false }
        let key = PickerKeyMapper.key(code: event.keyCode, modifiers: event.modifierFlags)
        switch key {
        case .ignored:
            return false
        case .dismiss:
            // macOS convention: Escape clears the search field first and only
            // closes the picker when there is nothing left to undo.
            if !query.isEmpty {
                query = ""
                return true
            }
            onDismiss()
            return true
        case .confirm:
            guard let emoji = highlightedEmoji else { return false }
            handlePick(emoji, fromSearch: searchMode == .search)
            return true
        default:
            selection.verticalStride = columnCount
            selection.move(key)
            return true
        }
    }

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
            .onChange(of: settings.showFrequentInPicker) { _, visible in
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
        .background(PickerKeyCatcher(isEnabled: !keyboardNavBlocked, onKey: handleKeyEvent))
        // Keep the model's view of the list in step with what's on screen: new
        // ids when the results change, and the right row width when the mode does.
        .onChange(of: visibleIDs) {
            selection.verticalStride = columnCount
            selection.update(visibleIDs)
        }
        .onChange(of: searchMode) {
            selection.verticalStride = columnCount
            selection.update(visibleIDs)
        }
        .sheet(
            isPresented: Binding(
                get: { editingEmoji != nil },
                set: { if !$0 { editingEmoji = nil } }
            )
        ) {
            if let emoji = editingEmoji {
                EmojiDescriptionEditor(emoji: emoji)
            }
        }
    }

    // MARK: - Frequent view
    private var frequentView: some View {
        let frequent = FrequentEmojiStore.shared
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(frequent.items) { emoji in
                        emojiCell(emoji)
                    }
                }
                .padding()
            }
            .onChange(of: selection.selectedID) { scrollToSelection(proxy) }
        }
    }

    /// Keeps the keyboard-highlighted cell on screen as the arrows walk the list.
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = selection.selectedID else { return }
        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
    }

    // MARK: - Category view
    //
    // Was a horizontally scrolling strip of nine icon cards: too wide for
    // the window (the cards had `maxWidth: .infinity` inside a horizontal
    // ScrollView), and the selected card drew an opaque blue `Rectangle`
    // *over* its icon and label, hiding the very thing it marked.
    // Nine mutually exclusive choices in a compact popover window:
    // apple-hig `tab-views.md` — "Avoid more than six tabs … for six or
    // more, consider a pop-up menu of view options" — so a pop-up button
    // (`pop-up-buttons.md`) it is: native `NSPopUpButton`, always shows
    // the current category, fits any width.
    private var categoryView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(EmojiCategory.allCases) { cat in
                        Text("\(cat.icon)  \(cat.displayName)").tag(cat)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer()

                Text("\(dataManager.emojis(in: selectedCategory).count) emoji")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    let emojis = dataManager.emojis(in: selectedCategory)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(emojis) { emoji in emojiCell(emoji) }
                    }
                    .padding()
                }
                .onChange(of: selection.selectedID) { scrollToSelection(proxy) }
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

        return ScrollViewReader { proxy in
            List(results, id: \.id, selection: $selectedEmoji) { emoji in
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
                            // The user's own tag (issue #1), accented so it reads
                            // as theirs, not part of the built-in metadata.
                            if !emoji.customDescription.isEmpty {
                                Text(emoji.customDescription)
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle()) // whole row is clickable, not just glyphs
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .help(emoji.displayDescription)
                .contextMenu {
                    Button(editingContextTitle(for: emoji)) { editingEmoji = emoji }
                }
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
                // Keyboard highlight as a tinted wash rather than the macOS blue
                // selection bar: it marks what Enter will insert without hiding
                // the glyph, and stays visible in both appearances.
                .listRowBackground(
                    isHighlighted(emoji) ? Color.accentColor.opacity(0.16) : Color.clear
                )
            }
            .listStyle(.plain)
            .frame(minWidth: 0, maxWidth: .infinity)
            .onChange(of: selection.selectedID) { scrollToSelection(proxy) }
        }
    }

    /// Whether this emoji is the one the keyboard is currently pointing at.
    private func isHighlighted(_ emoji: EmojiItem) -> Bool {
        selection.selectedID == emoji.id
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted(emoji) ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        // Explicit view id so ScrollViewReader can follow the keyboard into view.
        .id(emoji.id)
        .help(emoji.displayDescription)
        .contextMenu {
            Button(editingContextTitle(for: emoji)) { editingEmoji = emoji }
        }
        // Scoped cursor change via push/pop — SwiftUI has no .pointOnHover()
        // on macOS (checked the Xcode 27 SDK interface), and set()/set()
        // alternatives clobber cursors owned by other views.
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(
            isPresented: Binding(
                get: { skinToneSourceID == emoji.id },
                set: { if !$0 { skinToneEmoji = nil; skinToneSourceID = nil } }
            ),
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
        ) {
            skinToneChooser {
                skinToneEmoji = nil
                skinToneSourceID = nil
            }
        }
        .onChange(of: skinToneEmoji) {
            if let emoji = skinToneEmoji {
                presentSkinTone(emoji)
            }
        }
    }

    /// Context-menu label for the description editor. Shows the existing tag
    /// (truncated) so users can spot customised emoji without hovering.
    private func editingContextTitle(for emoji: EmojiItem) -> String {
        let custom = emoji.customDescription
        guard !custom.isEmpty else { return "Edit Description…" }
        let preview = custom.count > 24 ? String(custom.prefix(24)) + "…" : custom
        return "Edit Description — \(preview)"
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

// MARK: - Custom description editor (issue #1)

/// Sheet for assigning free-form keywords to one emoji, opened from the
/// picker's context menu (grid cells and search rows). The words join the
/// emoji's searchable keywords and the text becomes its label/tooltip;
/// empty text (or Remove) clears it.
struct EmojiDescriptionEditor: View {
    let emoji: EmojiItem

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(emoji: EmojiItem) {
        self.emoji = emoji
        _text = State(initialValue: emoji.customDescription)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom description")
                .font(.headline)

            HStack(spacing: 10) {
                Text(emoji.emoji)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(emoji.name)
                        .font(.subheadline)
                    Text(emoji.aliases.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            TextField("e.g. bob, office mascot", text: $text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) {
                    if text.count > CustomDescriptionStore.maxLength {
                        text = String(text.prefix(CustomDescriptionStore.maxLength))
                    }
                }
                .onSubmit(save)

            Text("Its words join this emoji's search keywords — picker search and :colon: suggestions will match them — and it shows as the emoji's tooltip. Separate words with spaces; clear the text to remove.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if !emoji.customDescription.isEmpty {
                    Button("Remove") {
                        CustomDescriptionStore.shared.remove(emoji.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        CustomDescriptionStore.shared.set(text, for: emoji.id)
        dismiss()
    }
}
