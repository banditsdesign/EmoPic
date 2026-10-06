// EmoPic-App.swift - Main entry point
import SwiftUI

@main
struct EmoPicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(settings)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)
    }
}
