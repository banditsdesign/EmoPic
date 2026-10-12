import SwiftUI
import Combine

/// Standard macOS settings window host.
///
/// Per apple-hig `settings.md` (macOS): settings open as a window with
/// "a toolbar of related panes"; "dim minimize/maximize (… panes fit their
/// content)"; "title the window for its pane … restore the last pane".
/// The panes themselves live in `SettingsView` (standard `TabView`, which
/// renders the native toolbar pane-switcher).
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 480, height: 400),
                // .titled + .closable only: minimize/zoom stay dimmed
                // because each pane is fixed-size and fits its content.
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.isReleasedWhenClosed = false
            w.center() // once; later opens remember the user's position

            // Title follows the active pane; @Published replays its current
            // value, so the restored last pane titles the window at once.
            AppSettings.shared.$settingsTab
                .receive(on: RunLoop.main)
                .sink { [weak w] tab in w?.title = tab }
                .store(in: &cancellables)

            window = w
        }

        window?.contentView = NSHostingView(rootView: SettingsView())
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
