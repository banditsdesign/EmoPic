import SwiftUI

struct MenuBarRootView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var frequent = FrequentEmojiStore.shared

    var body: some View {
        VStack(spacing: 0) {
            Button("Open Emoji Picker") {
                EmojiPickerWindow.shared.toggle()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

            Divider()

            if !frequent.items.isEmpty && settings.showFrequentInPicker {
                Text("Frequent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(frequent.items.prefix(4)) { emoji in
                        Button { insert(emoji) } label: {
                            Text(emoji.emoji).font(.system(size: 22)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            Button("Settings…") {
                SettingsWindow.shared.show()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

            Divider()

            HStack {
                Text("EmoPic").font(.subheadline.bold())
                Spacer()
                Text(VersionInfo.version).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()

            Button("Quit EmoPic", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func insert(_ emoji: EmojiItem) {
        AccessibilityInjector.insert(emoji)
    }
}
