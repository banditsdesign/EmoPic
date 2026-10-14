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

    /// The one title the window ever shows. Pinned because `NSTabViewController`
    /// in `.toolbar` style rewrites `window.title` from the selected item on
    /// every click — and it reads the child `NSHostingController.title` (empty),
    /// not the tab's `label`, so it blanks to "Untitled". We reassert this on
    /// each selection (see `SettingsTabViewController`) and on every `show()`.
    static let windowTitle = "Settings"

    private var window: NSWindow?
    private var tabController: SettingsTabViewController?

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.title = SettingsWindow.windowTitle   // reassert: some AppKit phase blanked it
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
            // Give the child VC a real title. In `.toolbar` style, AppKit drives
            // `window.title` from the selected item's *view-controller* title on
            // every selection; left empty it blanks the window to "Untitled".
            // (The tab `label` shows in the toolbar; the window title tracks the
            // VC title — so this is what actually keeps it titled.)
            hosting.title = SettingsWindow.windowTitle
            // Identical fixed size everywhere: switching panes never
            // resizes or shifts the window ("panes fit their content").
            hosting.preferredContentSize = SettingsTab.paneSize
            item.viewController = hosting

            controller.addTabViewItem(item)
        }

        let window = FixedTitleWindow(contentViewController: controller)
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
        // reverting to "Untitled" — so pin one honest title and reassert it on
        // every tab selection and window appearance, whatever AppKit does.
        window.title = SettingsWindow.windowTitle
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
        // `super` just rewrote the window title from the selected item's (empty)
        // view-controller title, blanking it to "Untitled". Restore our pinned
        // title synchronously — this runs on the initial selection and every
        // subsequent click, so the title can never stick as "Untitled".
        view.window?.title = SettingsWindow.windowTitle
        guard let id = tabViewItem?.identifier as? String else { return }
        onTabChange?(id)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Belt-and-suspenders: the first toolbar-driven title write can land
        // after selection during the window's initial layout pass.
        view.window?.title = SettingsWindow.windowTitle
    }
}

/// Window that refuses to be titled "Untitled": any attempt to set an empty
/// title (what AppKit's toolbar-tab machinery does when it loses the pane
/// name) is coerced back to our pinned title. This is timing-proof — it holds
/// whether the blank write happens during selection, layout, or a later pass.
private final class FixedTitleWindow: NSWindow {
    override var title: String {
        get { super.title }
        set { super.title = newValue.isEmpty ? SettingsWindow.windowTitle : newValue }
    }
}
