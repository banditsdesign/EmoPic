import SwiftUI
import ServiceManagement

/// Panes of the Settings window, shown as toolbar items by
/// `SettingsWindow`'s `NSTabViewController`.
///
/// A SwiftUI `TabView` was tried first, but on current macOS it renders as
/// the new tab-bar style which, at this window width, collapsed all panes
/// behind a `chevron.right.2` overflow menu. The HIG is explicit: "Avoid
/// overflow" (`tab-bars.md`) and settings should be "a visible,
/// noncustomizable toolbar that marks the active button" (`settings.md`).
/// An AppKit `NSTabViewController` with `.toolbar` style is the exact
/// mechanism Xcode/System Preferences use and cannot overflow.
enum SettingsTab: String, CaseIterable, Identifiable {
    case emojiPicker = "Emoji Picker"
    case colonShortcuts = "Colon Shortcuts"
    case excludedApps = "Excluded Apps"
    case customDescriptions = "Custom Descriptions"
    case about = "About"

    var id: String { rawValue }

    /// All icons verified to exist on the deployment target — two of the
    /// earlier names (`colon.textbox`, `list.bullet.square`) are not real
    /// SF Symbols and rendered as fallback blobs.
    var icon: String {
        switch self {
        case .emojiPicker: return "face.smiling"
        case .colonShortcuts: return "keyboard"
        case .excludedApps: return "minus.circle"
        case .customDescriptions: return "text.badge.plus"
        case .about: return "info.circle"
        }
    }

    /// Fixed pane size — every pane uses it so switching never resizes or
    /// shifts anything ("panes fit their content", settings.md).
    // 420 tall: the Startup section added on top of the previous
    // skin-tone/frequent/hotkey stack; clipped at 360 with the toolbar row.
    static let paneSize = NSSize(width: 480, height: 420)

    @ViewBuilder
    func paneView() -> some View {
        switch self {
        case .emojiPicker: EmojiPickerSettingsView()
        case .colonShortcuts: ColonShortcutsSettingsView()
        case .excludedApps: ExcludedAppsView()
        case .customDescriptions: CustomDescriptionsSettingsView()
        case .about: AboutView()
        }
    }
}

// MARK: - Emoji Picker Settings

struct EmojiPickerSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var hotKeyStatus: String = GlobalHotKey.shared.statusDescription
    @State private var loginItemError: String?

    var body: some View {
        // Tallest pane: scrollable so content is reachable even if it ever
        // exceeds the fixed window (overlay indicators hide when it fits).
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Startup")
            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .toggleStyle(.switch)
            Text("Start EmoPic automatically when you sign in. You can also manage it in System Settings → General → Login Items.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            SectionLabel("Default Skin Tone")
            HStack(spacing: 8) {
                ForEach(SkinTone.allCases) { tone in
                    Button {
                        settings.selectedSkinTone = tone
                    } label: {
                        Text(tone.emoji)
                            .font(.system(size: 28))
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                settings.selectedSkinTone == tone
                                    ? Color(NSColor.selectedControlColor)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(tone.description)
                }
            }
            Text("Applied to emoji inserted via the picker and :shortcodes:.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Show Frequent in Picker", isOn: $settings.showFrequentInPicker)
                .toggleStyle(.switch)
            Text("Adds a Frequent tab with your most-used emoji to the picker window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            SectionLabel("Global Hotkey")
            HStack(spacing: 12) {
                Picker("Open picker with", selection: hotKeyBinding) {
                    ForEach(HotKeyOption.presets) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .disabled(!settings.hotKeyEnabled)

                Toggle("Enabled", isOn: $settings.hotKeyEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.hotKeyEnabled) {
                        GlobalHotKey.shared.register()
                        hotKeyStatus = GlobalHotKey.shared.statusDescription
                    }

                Spacer()
            }

            Text(hotKeyStatus)
                .font(.caption)
                .foregroundStyle(GlobalHotKey.shared.isRegistered || !settings.hotKeyEnabled ? Color.secondary : Color.red)

            Text("⌘Space is reserved by Spotlight and ⌃⌘Space by the system Character Viewer, so they are not offered.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
        }
    }

    /// Toggle backed by `SMAppService.mainApp` (macOS 13+). Only updates
    /// the persisted mirror after the system call succeeds, so the switch
    /// never claims a state the system doesn't have; failures surface in
    /// red beside the toggle and leave it on the previous value.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else if SMAppService.mainApp.status != .notRegistered {
                        try SMAppService.mainApp.unregister()
                    }
                    settings.launchAtLogin = newValue
                    loginItemError = nil
                } catch {
                    loginItemError = "Couldn’t change the login item: \(error.localizedDescription)"
                }
            }
        )
    }

    /// Binding mapping the Picker's preset id onto the persisted keyCode/modifiers.
    private var hotKeyBinding: Binding<String> {
        Binding(
            get: { settings.hotKeyOption.id },
            set: { newID in
                guard let option = HotKeyOption.presets.first(where: { $0.id == newID }) else { return }
                settings.hotKeyCode = option.keyCode
                settings.hotKeyModifiers = option.modifiers
                GlobalHotKey.shared.register()
                hotKeyStatus = GlobalHotKey.shared.statusDescription
            }
        )
    }
}

// MARK: - Colon Shortcuts Settings

struct ColonShortcutsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable :shortcode: replacement", isOn: $settings.enableColonShortcuts)
                .toggleStyle(.switch)

            Toggle("Show suggestion popup while typing", isOn: $settings.showColonSuggestions)
                .toggleStyle(.switch)
                .disabled(!settings.enableColonShortcuts)
            Text("A popup appears at the caret with matches; ↑/↓ navigate, Enter/Tab inserts, Esc dismisses. Typing the closing : also confirms. Turning this off keeps only the inline closing-: behaviour.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Requires Accessibility access; skipped in excluded apps and secure password fields. Insertions use the default skin tone from the Emoji Picker pane.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

// MARK: - Excluded Apps

struct ExcludedAppsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colon shortcuts are disabled in these apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Search apps…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                Button("Add…") { addApp() }
            }

            let filtered = settings.excludedApps.filter {
                searchQuery.isEmpty || $0.localizedCaseInsensitiveContains(searchQuery)
            }

            List {
                ForEach(filtered, id: \.self) { appID in
                    HStack {
                        AppNameFromBundle(bundleID: appID)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            settings.excludedApps.removeAll { $0 == appID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(appID) from the exclusion list")
                        .accessibilityLabel("Remove \(appID)")
                    }
                    .padding(.vertical, 2)
                }
            }
            .overlay {
                if filtered.isEmpty {
                    Text(searchQuery.isEmpty
                         ? "No excluded apps — shortcuts are active everywhere."
                         : "No apps match “\(searchQuery)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            guard let id = bundleID, !settings.excludedApps.contains(id) else { return }
            settings.excludedApps.append(id)
        }
    }
}

// MARK: - Custom Descriptions

/// Management list for user-assigned emoji descriptions (issue #1): every
/// customised emoji with its text, inline-editable and removable. New tags
/// are assigned from the picker itself (right-click an emoji), which is why
/// there is no Add button here — the emoji grid is the picker for that.
struct CustomDescriptionsSettingsView: View {
    @ObservedObject private var store = CustomDescriptionStore.shared
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your words join each emoji's keywords — search and :colon: suggestions match them — and show as the emoji's tooltip. Right-click an emoji in the picker to add one.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search customised emoji…", text: $searchQuery)
                .textFieldStyle(.roundedBorder)

            let rows = store.descriptions
                .compactMap { id, text -> (emoji: EmojiItem, text: String)? in
                    // Skip ids from older dataset versions that no longer resolve.
                    guard let emoji = EmojiDataManager.shared.itemByID[id] else { return nil }
                    return (emoji, text)
                }
                .filter {
                    searchQuery.isEmpty
                        || $0.text.localizedCaseInsensitiveContains(searchQuery)
                        || $0.emoji.name.localizedCaseInsensitiveContains(searchQuery)
                }
                .sorted { $0.emoji.name < $1.emoji.name }

            List {
                ForEach(rows, id: \.emoji.id) { row in
                    CustomDescriptionRow(emojiID: row.emoji.id,
                                       name: row.emoji.name,
                                       glyph: row.emoji.emoji,
                                       text: row.text)
                }
            }
            .overlay {
                if rows.isEmpty {
                    Text(searchQuery.isEmpty
                         ? "No custom descriptions yet — right-click an emoji in the picker to add one."
                         : "No custom descriptions match “\(searchQuery)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

/// One row: emoji glyph, built-in name, and an inline editor for the custom
/// text. Drafts commit on Return or when the field gives up focus (not per
/// keystroke), so the search indexes rebuild once per edit, not per letter.
private struct CustomDescriptionRow: View {
    let emojiID: String
    let name: String
    let glyph: String
    let text: String

    @ObservedObject private var store = CustomDescriptionStore.shared
    @State private var draft: String
    @FocusState private var focused: Bool

    init(emojiID: String, name: String, glyph: String, text: String) {
        self.emojiID = emojiID
        self.name = name
        self.glyph = glyph
        self.text = text
        _draft = State(initialValue: text)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(glyph)
                .font(.system(size: 22))
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("keywords…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) {
                        if !focused { commit() }
                    }
            }
            Spacer(minLength: 0)
            Button {
                store.remove(emojiID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove the custom description for \(name)")
            .accessibilityLabel("Remove custom description for \(name)")
        }
        .padding(.vertical, 2)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != text else { return }
        // Empty text removes the entry (store rule); the row then disappears.
        store.set(trimmed, for: emojiID)
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "face.smiling")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("EmoPic")
                .font(.title.bold())

            Text("Version \(VersionInfo.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A native macOS menu-bar emoji picker.\nType emoji instantly — no subscriptions, no cloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

// MARK: - Helpers

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
    }
}

private struct AppNameFromBundle: View {
    let bundleID: String

    var body: some View {
        Text(bundleID)
    }
}
