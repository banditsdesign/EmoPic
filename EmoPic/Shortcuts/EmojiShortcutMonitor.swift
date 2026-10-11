// EmojiShortcutMonitor.swift
// Detects :colon-shortcut: patterns in ANY app's text fields and replaces
// them with the corresponding emoji, system-wide.
//
// Architecture (M3 rewrite of the old app-local NSEvent monitor):
// - A session CGEventTap observes keyDown events. Printable characters are
//   NEVER suppressed while buffering — ":name:" types through normally.
//   On confirm (closing ":" / space / tab / return) the already-typed
//   pattern is swapped for the emoji via AXTextInserter.replaceBeforeCaret.
//   If the Accessibility write fails, the terminator keystroke passes
//   through untouched — zero dropped characters, worst case the literal
//   ":name:" stays visible.
// - Never calls NSWorkspace or AppKit-inspecting APIs per keystroke:
//   frontmost app state is cached from activation notifications.
// - The tap runs on the main run loop, so all buffer state is
//   main-thread-only (no locks).
//
// Requires Accessibility permission; start() is a no-op until granted.
// EmojiShortcutMonitor.refreshAccessibilityStatus() picks the tap up as soon
// as permission flips, without relaunch.

import Cocoa
import ApplicationServices

final class EmojiShortcutMonitor: ObservableObject {
    static let shared = EmojiShortcutMonitor()

    /// Surfaced in the menu-bar panel (T10): shows a hint row while false.
    @Published private(set) var isAccessibilityGranted = false
    @Published private(set) var isMonitoring = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var buffer = ColonBuffer()

    // Cached frontmost-app state (updated on activation notifications only —
    // never inside the tap callback).
    private var frontmostPID: pid_t = 0
    private var frontmostBundleID: String?
    private var workspaceObserver: NSObjectProtocol?

    private let ownBundleID = Bundle.main.bundleIdentifier

    private init() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    // MARK: - Public

    /// Show the one-time system prompt (launch) and return current trust.
    @discardableResult
    func requestPermissionIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            refreshAccessibilityStatus()
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: emojiShortcutTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Permission revoked between check and creation, or secure input.
            refreshAccessibilityStatus()
            return
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isMonitoring = true

        cacheFrontmostApp()
        installActivationObserverIfNeeded()
        refreshAccessibilityStatus()
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isMonitoring = false
        flush()

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        AppSettings.shared.enableColonShortcuts = enabled
        if enabled { start() } else { stop() }
    }

    /// Cheap re-check, called on every app activation. Starts/stops the tap
    /// when permission flips at runtime (the accepted T10 flow: grant →
    /// shortcuts activate without relaunch).
    func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityGranted {
            isAccessibilityGranted = trusted
        }
        if trusted && !isMonitoring && AppSettings.shared.enableColonShortcuts {
            start()
        } else if !trusted && isMonitoring {
            stop()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Frontmost cache

    private func installActivationObserverIfNeeded() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.frontmostPID = app?.processIdentifier ?? 0
            self.frontmostBundleID = app?.bundleIdentifier
            self.handleFrontmostChanged()
        }
    }

    private func cacheFrontmostApp() {
        let app = NSWorkspace.shared.frontmostApplication
        frontmostPID = app?.processIdentifier ?? 0
        frontmostBundleID = app?.bundleIdentifier
    }

    private func handleFrontmostChanged() {
        // App switch mid-buffer → abort.
        flush()
        refreshAccessibilityStatus()
    }

    private func flush() {
        buffer = ColonBuffer()
    }

    // MARK: - Tap callback bridge (main thread)

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap after slow processing or secure input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            flush()
            return nil
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard AppSettings.shared.enableColonShortcuts else { flush(); return Unmanaged.passUnretained(event) }

        // Skip our own app: picker panel, settings window, search fields.
        // (Session tap fires for our keys too; NSApp is a local-state read.)
        if NSApp.isActive || frontmostBundleID == ownBundleID {
            flush()
            return Unmanaged.passUnretained(event)
        }

        // Skip excluded / unknown apps. Unknown bundle IDs (secure overlays)
        // don't buffer either — safety first.
        guard let bundleID = frontmostBundleID,
              !AppSettings.shared.isAppExcluded(bundleID),
              frontmostPID > 0 else {
            flush()
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            // A real shortcut fired mid-word — abort.
            flush()
            return Unmanaged.passUnretained(event)
        }

        guard let key = classify(event) else {
            flush()
            return Unmanaged.passUnretained(event)
        }

        let outcome = buffer.consume(key) { EmojiDataManager.shared.hasPrefix($0) }

        switch outcome {
        case .none, .started, .appended, .aborted:
            // Type through. The buffer is either tracking, dead, or done.
            return Unmanaged.passUnretained(event)

        case .confirmed(let name, let replaceCount, let trailingSpace):
            return confirm(name: name, replaceCount: replaceCount, trailingSpace: trailingSpace, event: event)
        }
    }

    /// Turn a CGEvent into a ColonKey, or nil if we can't classify it.
    private func classify(_ event: CGEvent) -> ColonKey? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case 51: return .delete           // Delete / Backspace
        case 53: return .escape          // Escape
        case 36, 76: return .character("\r") // Return / keypad Enter (confirm)
        case 48: return .character("\t")     // Tab (confirm)
        case 56, 60, 57: return nil     // shift / right-shift / caps — ignore, don't flush (":" itself needs shift!)
        default: break
        }

        // Extract the typed unicode text (single character only).
        var length = 0
        var chars = [UInt16](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length == 1, let ch = String(utf16CodeUnits: chars, count: length).first else {
            return nil
        }
        return .character(ch)
    }

    // MARK: - Replacement

    private func confirm(name: String, replaceCount: Int, trailingSpace: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        defer { flush() }

        guard let emoji = EmojiDataManager.shared.suggested(for: ":" + name + ":") else {
            // Valid prefix but no exact match — leave the literal text as typed.
            return Unmanaged.passUnretained(event)
        }

        var finalEmoji = emoji
        if AppSettings.shared.selectedSkinTone != .default && emoji.supportsSkinTone {
            finalEmoji = emoji.withSkinTone(AppSettings.shared.selectedSkinTone)
        }

        let replacement = finalEmoji.emoji + (trailingSpace ? " " : "")
        let success = AXTextInserter.replaceBeforeCaret(
            count: replaceCount, with: replacement, at: frontmostPID
        )

        if success {
            FrequentEmojiStore.shared.record(finalEmoji)
            return nil // swallow the terminator; the typed pattern was already swapped
        }
        return Unmanaged.passUnretained(event) // nothing lost — pattern stays visible
    }
}

// MARK: - C callback (top-level, allocation-light)

private func emojiShortcutTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<EmojiShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type, event)
}
