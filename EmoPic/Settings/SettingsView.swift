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
        case .about: return "info.circle"
        }
    }

    /// Fixed pane size — every pane uses it so switching never resizes or
    /// shifts anything ("panes fit their content", settings.md).
    static let paneSize = NSSize(width: 480, height: 360)

    @ViewBuilder
    func paneView() -> some View {
        switch self {
        case .emojiPicker: EmojiPickerSettingsView()
        case .colonShortcuts: ColonShortcutsSettingsView()
        case .excludedApps: ExcludedAppsView()
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
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
