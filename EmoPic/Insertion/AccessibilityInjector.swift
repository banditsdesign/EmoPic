import Foundation
import Cocoa
import ApplicationServices

struct AccessibilityInjector {
    /// Whether EmoPic currently has Accessibility (post-event) permission.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func insert(_ emoji: EmojiItem) {
        guard isTrusted else {
            showAccessibilityPrompt()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emoji.emoji, forType: .string)

        // The picker window closes right after this call, returning focus to the
        // previously active app. Paste once focus has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteWithCommandV()
        }
    }

    /// Show an alert directing the user to grant Accessibility permission.
    private static func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText =
            "EmoPic needs Accessibility access to insert emoji into text fields in other apps.\n\n" +
            "Open System Settings to grant permission."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Open the macOS System Settings app directly to the Accessibility / Privacy page.
    private static func openAccessibilitySettings() {
        // Tries the Ventura+ settings URL, falls back to macOS 12 settings URL
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.Accessibility-privacy"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func pasteWithCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKeyCode: CGKeyCode = 9 // 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
