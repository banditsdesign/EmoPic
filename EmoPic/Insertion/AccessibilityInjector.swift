// AccessibilityInjector.swift
// Inserts emoji into other apps. The mechanism is a clipboard ⌘V (write the
// emoji, post ⌘V, restore the user's original clipboard) — the one insertion
// path every app honors. We deliberately avoid writing text via the Accessibility
// API or typing a Unicode keystroke payload, because those are ignored by
// exactly the apps that matter (Messages drops an `AXSelectedText`
// write; Word ignores Unicode key events). The Accessibility API is used only
// for reading (popup caret position, before-the-caret verification) via
// AXTextInserter. Requires Accessibility permission for the ⌘V keystroke.

import Cocoa
import ApplicationServices

struct AccessibilityInjector {
    /// Whether EmoPic currently has Accessibility (post-event) permission.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Insert an emoji into the app running as `pid` (captured before the
    /// picker stole focus) via clipboard paste. `pasteboardInsert` verifies the
    /// intended app actually holds focus before firing the synthetic ⌘V, so a
    /// slow focus restore or a mid-flow ⌘-tab can't drop the emoji into the
    /// wrong app.
    static func insert(_ emoji: EmojiItem, into pid: pid_t?) {
        guard isTrusted else {
            showAccessibilityPrompt()
            return
        }
        pasteboardInsert(emoji.emoji, intendedPID: pid)
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

    // MARK: - Keystroke replacement (colon-shortcut fallback)

    /// Delete `count` characters before the caret and insert `text` using
    /// synthetic keystrokes and the clipboard — NOT AX writes and NOT Unicode
    /// keystroke payloads. Some apps silently ignore the latter two while every
    /// app honors a paste — Messages accepts an `AXSelectedText` write and
    /// drops it, Word ignores Unicode-payload key events — so backspacing the
    /// trigger and pasting with ⌘V is what makes substitution work across
    /// Messages, Pages and Word.
    ///
    /// Callers MUST gate this so it never fires over text they did not type:
    /// an intact colon buffer (flushed on every click/arrow/shortcut/app-switch
    /// since the pattern) plus a non-secure focused field
    /// (`AXTextInserter.replaceSafety`). This deletes without re-reading the
    /// field. Backspaces and the paste are posted to the same HID stream so they
    /// arrive in order; the clipboard is restored afterwards (see `pasteNow`).
    /// Returns false when nothing could be posted (wrong frontmost app,
    /// untrusted, etc.) so callers can pass the keystroke through untouched.
    @discardableResult
    static func replaceBeforeCaretViaKeystrokes(count: Int, with text: String, at pid: pid_t) -> Bool {
        guard count > 0, count <= 64, !text.isEmpty else { return false }
        // Only ever fire while the verified target is actually frontmost.
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == pid,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        guard isTrusted else { return false }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let deleteKey: CGKeyCode = 51
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false) else { continue }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        // Paste regardless of length: ⌘V is the one insertion path every target
        // honors, so it also covers ZWJ families, flags and skin-tone sequences
        // that overflow the 4-unit Unicode keystroke payload.
        pasteNow(text)
        return true
    }

    /// Clipboard ⌘V paste for an app that already holds focus (unlike
    /// `pasteboardInsert`, no focus-settle delay — the colon flow never left
    /// the target app). Clipboard is restored 0.4 s later if untouched.
    private static func pasteNow(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        pasteWithCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard pasteboard.changeCount == ourChangeCount else { return }
            snapshot.restore(to: pasteboard)
        }
    }

    // MARK: - Clipboard fallback (with save/restore)

    /// Paste `text` via a synthetic ⌘V. The paste fires ONLY while the
    /// intended app holds focus — without that check, a slow focus restore
    /// (or the user ⌘-tabbing during the 0.1 s window) would paste the emoji
    /// into whatever app won the race. On a focus mismatch the paste is
    /// retried once after a beat; the user's clipboard is restored 0.4 s
    /// after whichever paste attempt ran, unchanged from before.
    private static func pasteboardInsert(_ text: String, intendedPID: pid_t?) {
        let pasteboard = NSPasteboard.general

        // Snapshot the user's clipboard so we can put it back afterwards.
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        // True only when the intended target (or, with no captured target,
        // any app but EmoPic) is frontmost right now.
        func focusMatches() -> Bool {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            guard let intendedPID else { return true }
            return frontmost.processIdentifier == intendedPID
        }

        func restoreIfUnchanged() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard pasteboard.changeCount == ourChangeCount else { return }
                snapshot.restore(to: pasteboard)
            }
        }

        // The picker window closes right after this call, returning focus to
        // the previously active app. Paste once focus has settled; if it
        // hasn't after the first beat, give a slow app one more chance.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if focusMatches() {
                pasteWithCommandV()
                restoreIfUnchanged()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if focusMatches() { pasteWithCommandV() }
                    restoreIfUnchanged()
                }
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
