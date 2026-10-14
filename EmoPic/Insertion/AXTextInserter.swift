// AXTextInserter.swift
// READ-ONLY helpers over the Accessibility API: locate another app's focused
// text element, read its caret bounds (for anchoring the suggestion popup),
// and non-mutatingly verify what sits before the caret.
//
// This type deliberately performs NO text insertion. Writing text through
// `AXUIElementSetAttributeValue` or typing a Unicode keystroke payload
// (`CGEventKeyboardSetUnicodeString`) is unreliable — Messages accepts an
// `AXSelectedText` write and silently drops it, and Word ignores Unicode key
// events — while every app honors a clipboard paste. All insertion therefore
// happens via backspaces + clipboard ⌘V in AccessibilityInjector, which uses
// the read helpers here only to position the popup and to guard a swap.
//
// All failures are logged via os.Logger (Console: subsystem net.emopic.app,
// category AXTextInserter) so app-compatibility reports can be diagnosed
// without a debugger.

import Cocoa
import ApplicationServices
import os

/// Result of a NON-mutating check of whether it is safe to run a keystroke
/// based `:name:` replacement in `pid`'s focused field.
enum ReplaceSafety: Equatable {
    /// No secure field has focus — safe to delete the trigger and paste, using
    /// the colon buffer (not the field content) as the authority on what to
    /// delete. Apps like Messages that hide their text still land here.
    case safe
    /// The focused field is a secure/password field. Never delete characters or
    /// paste here.
    case secure
}

enum AXTextInserter {

    private static let log = Logger(subsystem: "net.emopic.app", category: "AXTextInserter")

    /// AX roles we consider writable text targets.
    /// ("AXSearchField" is what WebKit/Chromium expose; not in public headers.)
    /// NOTE: this is an ALLOWLIST — never add password-ish roles here.
    private static let writableRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
    ]

    /// Roles we refuse even if a future editable-roles edit would admit them.
    /// Password/secure fields expose one of these across AppKit/WebKit/
    /// Chromium. This explicit deny backs the "secure password fields are
    /// skipped" promise together with two other independent layers:
    ///   1. While secure input is active macOS does not deliver key events
    ///      to our event tap, so nothing buffers at all.
    ///   2. `replaceSafety` checks the focused element's role/subrole against
    ///      this (and `forbiddenSubroles`) and reports `.secure` before the
    ///      monitor injects any backspaces/paste, so even a mid-word focus
    ///      change into a password box can't delete or paste there.
    private static let forbiddenRoles: Set<String> = [
        "AXSecureField",
        "AXPasswordField",
    ]

    /// Subroles that mark a field secure even when its ROLE looks writable.
    /// AppKit's NSSecureTextField reports role AXTextField (which the
    /// allowlist would otherwise accept) and only reveals itself as secure
    /// through the AXSecureTextField subrole.
    private static let forbiddenSubroles: Set<String> = [
        "AXSecureTextField",
    ]

    /// Messaging timeout so a hung app can't freeze the picker.
    private static let messagingTimeout: Float = 0.2

    /// Slightly longer timeout for focused-element *discovery*. Heavier apps
    /// (Pages, Word, Messages) can take longer than 0.2 s to answer their
    /// first AX query of a session, which surfaced as a spurious "no writable
    /// focused element" that aborted colon replacement. Bounded so the tap
    /// callback stays responsive; genuinely hung apps hit the tap-disable →
    /// re-enable path instead.
    private static let discoveryTimeout: Float = 0.4

    // MARK: - Public API

    /// True when the UTF-16 units of `value` immediately before
    /// `caretLocation` are exactly `expected`. Pure so it can be unit-tested;
    /// out-of-range offsets fail closed (indexing that disagrees with the
    /// value string must never green-light a deletion).
    static func textMatchesExpectedBeforeCaret(value: String, caretLocation: Int, expected: String) -> Bool {
        let count = expected.utf16.count
        guard count > 0, caretLocation >= count, caretLocation <= value.utf16.count else { return false }
        let units = value.utf16
        let start = units.index(units.startIndex, offsetBy: caretLocation - count)
        let end = units.index(units.startIndex, offsetBy: caretLocation)
        return units[start..<end].elementsEqual(expected.utf16)
    }

    /// Whether it is safe to run a keystroke-based `:name:` replacement in
    /// `pid`'s focused field — a NON-mutating check that never writes or
    /// changes the selection.
    ///
    /// This deletes the trigger and pastes with no AX text verification, and
    /// that is safe — it's why we don't need to read the (often unreliable)
    /// field content here: the colon monitor only reaches a replacement when its
    /// buffer is intact — the event tap flushes on every click, arrow key,
    /// modifier shortcut and app switch since the pattern was typed, so the
    /// caret is provably still directly after the `:name` we watched the user
    /// type. That buffer, not a fragile AX content read (which false-aborts
    /// whenever the app hides its text or reports focus on a sibling field), is
    /// the authority on *what* to delete.
    ///
    /// The one thing that must always hard-block a backspace+paste is a secure
    /// field, so that is the only thing checked: typing happened because secure
    /// input had *not* paused the tap, but a keyboard-driven focus change can
    /// land on a password box mid-word, and backspacing into one would destroy
    /// characters. Reads the raw focused element on both the app and system-wide
    /// roots (the same dual path focus discovery uses) and rejects a secure role
    /// or subrole.
    static func replaceSafety(at pid: pid_t) -> ReplaceSafety {
        focusedFieldIsSecure(at: pid) ? .secure : .safe
    }

    /// True when the focused element (regardless of writability) reports a
    /// secure role (`AXSecureField`) or secure subrole (`AXSecureTextField`).
    private static func focusedFieldIsSecure(at pid: pid_t) -> Bool {
        guard pid > 0, NSRunningApplication(processIdentifier: pid) != nil else { return false }
        for source in [AXUIElementCreateApplication(pid), AXUIElementCreateSystemWide()] {
            AXUIElementSetMessagingTimeout(source, discoveryTimeout)
            if let element = quietFocusedChild(of: source),
               case .forbidden = writability(of: element) {
                return true
            }
        }
        return false
    }

    // MARK: - Focused element lookup

    /// Screen-space bounds of the caret (or current selection) in `pid`'s
    /// focused text element. Returned in AX global coordinates, i.e. origin
    /// at the top-left of the primary display, y growing downward — same
    /// space as `CGEvent` locations. Callers must convert to AppKit's
    /// bottom-left origin before positioning a window.
    /// Returns nil when the app exposes no writable/caret info; callers
    /// should fall back to the mouse location.
    static func caretBounds(at pid: pid_t) -> CGRect? {
        guard let element = focusedTextElement(for: pid) else { return nil }
        guard let range = selectedRange(of: element) else { return nil }

        // Parameterized AXBoundsForRange: caret (zero-length) first, then
        // the real selection length if the app refuses zero-length queries.
        var rect = CGRect.zero
        for length in [0, range.length] where length >= 0 {
            var cfRange = CFRange(location: range.location, length: length)
            guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { continue }
            var boundsValue: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue
            ) == .success, let axValue = boundsValue,
            CFGetTypeID(axValue) == AXValueGetTypeID(),
            AXValueGetValue(axValue as! AXValue, .cgRect, &rect) else { continue }
            return rect
        }
        return nil
    }

    /// The focused element of `pid` if it is a writable text target.
    ///
    /// Discovery strategy:
    ///   1. The app element's `kAXFocusedUIElementAttribute` — the fast,
    ///      normal path that works for most AppKit apps (Notes, TextEdit).
    ///   2. The system-wide element's focused element — some apps (notably
    ///      Messages, Pages, Word) return an error for strategy 1 but do
    ///      expose focus through `AXUIElementCreateSystemWide()`.
    ///   3. Container recovery — some apps report the *container* as focused
    ///      (Messages answers AXScrollArea instead of its compose field).
    ///      The focused subtree, then the containing window, get a bounded
    ///      breadth-first search for an editable descendant, preferring the
    ///      one actually marked AXFocused.
    /// Returns nil (and logs WHY — error codes + reported roles) when no
    /// path yields a writable text element, so field reports are diagnosable
    /// straight from Console.
    /// `expected` is the text the caller believes sits just before the caret
    /// (e.g. ":smile"); when provided, recovery prefers the candidate whose
    /// content actually matches it — the decisive signal when an app's focus
    /// reporting is broken. Popup positioning calls it without `expected`
    /// and falls back to pointer proximity.
    static func focusedTextElement(for pid: pid_t, expected: String? = nil) -> AXUIElement? {
        guard pid > 0, NSRunningApplication(processIdentifier: pid) != nil else {
            log.debug("focusedTextElement: no running application for pid \(pid, privacy: .public)")
            return nil
        }

        // Strategy 1: per-app focused element.
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, discoveryTimeout)
        if let element = focusedChild(of: appElement, via: "app"),
           let target = resolveFocused(element, expected: expected) {
            return target
        }

        // Strategy 2: system-wide focused element (covers apps that refuse
        // kAXFocusedUIElementAttribute on their app element). May report a
        // different container than strategy 1, so it searches independently;
        // the duplicate is bounded and only costs when the first failed.
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, discoveryTimeout)
        if let element = focusedChild(of: systemElement, via: "systemwide"),
           let target = resolveFocused(element, expected: expected) {
            return target
        }

        log.debug("focusedTextElement: no writable focused element (pid \(pid, privacy: .public))")
        return nil
    }

    /// Read kAXFocusedUIElementAttribute off `element`, logging the failure
    /// code against `source` for diagnostics.
    private static func focusedChild(of element: AXUIElement, via source: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &value)
        guard err == .success, let focused = value else {
            log.debug("focusedTextElement: \(source, privacy: .public) kAXFocusedUIElement failed err=\(err.rawValue, privacy: .public)")
            return nil
        }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            log.debug("focusedTextElement: \(source, privacy: .public) focused value is not an AXUIElement")
            return nil
        }
        return focused as! AXUIElement
    }

    /// Resolve what kAXFocusedUIElementAttribute actually reported into a
    /// usable text target: the element itself when it's editable, or — when
    /// the app gave us a container — a bounded, near-first search collecting
    /// every editable candidate, then this decision order:
    ///   1. The candidate whose content before its caret equals `expected`
    ///      (when provided) — the field the user is literally typing into.
    ///   2. A candidate marked AXFocused.
    ///   3. The candidate whose frame is nearest the pointer.
    /// This is read-only element discovery (used for popup caret anchoring);
    /// text replacement itself never writes here — see AccessibilityInjector's
    /// backspace + clipboard-paste swap.
    private static func resolveFocused(_ element: AXUIElement, expected: String?) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        switch writability(of: element) {
        case .forbidden:
            // Focus is a secure/password field — stop entirely; never hunt
            // for a "nearby" text field while a password box has focus.
            return nil
        case .roleAllowed:
            return element
        case .capable:
            log.debug("focusedTextElement: accepting role \(role(of: element) ?? "?", privacy: .public) as settable text")
            return element
        case .notWritable:
            break // container reported as focus — fall through to recovery
        }

        var state = SearchState()

        // Search the reported container's own subtree first (most apps nest
        // the compose field inside it).
        _ = searchForEditable(in: element, maxDepth: 5, state: &state)

        // Climb the parent chain searching sibling branches — in Messages
        // the compose box is a SIBLING of the transcript scroll area it
        // reports as focused, and staying local avoids burning the whole
        // budget flooding the message transcript before reaching it.
        _ = searchAdjacentBranches(of: element, state: &state)

        if state.candidates.isEmpty {
            log.debug("focusedTextElement: role \(role(of: element) ?? "?", privacy: .public) not writable and no editable element nearby")
            return nil
        }
        log.debug("focusedTextElement: \(state.candidates.count, privacy: .public) candidate(s): \(roles(of: state.candidates), privacy: .public)")

        // 1. Content match — decisive: the right field ends with what the
        // user just typed (the terminator keystroke hasn't landed yet).
        if let expected, !expected.isEmpty,
           let matched = state.candidates.first(where: { contentMatches($0, expected: expected) }) {
            return recovered(matched, "by content match")
        }

        // 2. An app-marked focused field (honored when content can't decide).
        if let focused = state.candidates.first(where: { isFocused($0) }) {
            return recovered(focused, "marked AXFocused")
        }

        // 3. Pointer proximity — the user is typing where they last clicked.
        if let nearest = nearestToPointer(state.candidates) {
            return recovered(nearest, "nearest to pointer")
        }

        return recovered(state.candidates[0], "first candidate")
    }

    /// Comma-joined roles of `elements` for a single compact log line.
    private static func roles(of elements: [AXUIElement]) -> String {
        elements.prefix(6).map { role(of: $0) ?? "?" }.joined(separator: ", ")
    }

    /// True when `element`'s text immediately before its caret equals
    /// `expected`. Skips huge values (whole-document AXValue) — those fall
    /// through to the weaker signals rather than paying an O(n) slice.
    private static func contentMatches(_ element: AXUIElement, expected: String) -> Bool {
        guard let caret = selectedRange(of: element),
              let value = stringValue(of: element),
              value.utf16.count <= 100_000 else { return false }
        return textMatchesExpectedBeforeCaret(value: value, caretLocation: caret.location, expected: expected)
    }

    /// The candidate whose frame is closest to the pointer (AX coordinates).
    private static func nearestToPointer(_ elements: [AXUIElement]) -> AXUIElement? {
        let mouseAppKit = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let pointer = CGPoint(x: mouseAppKit.x, y: primaryHeight - mouseAppKit.y) // AX space
        var best: (element: AXUIElement, distance: CGFloat)?
        for element in elements {
            guard let frame = frame(of: element) else { continue }
            let d = distance(from: pointer, to: frame)
            if best == nil || d < best!.distance { best = (element, d) }
        }
        return best?.element
    }

    /// Frame of `element` in AX global coordinates (top-left origin).
    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let position = positionValue,
              CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let axSize = sizeValue,
              CFGetTypeID(axSize) == AXValueGetTypeID(),
              AXValueGetValue(axSize as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Distance from a point to the nearest point of `rect` (0 when inside).
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func recovered(_ element: AXUIElement, _ location: String) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        log.debug("focusedTextElement: recovered \(role(of: element) ?? "?", privacy: .public) \(location, privacy: .public)")
        return element
    }

    /// Whether an element may serve as a colon-shortcut insertion target.
    private enum Writability {
        /// Secure/password element — never a target, and never searched into.
        case forbidden
        /// Role in the editable allowlist (secure subroles already rejected).
        case roleAllowed
        /// Unknown role the app itself reports as having a SETTABLE
        /// AXSelectedText — "you can insert text here" (custom engines use
        /// non-standard roles). Merely ANSWERING AXSelectedTextRange is not
        /// enough: selectable message-bubble text does that without being
        /// editable.
        case capable
        /// Container or control with no text-editing surface.
        case notWritable
    }

    /// Roles that are never text editors. Checked before the (slightly more
    /// expensive) settable probe so flooding nodes — transcript bubbles,
    /// conversation-list rows — stay cheap during tree search.
    private static let nonEditableRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXHeadingRole as String,
        kAXImageRole as String,
        kAXButtonRole as String,
    ]

    private static func writability(of element: AXUIElement) -> Writability {
        guard let role = role(of: element) else { return .notWritable }
        if forbiddenRoles.contains(role) { return .forbidden }
        if writableRoles.contains(role) {
            // NSSecureTextField reports role AXTextField but subrole
            // AXSecureTextField — reject before the allowlist accepts it.
            if let subrole = subrole(of: element), forbiddenSubroles.contains(subrole) {
                return .forbidden
            }
            return .roleAllowed
        }
        if nonEditableRoles.contains(role) { return .notWritable }
        if isSettable(element, kAXSelectedTextAttribute as String) { return .capable }
        return .notWritable
    }

    /// Shared budget + candidate memory across the search scopes, so one
    /// huge subtree (a long transcript) can't starve the branches after it.
    /// Candidates keep visit order (nearest scope first); `focused` records
    /// which ones the app marked AXFocused. Capped so pathological windows
    /// can't blow up the decision pass.
    private struct SearchState {
        var budget = 150
        private(set) var candidates: [AXUIElement] = []
        private(set) var focusedFlags: [Bool] = []

        /// Append unless already present or the list is full.
        mutating func add(_ element: AXUIElement, focused: Bool) {
            guard candidates.count < 8 else { return }
            guard !candidates.contains(where: { CFEqual($0, element) }) else { return }
            candidates.append(element)
            focusedFlags.append(focused)
        }
    }

    /// Bounded breadth-first search collecting every editable descendant,
    /// capped per branch as well as overall (see SearchState). Returns nil —
    /// results land in `state`; the caller decides between them. Secures are
    /// skipped and never descended into.
    private static func searchForEditable(in root: AXUIElement, maxDepth: Int, state: inout SearchState) -> AXUIElement? {
        var queue: [(node: AXUIElement, depth: Int)] = [(root, 0)]
        var branchBudget = min(state.budget, 30)
        while !queue.isEmpty, branchBudget > 0, state.budget > 0 {
            let (node, depth) = queue.removeFirst()
            branchBudget -= 1
            state.budget -= 1
            AXUIElementSetMessagingTimeout(node, messagingTimeout)
            switch writability(of: node) {
            case .forbidden:
                continue
            case .roleAllowed, .capable:
                state.add(node, focused: isFocused(node))
                continue // found a text field — no need to descend into it
            case .notWritable:
                if depth < maxDepth, let children = children(of: node) {
                    for child in children { queue.append((node: child, depth: depth + 1)) }
                }
            }
        }
        return nil
    }

    /// Climb the parent chain toward the window. At each ancestor: ask the
    /// ancestor for its own focused-element attribute (some containers answer
    /// it precisely even when the app level doesn't) and collect it as a
    /// candidate, then collect candidates from each other child branch.
    /// Stops at the window or after 5 levels.
    private static func searchAdjacentBranches(of element: AXUIElement, state: inout SearchState) -> AXUIElement? {
        var current = element
        for _ in 0..<5 {
            guard let parent = parent(of: current) else { break }

            if let focus = quietFocusedChild(of: parent) {
                let w = writability(of: focus)
                if w == .roleAllowed || w == .capable {
                    state.add(focus, focused: isFocused(focus))
                }
            }

            for sibling in children(of: parent) ?? [] {
                if CFEqual(sibling, current) { continue }
                _ = searchForEditable(in: sibling, maxDepth: 5, state: &state)
                if state.budget <= 0 { return nil }
            }

            current = parent
            if role(of: current) == (kAXWindowRole as String) { break }
        }
        return nil
    }

    /// The element's AXParent, if any.
    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let parent = value, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        return parent as! AXUIElement
    }

    /// kAXFocusedUIElementAttribute without logging — used while probing
    /// ancestors during recovery, where misses are routine and expected.
    private static func quietFocusedChild(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let focused = value, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return focused as! AXUIElement
    }

    /// Ask the app itself whether `attribute` can be written on this element.
    /// The definitive editability question: secure fields and static text
    /// answer false (or refuse), editable fields answer true.
    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let err = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return err == .success && settable.boolValue
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func isFocused(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    // MARK: - Helpers

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func subrole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
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
}
