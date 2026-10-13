import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    func applicationWillTerminate(_: Notification) {
        GlobalHotKey.shared.unregister()
        EmojiShortcutMonitor.shared.stop()
    }
}
