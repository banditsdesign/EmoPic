// AccessibilityInjector.swift
// Inserts emoji into other apps. Strategy:
//   1. Accessibility API (AXTextInserter) — writes straight into the target's
//      focused text element, never touching the clipboard.
//   2. Clipboard fallback — writes the emoji, posts ⌘V, then restores the
//      user's original clipboard contents.

import Cocoa
import ApplicationServices

struct AccessibilityInjector {
    /// Whether EmoPic currently has Accessibility (post-event) permission.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Insert an emoji into the app running as `pid` (captured before the
    /// picker stole focus). Falls back to clipboard paste when the target
    /// exposes no writable AX text element.
    static func insert(_ emoji: EmojiItem, into pid: pid_t?) {
        guard isTrusted else {
            showAccessibilityPrompt()
            return
        }

        if let pid, AXTextInserter.insert(emoji.emoji, at: pid) {
            return
        }

        pasteboardInsert(emoji.emoji)
    }

    /// Convenience for callers without a captured target (menu-bar quick
    /// inserts). Inserts into the frontmost app unless that is EmoPic itself,
    /// in which case the paste happens after focus settles.
    static func insert(_ emoji: EmojiItem) {
        insert(emoji, into: frontmostOtherAppPID())
    }

    private static func frontmostOtherAppPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return app.processIdentifier
    }

    // MARK: - Clipboard fallback (with save/restore)

    private static func pasteboardInsert(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Snapshot the user's clipboard so we can put it back afterwards.
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        // The picker window closes right after this call, returning focus to the
        // previously active app. Paste once focus has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteWithCommandV()

            // Restore the original clipboard shortly after the paste — but only
            // if the user hasn't copied something newer in the meantime.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard pasteboard.changeCount == ourChangeCount else { return }
                snapshot.restore(to: pasteboard)
            }
        }
    }

    /// Copy of every pasteboard item and its types, restorable later.
    private struct ClipboardSnapshot {
        private var items: [NSPasteboardItem] = []

        init(pasteboard: NSPasteboard) {
            for item in pasteboard.pasteboardItems ?? [] {
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                items.append(copy)
            }
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return } // clipboard was empty before; leave it empty
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - Permission prompt

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

    // MARK: - ⌘V posting

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
