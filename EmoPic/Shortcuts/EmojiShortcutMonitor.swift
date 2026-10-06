// EmojiShortcutMonitor.swift
// Detects :colon-shortcut: patterns in the current app's text fields and
// replaces them with the corresponding emoji character.
//
// Uses addLocalMonitorForEvents for keyDown detection (works within the
// current application). Cross-app monitoring can be added later with a
// CGEventTap (requires Accessibility permission).

import Cocoa

final class EmojiShortcutMonitor {
    static let shared = EmojiShortcutMonitor()

    private var eventMonitor: Any?
    private var isMonitoring = false

    // State for tracking colon patterns
    private var currentField: NSResponder?
    private var buffer: [Character] = []
    private var isProcessing = false

    // MARK: - Public

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        buffer = []
        isProcessing = false
        setupEventMonitor()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        cleanup()
    }

    func setEnabled(_ enabled: Bool) {
        AppSettings.shared.enableColonShortcuts = enabled
        if enabled { start() } else { stop() }
    }

    // MARK: - Event Monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    private func cleanup() {
        buffer = []
        isProcessing = false
        currentField = nil

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Key Down Handler

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else { return event }

        let chars = event.charactersIgnoringModifiers ?? ""
        let key = chars.first

        // Check if shortcuts are enabled
        guard AppSettings.shared.enableColonShortcuts else { return event }

        // Check excluded apps
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let bundleID = frontApp?.bundleIdentifier,
           AppSettings.shared.isAppExcluded(bundleID) {
            return event
        }

        // Detect colon key and start buffering
        if key == ":" {
            return handleColonEvent()
        }

        // Check if we're in buffer mode
        if !buffer.isEmpty {
            return handleBufferChar(key)
        }

        return event
    }

    // MARK: - Colon Detection

    private func handleColonEvent() -> NSEvent? {
        // Find the first responder (focused text field)
        guard let field = findFirstResponder() else { return nil }
        currentField = field

        buffer = []

        // Suppress the colon — it will be restored by the pattern replacement
        return nil
    }

    private func handleBufferChar(_ key: Character?) -> NSEvent? {
        guard let key = key else {
            buffer = []; currentField = nil
            return nil
        }

        // Check if this ends the pattern
        if key == ":" || key.isWhitespace || key == "\t" {
            return handleBufferEnd(key)
        }

        buffer.append(key)

        // Suppress typing while buffering
        return nil
    }

    private func handleBufferEnd(_ endChar: Character) -> NSEvent? {
        guard let field = currentField,
              let fieldText = getFieldText(from: field) else {
            buffer = []; currentField = nil
            return nil
        }

        // Build the pattern
        let trimmed = String(buffer).trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 0 else {
            buffer = []; currentField = nil
            return nil
        }

        let pattern = ":" + trimmed + ":"

        // Look up emoji
        guard let emoji = EmojiDataManager.shared.suggested(for: pattern) else {
            buffer = []; currentField = nil
            return nil
        }

        // Apply skin tone for shortcuts
        let finalEmoji: EmojiItem
        if AppSettings.shared.selectedSkinTone != .default && emoji.supportsSkinTone {
            finalEmoji = emoji.withSkinTone(AppSettings.shared.selectedSkinTone)
        } else {
            finalEmoji = emoji
        }

        // Find and replace the pattern using NSString
        guard let nsText = fieldText as NSString? else {
            buffer = []; currentField = nil
            return nil
        }
        let nsRange = nsText.range(of: pattern)
        guard nsRange.location != NSNotFound else {
            buffer = []; currentField = nil
            return nil
        }

        isProcessing = true
        buffer = []; currentField = nil

        // Replace using NSString
        let newText = nsText.replacingCharacters(in: nsRange, with: finalEmoji.emoji + " ")

        // Apply replacement
        applyTextReplacement(to: field, text: newText)

        // Record usage
        FrequentEmojiStore.shared.record(finalEmoji)

        // Suppress the end character
        return nil
    }

    // MARK: - Text Replacement

    /// Apply a text replacement to a responder that supports text editing.
    private func applyTextReplacement(to responder: NSResponder, text: String) {
        // For NSTextView
        if let textView = responder as? NSTextView {
            // Replace the entire text
            let oldString = textView.string
            let newRange = NSRange(oldString.startIndex..<oldString.endIndex, in: oldString)
            textView.textStorage?.replaceCharacters(in: newRange, with: text)
            return
        }

        // For NSTextField / NSSecureTextField
        if let textField = responder as? NSTextField {
            textField.stringValue = text
            return
        }
        if let secureField = responder as? NSSecureTextField {
            secureField.stringValue = text
            return
        }
    }

    // MARK: - Helpers

    /// Extract plain text from a responder.
    private func getFieldText(from responder: NSResponder) -> String? {
        // NSTextView
        if let textView = responder as? NSTextView {
            return textView.string
        }

        // NSTextField
        if let textField = responder as? NSTextField {
            return textField.stringValue
        }

        // NSSecureTextField
        if let secureField = responder as? NSSecureTextField {
            return secureField.stringValue
        }

        return nil
    }

    /// Find the current first responder in the key window.
    private func findFirstResponder() -> NSResponder? {
        guard let window = NSApp.keyWindow else { return nil }
        return window.firstResponder
    }
}
