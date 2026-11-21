import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// False in a copy that stood down as a duplicate — it must not bring up a
    /// single subsystem on its way out.
    private var isPrimaryInstance = true

    /// Token for the handoff message from a duplicate copy (see
    /// `SingleInstanceGuard`). Kept for the life of the process.
    private var openPickerObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything else: the keyboard event tap, the global hotkey and
        // the menu bar item all belong to exactly one process, so a duplicate
        // has to be turned away here rather than in `didFinishLaunching`.
        isPrimaryInstance = SingleInstanceGuard.shared.enforce()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isPrimaryInstance else { return }

        EmojiDataManager.shared.loadEmojiData()
        FrequentEmojiStore.shared.update()
        // Show the one-time Accessibility prompt if untrusted; the monitor
        // activates its event tap as soon as permission flips (no relaunch).
        EmojiShortcutMonitor.shared.requestPermissionIfNeeded()
        EmojiShortcutMonitor.shared.start()
        GlobalHotKey.shared.register()
        // Issue #2: Sparkle. Starts idle — it will not reach the network until
        // the user opts in via Settings → About (SUEnableAutomaticChecks is
        // false in Info.plist and defaults to off in AppSettings).
        Updater.shared.start()

        // The copy that got refused after this one owns the menu bar; say
        // "Open Emoji Picker" on its alert and it posts this, so the click the
        // user already made does what they meant instead of nothing at all.
        openPickerObserver = DistributedNotificationCenter.default().addObserver(
            forName: SingleInstanceGuard.openPickerNotification,
            object: nil,
            queue: .main
        ) { _ in
            EmojiPickerWindow.shared.presentIfHidden()
        }
    }

    /// Double-clicking EmoPic in Finder while it is already running activates
    /// the running copy instead of launching a second one — make that gesture
    /// do the thing people were reaching for.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard isPrimaryInstance else { return true }
        EmojiPickerWindow.shared.presentIfHidden()
        return true
    }

    func applicationWillTerminate(_: Notification) {
        guard isPrimaryInstance else { return }
        GlobalHotKey.shared.unregister()
        EmojiShortcutMonitor.shared.stop()
    }
}
