// GlobalHotKey.swift
// System-wide hotkey to toggle the emoji picker, implemented with Carbon's
// RegisterEventHotKey. It works while other apps are frontmost and needs no
// extra permission.
//
// Deliberately avoids ⌘Space (Spotlight) and ⌃⌘Space (Character Viewer);
// registration of those combos fails silently, so they are not offered.

import Cocoa
import Carbon.HIToolbox

// MARK: - Hotkey presets

/// A selectable hotkey combo persisted by keyCode + Carbon modifier flags.
struct HotKeyOption: Identifiable, Hashable {
    let id: String
    let label: String
    let keyCode: Int
    let modifiers: Int // Carbon flags: cmdKey / optionKey / controlKey / shiftKey

    static let defaultOption = HotKeyOption(
        id: "opt-cmd-e", label: "⌥⌘E",
        keyCode: kVK_ANSI_E, modifiers: cmdKey | optionKey
    )

    /// Known-safe combos. All of these register successfully and shadow no
    /// common system shortcut.
    static let presets: [HotKeyOption] = [
        defaultOption,
        HotKeyOption(
            id: "ctrl-cmd-e", label: "⌃⌘E",
            keyCode: kVK_ANSI_E, modifiers: cmdKey | controlKey
        ),
        HotKeyOption(
            id: "opt-cmd-k", label: "⌥⌘K",
            keyCode: kVK_ANSI_K, modifiers: cmdKey | optionKey
        ),
        HotKeyOption(
            id: "ctrl-opt-cmd-e", label: "⌃⌥⌘E",
            keyCode: kVK_ANSI_E, modifiers: cmdKey | optionKey | controlKey
        ),
    ]

    /// Resolve persisted settings back to a preset, falling back to the default.
    static func option(keyCode: Int, modifiers: Int) -> HotKeyOption {
        presets.first { $0.keyCode == keyCode && $0.modifiers == modifiers } ?? defaultOption
    }
}

// MARK: - Registration

final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private(set) var isRegistered = false
    private(set) var lastStatus: OSStatus = noErr

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerInstalled = false

    /// Four-char code 'EMPI'.
    private static let signature: OSType = 0x454D_5049
    static let hotKeyID = 1

    private init() {}

    /// (Re-)register the hotkey from current AppSettings. Safe to call repeatedly.
    @discardableResult
    func register() -> Bool {
        unregister()
        let settings = AppSettings.shared
        guard settings.hotKeyEnabled else { return false }

        // Resolve the persisted pair through the preset table: validates the
        // values (a corrupt or hand-edited plist must not trap the UInt32
        // conversion here and crash the app at launch) and falls back to the
        // default combo for anything unknown.
        let option = settings.hotKeyOption

        installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(Self.hotKeyID))
        lastStatus = RegisterEventHotKey(
            UInt32(option.keyCode), UInt32(option.modifiers),
            id, GetApplicationEventTarget(), 0, &ref
        )
        hotKeyRef = ref
        isRegistered = lastStatus == noErr
        return isRegistered
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        hotKeyRef = nil
        isRegistered = false
    }

    /// Human-readable registration state, surfaced in Settings.
    var statusDescription: String {
        let option = HotKeyOption.option(keyCode: AppSettings.shared.hotKeyCode,
                                          modifiers: AppSettings.shared.hotKeyModifiers)
        if !AppSettings.shared.hotKeyEnabled {
            return "Disabled in settings."
        }
        if isRegistered {
            return "\(option.label) is active in any app."
        }
        return "Failed to register \(option.label) (OSStatus \(lastStatus)). Try another combo."
    }

    /// Called on the main thread when the hotkey fires.
    func handlePressed() {
        EmojiPickerWindow.shared.toggle()
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Singleton lives forever — unretained is safe and avoids a retain cycle.
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(), globalHotKeyEventHandler,
            1, &spec, userData, nil
        )
        eventHandlerInstalled = status == noErr
    }
}

/// Carbon event callback (C function pointer — must stay top-level).
private func globalHotKeyEventHandler(_ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event, EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard err == noErr, hotKeyID.id == UInt32(GlobalHotKey.hotKeyID) else {
        return OSStatus(eventNotHandledErr)
    }

    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { hotKey.handlePressed() }
    return noErr
}
