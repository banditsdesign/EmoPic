// ColonBuffer.swift
// Pure state machine for :colon-shortcut: buffering, extracted so it can be
// unit-tested without a live event tap. EmojiShortcutMonitor feeds it
// classified keystrokes and acts on the outcomes.
//
// Design: printable keys are NEVER suppressed while buffering — everything
// types through normally. Only the terminator on a *successful* replacement is
// swallowed (see EmojiShortcutMonitor). At the moment any terminator arrives
// the typed text before the caret is exactly ":name", so the swap always
// consumes `name + 1` UTF-16 units; a space terminator is re-added after the
// emoji ("😀 ") so prose flow is preserved.

import Foundation

/// A classified keystroke fed into ColonBuffer.
enum ColonKey: Equatable {
    case character(Character)
    case delete
    case escape
    /// The frontmost app changed mid-buffer.
    case appSwitch
}

/// What the buffer decided after consuming a keystroke.
enum ColonOutcome: Equatable {
    case none
    case started
    case appended
    /// Buffer is dead; already-typed text stays exactly as typed.
    case aborted
    /// A pattern is complete. `name` excludes both colons.
    case confirmed(name: String, replaceCount: Int, trailingSpace: Bool)
}

struct ColonBuffer {
    private(set) var name: String = ""
    private(set) var isActive = false

    /// Characters allowed inside a shortcut name — ASCII only (Slack-ish rules).
    static func isNameChar(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 0x61...0x7A,          // a-z
             0x30...0x39,          // 0-9
             0x2B, 0x2D, 0x5F:     // + - _
            return true
        default:
            return false
        }
    }

    /// Characters that terminate (confirm) a pattern.
    static func isTerminator(_ c: Character) -> Bool {
        c == " " || c == "\t" || c == "\r" || c == "\n"
    }

    /// Feed one keystroke. `hasPrefix` answers whether the buffer-so-far
    /// could still match a known emoji (injectable for tests).
    mutating func consume(_ key: ColonKey, hasPrefix: (String) -> Bool) -> ColonOutcome {
        switch key {
        case .appSwitch:
            return abort()

        case .escape:
            return abort()

        case .delete:
            guard isActive else { return .none }
            if name.isEmpty {
                // Only ":" typed so far (and it's already visible in the text
                // field); let delete remove it.
                isActive = false
                return .aborted
            }
            name.removeLast()
            return .appended

        case .character(let ch):
            return consumeCharacter(ch, hasPrefix: hasPrefix)
        }
    }

    private mutating func consumeCharacter(_ ch: Character, hasPrefix: (String) -> Bool) -> ColonOutcome {
        if !isActive {
            guard ch == ":" else { return .none }
            isActive = true
            name = ""
            return .started
        }

        // Any terminator closes the pattern. At this moment the typed text
        // before the caret is exactly ":name" (the terminator itself hasn't
        // been committed yet), so the swap always consumes name+1 units.
        // The terminator keystroke is swallowed only if the swap succeeds;
        // a space is re-added after the emoji so prose flow is preserved.
        if ch == ":" || Self.isTerminator(ch) {
            let count = name.utf16.count + 1
            isActive = false
            return name.isEmpty
                ? .aborted
                : .confirmed(name: name, replaceCount: count, trailingSpace: ch == " ")
        }

        guard Self.isNameChar(ch) else { return abort() }

        name.append(ch)
        guard hasPrefix(name) else { return abort() }
        return .appended
    }

    private mutating func abort() -> ColonOutcome {
        guard isActive else { return .none }
        isActive = false
        return .aborted
    }
}
