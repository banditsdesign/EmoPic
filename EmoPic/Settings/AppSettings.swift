// AppSettings.swift
// Shared app settings persisted in UserDefaults.

import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Suite

    private let suite: UserDefaults

    private init(suiteName: String = AppSettings.suiteName) {
        self.suite = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        load()
    }

    // MARK: - Published Settings

    @Published var selectedSkinTone: SkinTone = .default {
        didSet { self.save() }
    }

    @Published var recentEmojiIDs: [String] = [] {
        didSet { self.save() }
    }

    @Published var enabledCategories: [EmojiCategory.RawValue] = EmojiCategory.allCases.map(\.rawValue) {
        didSet { self.save() }
    }

    @Published var excludedApps: [String] = AppSettings.defaultExcludedApps {
        didSet { self.save() }
    }

    @Published var enableColonShortcuts: Bool = true {
        didSet { self.save() }
    }

    @Published var showFrequentInPicker: Bool = true {
        didSet { self.save() }
    }

    // MARK: - Convenience

    var usesSkinTone: Bool { selectedSkinTone != .default }

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
        static let showFrequent = "showFrequentInPicker"
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
        suite.set(showFrequentInPicker, forKey: Keys.showFrequent)
    }

    private func load() {
        selectedSkinTone = SkinTone(rawValue: suite.string(forKey: Keys.skinTone) ?? "") ?? .default
        recentEmojiIDs = suite.array(forKey: Keys.recentIDs) as? [String] ?? Self.defaultRecentIDs
        enabledCategories = suite.array(forKey: Keys.enabledCategories) as? [EmojiCategory.RawValue] ?? EmojiCategory.allCases.map(\.rawValue)
        excludedApps = suite.array(forKey: Keys.excludedApps) as? [String] ?? Self.defaultExcludedApps
        enableColonShortcuts = suite.object(forKey: Keys.enableColonShortcuts) as? Bool ?? true
        showFrequentInPicker = suite.object(forKey: Keys.showFrequent) as? Bool ?? true
    }
}
