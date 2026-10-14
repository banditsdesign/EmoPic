import Cocoa
import SwiftUI

final class EmojiPickerWindow {
    static let shared = EmojiPickerWindow()

    private var window: NSWindow?

    /// App that was frontmost before the picker stole focus — emoji targets it.
    private var previousApp: NSRunningApplication?

    func toggle() {
        if let w = window, w.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        // The caret suggestion popup belongs to another app's text context;
        // it has no business floating over our own picker.
        ColonSuggestionPanel.shared.hide()

        // Capture the insertion target *before* we activate and steal focus.
        if window?.isVisible != true {
            previousApp = NSWorkspace.shared.frontmostApplication
        }

        if window == nil {
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 380, height: 460),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            window?.title = "EmoPic"
            window?.styleMask.insert(.fullSizeContentView)
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.isReleasedWhenClosed = false
        }

        let hosted = NSHostingView(rootView: EmojiPickerView(
            onSelect: { [weak self] emoji in
                self?.insert(emoji)
                self?.close()
            },
            presentSkinTone: { _ in },
            // Escape closes the picker (the view clears the search field first).
            onDismiss: { [weak self] in self?.close() }
        ))
        hosted.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = hosted

        positionBelowStatusItem()

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
        returnFocus()
    }

    /// Hands keyboard focus back to whatever app was frontmost before the picker
    /// opened.
    ///
    /// `show()` explicitly activates our own app, and closing a window does not
    /// undo that: with an accessory (LSUIElement) app the previous app is not
    /// restored automatically, so after an insert you were left staring at an
    /// inactive desktop and had to ⌘-tab or click back into your document. A
    /// Spotlight-style picker should land you exactly where you were.
    private func returnFocus() {
        guard let app = previousApp,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isActive else { return }
        // macOS 14 wants the app handing focus over to name itself; at this
        // moment that is us, which is exactly the requirement.
        app.activate(from: .current, options: [])
    }

    private func positionBelowStatusItem() {
        guard let screen = NSScreen.main, let window else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.maxX - size.width - 8
        let y = visible.maxY - size.height - 8
        window.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func insert(_ emoji: EmojiItem) {
        // Never target our own process: if Settings (or the picker itself)
        // was frontmost when the hotkey fired, `previousApp` is EmoPic. The
        // AX write would hit our own UI and, failing that, the clipboard
        // fallback would ⌘V-paste into whichever app won the focus race
        // after close. Drop the pick instead of guessing a destination.
        guard previousApp?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        AccessibilityInjector.insert(emoji, into: previousApp?.processIdentifier)
    }
}
