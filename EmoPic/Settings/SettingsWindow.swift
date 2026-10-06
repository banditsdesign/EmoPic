import SwiftUI

final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show() {
        if window == nil {
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            window?.title = "EmoPic Settings"
            window?.titleVisibility = .visible
            window?.titlebarAppearsTransparent = false
            window?.isReleasedWhenClosed = false
        }

        let hosted = NSHostingView(rootView: SettingsView())
        hosted.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = hosted

        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
