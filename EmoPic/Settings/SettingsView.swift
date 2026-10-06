import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .emojiPicker

    enum SettingsTab: String, CaseIterable, Identifiable {
        case emojiPicker = "Emoji Picker"
        case colonShortcuts = "Colon Shortcuts"
        case excludedApps = "Excluded Apps"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .emojiPicker: return "face.smiling"
            case .colonShortcuts: return "colon.textbox"
            case .excludedApps: return "list.bullet.square"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, maxWidth: 200)

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case .emojiPicker:
                        EmojiPickerSettingsView()
                    case .colonShortcuts:
                        ColonShortcutsSettingsView()
                    case .excludedApps:
                        ExcludedAppsView()
                    case .about:
                        AboutView()
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }
}

// MARK: - Emoji Picker Settings

private struct EmojiPickerSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Emoji Picker")
                .font(.title2.bold())

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
                                    ? Color.blue.opacity(0.15)
                                    : Color(NSColor.controlBackgroundColor)
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Toggle("Show Frequent in Picker", isOn: $settings.showFrequentInPicker)
                .toggleStyle(.switch)
        }
    }
}

// MARK: - Colon Shortcuts Settings

private struct ColonShortcutsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colon Shortcuts")
                .font(.title2.bold())

            Toggle("Enable :shortcut: replacement", isOn: $settings.enableColonShortcuts)
                .toggleStyle(.switch)

            SectionLabel("Skin Tone for Shortcuts")
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
                                    ? Color.blue.opacity(0.15)
                                    : Color(NSColor.controlBackgroundColor)
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Type :smile:, :heart:, etc. to insert emoji. Currently works in EmoPic's own windows; cross-app support is planned.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Excluded Apps

struct ExcludedAppsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Excluded Apps")
                .font(.title2.bold())

            Text("Colon shortcuts are disabled in these apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Search apps…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                Button { addApp() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }

            let filtered = settings.excludedApps.filter {
                searchQuery.isEmpty || $0.localizedCaseInsensitiveContains(searchQuery)
            }

            List(filtered, id: \.self) { appID in
                HStack {
                    AppNameFromBundle(bundleID: appID)
                    Spacer()
                    Button {
                        settings.excludedApps.removeAll { $0 == appID }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 200)
        }
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
            Image(systemName: "face.smiling")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("EmoPic")
                .font(.title.bold())

            Text("Version \(VersionInfo.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A native macOS menu-bar emoji picker.\nType emoji instantly — no subscriptions, no cloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Helpers

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct AppNameFromBundle: View {
    let bundleID: String

    var body: some View {
        Text(bundleID)
    }
}
