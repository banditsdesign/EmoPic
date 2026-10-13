// AppSettings.swift
// Shared app settings persisted in the standard UserDefaults domain.
// (v1.0 stored them under an App-Group suite name the app never had the
// entitlement for — migrated once on launch, see `migrateLegacyValues`.)

import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Suite

    private let suite: UserDefaults

    /// v1.0's suite name, kept only as a migration source.
    private static let legacySuiteName = "group.net.emopic.app"
    private static let migrationDoneKey = "migratedFromLegacyGroupSuite"

    // Internal (not private) so the unit-test target can inject a volatile
    // suite. Injected suites skip migration — they are test fixtures, not
    // the real store.
    init(suiteName: String? = nil) {
        if let suiteName {
            suite = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            suite = .standard
            Self.migrateLegacyValues(into: suite, legacySuiteName: Self.legacySuiteName)
        }
        load()
    }

    /// One-time copy of the settings v1.0 wrote into the (entitlement-less)
    /// group suite. Only known app keys move, only into keys the standard
    /// domain doesn't already have, and the legacy domain is left untouched —
    /// idempotent and non-destructive. Internal for unit-test coverage.
    static func migrateLegacyValues(into standard: UserDefaults, legacySuiteName: String) {
        guard standard.bool(forKey: migrationDoneKey) == false else { return }
        standard.set(true, forKey: migrationDoneKey)
        guard let legacy = UserDefaults(suiteName: legacySuiteName),
              let legacyValues = legacy.persistentDomain(forName: legacySuiteName),
              !legacyValues.isEmpty else { return }
        for key in legacyKeyNames {
            if let value = legacyValues[key], standard.object(forKey: key) == nil {
                standard.set(value, forKey: key)
            }
        }
    }

    /// Every key v1.0 could have written to the legacy suite, in one list so
    /// migration and the `Keys` namespace can't drift apart.
    static let legacyKeyNames: [String] = [
        Keys.skinTone, Keys.recentIDs, Keys.enabledCategories, Keys.excludedApps,
        Keys.enableColonShortcuts, Keys.showColonSuggestions, Keys.showFrequent,
        Keys.hotKeyCode, Keys.hotKeyModifiers, Keys.hotKeyEnabled,
        Keys.settingsTab, Keys.launchAtLogin,
    ]
    // MARK: - Published Settings

    // NOTE: assignments inside load() fire didSet; the isLoading guard stops
    // those from saving stale half-loaded state back to disk (which previously
    // erased recents/exclusions on every launch).
    private var isLoading = false

    @Published var selectedSkinTone: SkinTone = .default {
        didSet { if !isLoading { save(Keys.skinTone) } }
    }

    @Published var recentEmojiIDs: [String] = [] {
        didSet { if !isLoading { save(Keys.recentIDs) } }
    }

    @Published var enabledCategories: [EmojiCategory.RawValue] = EmojiCategory.allCases.map(\.rawValue) {
        didSet { if !isLoading { save(Keys.enabledCategories) } }
    }

    @Published var excludedApps: [String] = AppSettings.defaultExcludedApps {
        didSet { if !isLoading { save(Keys.excludedApps) } }
    }

    @Published var enableColonShortcuts: Bool = true {
        didSet { if !isLoading { save(Keys.enableColonShortcuts) } }
    }

    /// Show the Slack-style suggestion popup while typing :shortcod…
    @Published var showColonSuggestions: Bool = true {
        didSet { if !isLoading { save(Keys.showColonSuggestions) } }
    }

    @Published var showFrequentInPicker: Bool = true {
        didSet { if !isLoading { save(Keys.showFrequent) } }
    }

    /// Global picker hotkey (Carbon keyCode + modifier flags). See HotKeyOption.
    @Published var hotKeyCode: Int = HotKeyOption.defaultOption.keyCode {
        didSet { if !isLoading { save(Keys.hotKeyCode) } }
    }

    @Published var hotKeyModifiers: Int = HotKeyOption.defaultOption.modifiers {
        didSet { if !isLoading { save(Keys.hotKeyModifiers) } }
    }

    @Published var hotKeyEnabled: Bool = true {
        didSet { if !isLoading { save(Keys.hotKeyEnabled) } }
    }

    /// Whether EmoPic registers itself as a login item (macOS 13+
    /// `SMAppService.mainApp`). The Settings toggle drives it; the
    /// persisted value mirrors the real service status.
    @Published var launchAtLogin: Bool = false {
        didSet { if !isLoading { save(Keys.launchAtLogin) } }
    }

    /// Last-opened Settings pane rawValue; the window restores it and titles
    /// itself for its pane ("restore the last pane" — apple-hig settings.md).
    @Published var settingsTab: String = "Emoji Picker" {
        didSet { if !isLoading { save(Keys.settingsTab) } }
    }

    /// User-assigned custom emoji descriptions (issue #1): emoji id → free
    /// text. `[String: String]` is plist-safe, so UserDefaults stores it
    /// directly like the other lists. Deliberately absent from
    /// `legacyKeyNames` — v1.0 never wrote this key.
    @Published var customEmojiDescriptions: [String: String] = [:] {
        didSet { if !isLoading { save(Keys.customDescriptions) } }
    }

    /// Issue #2: may EmoPic contact GitHub for update checks without being
    /// asked each time? Deliberately off by default — the app makes no network
    /// connection until the user says otherwise (see PRIVACY.md).
    ///
    /// Sparkle keeps its own mirror of this in `SUEnableAutomaticChecks` in the
    /// same domain; `Updater` applies this value to the live updater. Stored on
    /// our side so the preference is observable without instantiating Sparkle
    /// (the unit tests run without an updater), and so the Settings switch can
    /// never claim a state the updater didn't accept — same reasoning as
    /// `launchAtLogin` mirroring the real `SMAppService` registration.
    @Published var automaticallyCheckForUpdates: Bool = false {
        didSet { if !isLoading { save(Keys.automaticallyCheckForUpdates) } }
    }

    /// When the last update check actually happened; display only, so it is
    /// re-written on every check rather than migrated or synced.
    @Published var lastUpdateCheck: Date? {
        didSet { if !isLoading { save(Keys.lastUpdateCheck) } }
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
        static let launchAtLogin = "launchAtLogin"
        static let customDescriptions = "customEmojiDescriptions"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
    }

    // MARK: - Persistence

    /// Persist exactly the key that changed — the previous save() rewrote
    /// all twelve keys (plus a deprecated synchronize()) on every didSet.
    /// No synchronize(): cfprefsd keeps same-process suite instances
    /// coherent, and the suite round-trip tests guard exactly that.
    private func save(_ key: String) {
        switch key {
        case Keys.skinTone: suite.set(selectedSkinTone.rawValue, forKey: key)
        case Keys.recentIDs: suite.set(recentEmojiIDs, forKey: key)
        case Keys.enabledCategories: suite.set(enabledCategories, forKey: key)
        case Keys.excludedApps: suite.set(excludedApps, forKey: key)
        case Keys.enableColonShortcuts: suite.set(enableColonShortcuts, forKey: key)
        case Keys.showColonSuggestions: suite.set(showColonSuggestions, forKey: key)
        case Keys.showFrequent: suite.set(showFrequentInPicker, forKey: key)
        case Keys.hotKeyCode: suite.set(hotKeyCode, forKey: key)
        case Keys.hotKeyModifiers: suite.set(hotKeyModifiers, forKey: key)
        case Keys.hotKeyEnabled: suite.set(hotKeyEnabled, forKey: key)
        case Keys.settingsTab: suite.set(settingsTab, forKey: key)
        case Keys.launchAtLogin: suite.set(launchAtLogin, forKey: key)
        case Keys.customDescriptions: suite.set(customEmojiDescriptions, forKey: key)
        case Keys.automaticallyCheckForUpdates: suite.set(automaticallyCheckForUpdates, forKey: key)
        case Keys.lastUpdateCheck: suite.set(lastUpdateCheck, forKey: key)
        default: break
        }
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
        launchAtLogin = suite.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        customEmojiDescriptions = suite.dictionary(forKey: Keys.customDescriptions) as? [String: String] ?? [:]
        automaticallyCheckForUpdates = suite.object(forKey: Keys.automaticallyCheckForUpdates) as? Bool ?? false
        lastUpdateCheck = suite.object(forKey: Keys.lastUpdateCheck) as? Date
    }
}
