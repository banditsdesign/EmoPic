import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EmojiDataManager.shared.loadEmojiData()
        FrequentEmojiStore.shared.update()
        EmojiShortcutMonitor.shared.start()
    }

    func applicationWillTerminate(_: Notification) {
        EmojiShortcutMonitor.shared.stop()
    }
}
