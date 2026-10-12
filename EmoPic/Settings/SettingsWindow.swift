import AppKit
import SwiftUI

/// Standard macOS settings window host.
///
/// Panes are switched by an AppKit `NSTabViewController` with `.toolbar`
/// style — the same mechanism Xcode and System Preferences use: a row of
/// labeled toolbar buttons across the top, marking the active pane, that
/// can never overflow behind a chevron menu. This is what the HIG asks for:
/// "Choosing Settings … opens a window, typically a toolbar of related
/// panes. Use a visible, noncustomizable toolbar that marks the active
/// button; title the window for its pane … restore the last pane"
/// (apple-hig `settings.md`), reinforced by "Avoid overflow"
/// (`tab-bars.md`).
///
/// The earlier SwiftUI `TabView` was wrong for this window width: macOS
/// collapsed the panes into a `chevron.right.2` overflow menu. The panes
/// themselves remain SwiftUI, hosted per tab.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var tabController: SettingsTabViewController?

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.title = "Settings"   // reassert: some AppKit phase blanked it
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: - Construction

    private func build() {
        let controller = SettingsTabViewController()
        controller.tabStyle = .toolbar // top toolbar of pane buttons

        for tab in SettingsTab.allCases {
            let item = NSTabViewItem(identifier: tab.rawValue)
            item.label = tab.rawValue
            item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.rawValue)

            let hosting = NSHostingController(rootView: tab.paneView())
            // Identical fixed size everywhere: switching panes never
            // resizes or shifts the window ("panes fit their content").
            hosting.preferredContentSize = SettingsTab.paneSize
            item.viewController = hosting

            controller.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: controller)
        // .titled + .closable only: minimize/zoom stay dimmed — every pane
        // is the same fixed size (settings.md).
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // .expanded (not .preference): title renders on its own titlebar
        // row (the pane name — the earlier .preference assembly left the
        // title as "Untitled"), the tab strip sits on the toolbar row, and
        // pane content begins strictly below it. With the earlier setup the
        // unified chrome consumed content height: the first control of the
        // Startup pane hid under the strip and the hotkey status clipped at
        // the bottom edge of a non-resizable window.
        window.toolbarStyle = .expanded
        window.tabbingMode = .disallowed
        window.setContentSize(SettingsTab.paneSize)

        // Restore the last pane.
        let last = SettingsTab.allCases.firstIndex {
            $0.rawValue == AppSettings.shared.settingsTab
        } ?? 0
        controller.selectedTabViewItemIndex = last

        // Title: plain "Settings" (matches the ⌘, menu item people read).
        // Per-pane titling was unreliable in this assembly — the title kept
        // reverting to "Untitled" — so pin one honest title and reassert it
        // whenever the window appears, whatever AppKit does in between.
        window.title = "Settings"
        window.titleVisibility = .visible
        controller.onTabChange = { paneTitle in
            AppSettings.shared.settingsTab = paneTitle
        }

        self.window = window
        self.tabController = controller
        if window.frameAutosaveName.isEmpty {
            // Remember user-moved position across launches (settings.md:
            // "people expect a window to reopen where they left it").
            window.setFrameAutosaveName("EmoPicSettingsWindow")
            if !window.setFrameUsingName("EmoPicSettingsWindow") {
                window.center()
            }
        }
    }
}

/// Subclass (rather than an external `NSTabViewDelegate`) so the controller
/// keeps its own toolbar bookkeeping — we only observe selection changes.
private final class SettingsTabViewController: NSTabViewController {
    var onTabChange: ((String) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let id = tabViewItem?.identifier as? String else { return }
        onTabChange?(id)
    }
}
