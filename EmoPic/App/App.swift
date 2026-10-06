import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EmojiDataManager.shared.loadEmojiData()
        FrequentEmojiStore.shared.update()
        EmojiShortcutMonitor.shared.start()
        GlobalHotKey.shared.register()
    }

    func applicationWillTerminate(_: Notification) {
        GlobalHotKey.shared.unregister()
        EmojiShortcutMonitor.shared.stop()
    }
}
