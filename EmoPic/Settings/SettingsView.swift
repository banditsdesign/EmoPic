import SwiftUI

/// EmoPic Settings — standard macOS preferences window.
///
/// Apple's Settings guidance (apple-hig `settings.md`, macOS):
/// "Choosing Settings from the App menu opens a window, typically a toolbar
/// of related panes. … Use a visible, noncustomizable toolbar that marks
/// the active button; title the window for its pane … restore the last
/// pane."
///
/// This used to be an `HSplitView` with a `.sidebar` list: macOS sidebars
/// "need substantial space" (`sidebars.md`) and looked out of place in a
/// small settings window — and selecting the centered About pane appeared to
/// shove everything sideways. The standard `TabView` on macOS renders
/// exactly the expected pane-switcher toolbar (native hover/selection, no
/// content shifting), with the window titled for its pane by
/// `SettingsWindow`.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab

    init() {
        let saved = AppSettings.shared.settingsTab
        _selectedTab = State(initialValue: SettingsTab(rawValue: saved) ?? .emojiPicker)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case emojiPicker = "Emoji Picker"
        case colonShortcuts = "Colon Shortcuts"
        case excludedApps = "Excluded Apps"
        case about = "About"

        var id: String { rawValue }

        /// All icons verified to exist on the deployment target — two of
        /// the previous names (`colon.textbox`, `list.bullet.square`) are
        /// not real SF Symbols and rendered as fallback blobs.
        var icon: String {
            switch self {
            case .emojiPicker: return "face.smiling"
            case .colonShortcuts: return "keyboard"
            case .excludedApps: return "minus.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            EmojiPickerSettingsView()
                .tabItem { Label(SettingsTab.emojiPicker.rawValue, systemImage: SettingsTab.emojiPicker.icon) }
                .tag(SettingsTab.emojiPicker)

            ColonShortcutsSettingsView()
                .tabItem { Label(SettingsTab.colonShortcuts.rawValue, systemImage: SettingsTab.colonShortcuts.icon) }
                .tag(SettingsTab.colonShortcuts)

            ExcludedAppsView()
                .tabItem { Label(SettingsTab.excludedApps.rawValue, systemImage: SettingsTab.excludedApps.icon) }
                .tag(SettingsTab.excludedApps)

            AboutView()
                .tabItem { Label(SettingsTab.about.rawValue, systemImage: SettingsTab.about.icon) }
                .tag(SettingsTab.about)
        }
        .frame(width: 480, height: 400)
        .onChange(of: selectedTab) { tab in
            // Restore-the-last-pane; also drives the window title.
            settings.settingsTab = tab.rawValue
        }
    }
}

// MARK: - Emoji Picker Settings

private struct EmojiPickerSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var hotKeyStatus: String = GlobalHotKey.shared.statusDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
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

private struct ColonShortcutsSettingsView: View {
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
