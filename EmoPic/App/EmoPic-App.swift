// EmoPic-App.swift - Main entry point
import SwiftUI

@main
struct EmoPicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
        } label: {
            MenuBarIconView()
        }
        // Native NSMenu (not a custom .window panel): standard item
        // padding, accent hover highlight, separators, shortcut display —
        // "Display a menu - not a popover - when people click it"
        // (apple-hig the-menu-bar.md).
        .menuBarExtraStyle(.menu)
    }
}
