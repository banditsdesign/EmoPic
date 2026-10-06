// AXTextInserter.swift
// Inserts text directly into another app's focused text element via the
// Accessibility API — no clipboard involved.
//
// Callers that get `false` back should fall back to clipboard paste
// (see AccessibilityInjector). Requires Accessibility trust; the
// AccessibilityInjector gates on AXIsProcessTrusted() before calling.

import Cocoa
import ApplicationServices

enum AXTextInserter {

    /// AX roles we consider writable text targets.
    /// ("AXSearchField" is what WebKit/Chromium expose; not in public headers.)
    private static let writableRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
    ]

    /// Messaging timeout so a hung app can't freeze the picker.
    private static let messagingTimeout: Float = 0.2

    // MARK: - Public API

    /// Insert `text` at the caret of `pid`'s focused text element.
    /// Returns false if the app is gone, unresponsive, or has no writable
    /// focused element.
    @discardableResult
    static func insert(_ text: String, at pid: pid_t) -> Bool {
        guard !text.isEmpty, let element = focusedTextElement(for: pid) else { return false }
        let err = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        )
        return err == .success
    }

    /// Insert into the current frontmost app, skipping our own bundle
    /// (used by menu-bar quick inserts where the panel may be frontmost).
    @discardableResult
    static func insertIntoFrontmostApp(_ text: String, excluding bundleID: String?) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if let bundleID, app.bundleIdentifier == bundleID { return false }
        return insert(text, at: app.processIdentifier)
    }

    /// Replace `count` UTF-16 units immediately before the caret with `text`.
    /// The selection is verified before the write; the original caret
    /// position is restored on any failure. Used by colon shortcuts to
    /// swap a typed `:name:` pattern for the emoji after the fact.
    @discardableResult
    static func replaceBeforeCaret(count: Int, with text: String, at pid: pid_t) -> Bool {
        guard count > 0, !text.isEmpty, let element = focusedTextElement(for: pid) else { return false }
        guard let caret = selectedRange(of: element) else { return false }

        let target = NSRange(location: caret.location - count, length: count)
        guard target.location >= 0 else { return false }
        guard setSelectedRange(target, on: element) else { return false }

        // Verify the selection captured exactly `count` UTF-16 units before writing.
        var selectedValue: CFTypeRef?
        let verifyErr = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedValue
        )
        guard verifyErr == .success,
              let selected = selectedValue as? String,
              selected.utf16.count == count else {
            _ = setSelectedRange(caret, on: element)
            return false
        }

        let writeErr = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        )
        if writeErr != .success {
            _ = setSelectedRange(caret, on: element)
            return false
        }
        return true
    }

    // MARK: - Focused element lookup

    /// The focused element of `pid` if it is a writable text target.
    static func focusedTextElement(for pid: pid_t) -> AXUIElement? {
        guard pid > 0, NSRunningApplication(processIdentifier: pid) != nil else { return nil }

        // Per-app elements respond far more reliably than the system-wide element.
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

        var focusedValue: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        )
        guard err == .success, let focused = focusedValue else { return nil }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        guard let role = role(of: element), writableRoles.contains(role) else { return nil }
        return element
    }

    // MARK: - Helpers

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedRange(of element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func setSelectedRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axValue = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, axValue
        ) == .success
    }
}
