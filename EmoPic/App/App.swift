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
    }

    func applicationWillTerminate(_: Notification) {
        GlobalHotKey.shared.unregister()
        EmojiShortcutMonitor.shared.stop()
    }
}
