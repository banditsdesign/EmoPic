import Cocoa
import SwiftUI

final class EmojiPickerWindow {
    static let shared = EmojiPickerWindow()

    private var window: NSWindow?

    func toggle() {
        if let w = window, w.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 380, height: 460),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            window?.title = "EmoPic"
            window?.styleMask.insert(.fullSizeContentView)
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.isReleasedWhenClosed = false
        }

        let hosted = NSHostingView(rootView: EmojiPickerView(
            onSelect: { [weak self] emoji in
                self?.insert(emoji)
                self?.close()
            },
            presentSkinTone: { _ in }
        ))
        hosted.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = hosted

        positionBelowStatusItem()

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    private func positionBelowStatusItem() {
        guard let screen = NSScreen.main else { return }
        let barHeight = NSStatusBar.system.thickness
        guard let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) else { return }
        let rect = statusItem.button?.frame ?? CGRect(x: 0, y: screen.frame.maxY - 24, width: 40, height: 24)
        let windowY = rect.maxY + barHeight + 4
        let windowX = rect.minX + rect.width / 2 - 190
        window?.setFrame(CGRect(x: windowX, y: windowY, width: 380, height: 460), display: true)
    }

    private func insert(_ emoji: EmojiItem) {
        AccessibilityInjector.insert(emoji)
    }
}

extension EmojiPickerWindow: NSWindowDelegate {
    nonisolated func windowDidResignMain(_ notification: Notification) {
        // Don't close automatically
    }
}
