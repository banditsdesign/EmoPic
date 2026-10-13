import SwiftUI

/// Menu bar dropdown content, rendered as a *native* NSMenu through
/// `.menuBarExtraStyle(.menu)`.
///
/// Apple's "The menu bar" guidance (apple-hig skill, `the-menu-bar.md`):
/// **"Display a menu — not a popover — when people click it."** The old
/// `.window` style hosted custom-styled buttons, which is why items had no
/// standard padding and no hover highlight. A native menu provides the
/// system metrics, accent-colored mouseover selection, separators, and
/// shortcut display for free — exactly what people expect on macOS.
///
/// Frequent emoji intentionally do not appear here: recency is surfaced in
/// the picker's Frequent tab and in colon-suggestion ranking, keeping this
/// menu short and scannable ("Be mindful of menu length", menus.md).
struct MenuBarRootView: View {
    @ObservedObject private var monitor = EmojiShortcutMonitor.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Open Emoji Picker") {
            EmojiPickerWindow.shared.toggle()
        }

        // T10: subtle hint while Accessibility access is missing — the colon
        // feature is paused, the picker itself stays usable. The grant
        // observer in EmojiShortcutMonitor refreshes this as soon as the
        // user returns from System Settings.
        if !monitor.isAccessibilityGranted {
            Button {
                monitor.requestPermissionIfNeeded()
                monitor.openAccessibilitySettings()
            } label: {
                Label("Accessibility access needed", systemImage: "lock.shield")
            }
        }

        Divider()

        Button("Settings…") {
            SettingsWindow.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        // Issue #2: manual update check. Grouped with the app-management items
        // rather than lengthening the top of the menu, retitles itself once an
        // update has been found, and goes dim while Sparkle is mid-session (it
        // rejects re-entrant checks).
        Button(updater.menuItemTitle) {
            updater.checkNow()
        }
        .disabled(!updater.canCheckForUpdates)

        Divider()

        // Minimal info footer; plain Text renders as a disabled menu item.
        Text("EmoPic \(VersionInfo.version)")

        Button("Quit EmoPic") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
