import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EmojiDataManager.shared.loadEmojiData()
        FrequentEmojiStore.shared.update()
    }
}
