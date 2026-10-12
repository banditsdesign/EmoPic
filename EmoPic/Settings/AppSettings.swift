// AppSettings.swift
// Shared app settings persisted in UserDefaults.

import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Suite

    private let suite: UserDefaults

    // Internal (not private) so the unit-test target can inject a volatile suite.
    init(suiteName: String = AppSettings.suiteName) {
        self.suite = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        load()
    }
    // MARK: - Published Settings

    // NOTE: assignments inside load() fire didSet; the isLoading guard stops
    // those from saving stale half-loaded state back to disk (which previously
    // erased recents/exclusions on every launch).
    private var isLoading = false

    @Published var selectedSkinTone: SkinTone = .default {
        didSet { if !isLoading { self.save() } }
    }

    @Published var recentEmojiIDs: [String] = [] {
        didSet { if !isLoading { self.save() } }
    }

    @Published var enabledCategories: [EmojiCategory.RawValue] = EmojiCategory.allCases.map(\.rawValue) {
        didSet { if !isLoading { self.save() } }
    }

    @Published var excludedApps: [String] = AppSettings.defaultExcludedApps {
        didSet { if !isLoading { self.save() } }
    }

    @Published var enableColonShortcuts: Bool = true {
        didSet { if !isLoading { self.save() } }
    }

    /// Show the Slack-style suggestion popup while typing :shortcod…
    @Published var showColonSuggestions: Bool = true {
        didSet { if !isLoading { self.save() } }
    }

    @Published var showFrequentInPicker: Bool = true {
        didSet { if !isLoading { self.save() } }
    }

    /// Global picker hotkey (Carbon keyCode + modifier flags). See HotKeyOption.
    @Published var hotKeyCode: Int = HotKeyOption.defaultOption.keyCode {
        didSet { if !isLoading { self.save() } }
    }

    @Published var hotKeyModifiers: Int = HotKeyOption.defaultOption.modifiers {
        didSet { if !isLoading { self.save() } }
    }

    @Published var hotKeyEnabled: Bool = true {
        didSet { if !isLoading { self.save() } }
    }

    /// Last-opened Settings pane rawValue; the window restores it and titles
    /// itself for its pane ("restore the last pane" — apple-hig settings.md).
    @Published var settingsTab: String = "Emoji Picker" {
        didSet { if !isLoading { self.save() } }
    }

    // MARK: - Convenience

    var usesSkinTone: Bool { selectedSkinTone != .default }

    var hotKeyOption: HotKeyOption {
        HotKeyOption.option(keyCode: hotKeyCode, modifiers: hotKeyModifiers)
    }

    // MARK: - Public API

    /// Record an emoji usage event. Pushes to front, keeps max 30.
    func recordUsage(_ emoji: EmojiItem) {
        let newIDs = [emoji.id] + recentEmojiIDs.filter { $0 != emoji.id }
        recentEmojiIDs = Array(newIDs.prefix(30))
    }

    /// Check if a bundle ID is in the exclusion list.
    func isAppExcluded(_ bundleIdentifier: String) -> Bool {
        excludedApps.contains(bundleIdentifier)
    }

    // MARK: - Defaults

    private static let suiteName = "group.net.emopic.app"

    private static let defaultRecentIDs: [String] = []
    private static let defaultExcludedApps: [String] = [
        "com.apple.dt.Xcode",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.microsoft.VSCode",
        "com.visualstudio.code.oss",
        "com.github.atom",
        "com.postmanlabs.mac",
    ]

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let skinTone = "selectedSkinTone"
        static let recentIDs = "recentEmojiIDs"
        static let enabledCategories = "enabledCategories"
        static let excludedApps = "excludedApps"
        static let enableColonShortcuts = "enableColonShortcuts"
        static let showColonSuggestions = "showColonSuggestions"
        static let showFrequent = "showFrequentInPicker"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let settingsTab = "settingsTab"
    }

    // MARK: - Persistence

    private func save() {
        if let tone = SkinTone(rawValue: selectedSkinTone.rawValue) {
            suite.set(tone.rawValue, forKey: Keys.skinTone)
        }
        suite.set(recentEmojiIDs, forKey: Keys.recentIDs)
        suite.set(enabledCategories, forKey: Keys.enabledCategories)
        suite.set(excludedApps, forKey: Keys.excludedApps)
        suite.set(enableColonShortcuts, forKey: Keys.enableColonShortcuts)
        suite.set(showColonSuggestions, forKey: Keys.showColonSuggestions)
        suite.set(showFrequentInPicker, forKey: Keys.showFrequent)
        suite.set(hotKeyCode, forKey: Keys.hotKeyCode)
        suite.set(hotKeyModifiers, forKey: Keys.hotKeyModifiers)
        suite.set(hotKeyEnabled, forKey: Keys.hotKeyEnabled)
        suite.set(settingsTab, forKey: Keys.settingsTab)
        // Flush synchronously so writes are visible to other UserDefaults
        // instances for the same suite (e.g. after relaunch, or in tests).
        suite.synchronize()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        selectedSkinTone = SkinTone(rawValue: suite.string(forKey: Keys.skinTone) ?? "") ?? .default
        recentEmojiIDs = suite.array(forKey: Keys.recentIDs) as? [String] ?? Self.defaultRecentIDs
        enabledCategories = suite.array(forKey: Keys.enabledCategories) as? [EmojiCategory.RawValue] ?? EmojiCategory.allCases.map(\.rawValue)
        excludedApps = suite.array(forKey: Keys.excludedApps) as? [String] ?? Self.defaultExcludedApps
        enableColonShortcuts = suite.object(forKey: Keys.enableColonShortcuts) as? Bool ?? true
        showColonSuggestions = suite.object(forKey: Keys.showColonSuggestions) as? Bool ?? true
        showFrequentInPicker = suite.object(forKey: Keys.showFrequent) as? Bool ?? true
        hotKeyCode = suite.object(forKey: Keys.hotKeyCode) as? Int ?? HotKeyOption.defaultOption.keyCode
        hotKeyModifiers = suite.object(forKey: Keys.hotKeyModifiers) as? Int ?? HotKeyOption.defaultOption.modifiers
        hotKeyEnabled = suite.object(forKey: Keys.hotKeyEnabled) as? Bool ?? true
        settingsTab = suite.string(forKey: Keys.settingsTab) ?? "Emoji Picker"
    }
}
