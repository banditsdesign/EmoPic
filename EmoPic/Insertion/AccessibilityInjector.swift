import Foundation
import Cocoa
import ApplicationServices

struct AccessibilityInjector {
    static func insert(_ emoji: EmojiItem) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            insertViaPasteboard(emoji.emoji)
        }
    }

    private static func insertViaPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        var error = AXError.success
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        error = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement
        )

        if error == .success, let element = focusedElement as? AXUIElement {
            let pasteAction = "AXShowInputWindow"
            AXUIElementPerformAction(element, pasteAction as CFString)
        }

        // Fallback — simulate Cmd+V via System Events
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
            var err: NSDictionary?
            if let s = NSAppleScript(source: script) {
                s.executeAndReturnError(&err)
            }
        }
    }
}
