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
        guard let screen = NSScreen.main, let window else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.maxX - size.width - 8
        let y = visible.maxY - size.height - 8
        window.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func insert(_ emoji: EmojiItem) {
        AccessibilityInjector.insert(emoji)
    }
}
