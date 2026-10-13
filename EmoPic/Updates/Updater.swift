// Updater.swift
// Sparkle-backed software updates (issue #2): opt-in checks, user-confirmed
// download, user-confirmed relaunch.
//
// Privacy contract — mirrored in PRIVACY.md, and deliberately a contract:
//   * Nothing here touches the network unless the user turned on "Automatically
//     check for updates" (default off: `SUEnableAutomaticChecks` = false in
//     Info.plist) or pressed Check for Updates… themselves.
//   * `sendsSystemProfile` is forced off, so a check carries no macOS version,
//     hardware model or usage statistics — just the appcast request itself.
//   * The user agent names the app and its version, nothing else.
//
// Install policy — "prompt for everything": `automaticallyDownloadsUpdates`
// stays false, so Sparkle asks before downloading and again before relaunching.
// EmoPic sits between the user and their keyboard all day; restarting it should
// never surprise them mid-sentence.
//
// Two Sparkle details that matter for this app in particular:
//   * The app is an `LSUIElement` agent, so update UI would otherwise appear
//     behind the frontmost app. We activate before checking and when an update
//     turns up.
//   * The delegates are held *weakly* by Sparkle, hence `shared` retains both
//     the controller and itself as the delegate.

import AppKit
import Sparkle

final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// Where the update flow currently is; drives the Settings status line and
    /// the menu-bar item title.
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading(String)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private let settings = AppSettings.shared
    private var controller: SPUStandardUpdaterController?

    /// Weekly rather than Sparkle's daily default: this is a 3 MB menu-bar app,
    /// not a browser. Sparkle still adds jitter and exponential back-off.
    private static let checkInterval: TimeInterval = 7 * 24 * 60 * 60

    /// `SUNoUpdateError` from Sparkle's `SUError` enum. Spelled as a raw value
    /// rather than as `SUError.noUpdate...`: the enum is OSStatus-backed and its
    /// Swift name translation has shifted between Sparkle releases, and a typo
    /// there would silently mislabel "you're up to date" as a failure.
    private static let noUpdateErrorCode = 1001

    private static func isNoUpdateError(_ error: (any Error)?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == SUSparkleErrorDomain && error.code == noUpdateErrorCode
    }

    // MARK: - Lifecycle

    /// Builds the updater and starts it. Call once, from
    /// `applicationDidFinishLaunching`. Safe to call again (ignored).
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(updaterDelegate: self, userDriverDelegate: nil)
        // The Info.plist key already defaults this to off; set it from our own
        // store so a user's earlier choice survives, and so the switch in
        // Settings → About reflects what Sparkle will actually do.
        controller.updater.automaticallyChecksForUpdates = settings.automaticallyCheckForUpdates
        controller.updater.automaticallyDownloadsUpdates = false
        controller.updater.sendsSystemProfile = false
        controller.updater.userAgentString = "EmoPic/\(VersionInfo.version)"
        controller.updater.updateCheckInterval = Self.checkInterval
        self.controller = controller
    }

    // MARK: - Actions

    /// True while a check/install session can be started (Sparkle blocks
    /// re-entrant checks while one is running).
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    /// The version awaiting install, if an update has already been found.
    var pendingVersion: String? {
        if case .available(let version) = phase { return version }
        return nil
    }

    /// Menu-bar title: switches to an affirmative once something is found.
    var menuItemTitle: String {
        guard let version = pendingVersion else { return "Check for Updates…" }
        return "Update to EmoPic \(version)…"
    }

    /// One-line status for Settings → About. Empty when there is nothing to say.
    var statusText: String {
        switch phase {
        case .idle: return ""
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date — EmoPic \(VersionInfo.version) is the latest release."
        case .available(let version): return "EmoPic \(version) is available."
        case .downloading(let version): return "Downloading EmoPic \(version)…"
        case .installing(let version): return "Installing EmoPic \(version)…"
        case .failed(let message): return message
        }
    }

    /// Show Sparkle's update UI. Only ever user-initiated.
    func checkNow() {
        guard let controller else { return }
        phase = .checking
        // Accessory app: bring ourselves forward or the alert lands behind
        // whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Applies the opt-in switch to Sparkle and persists it.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        settings.automaticallyCheckForUpdates = enabled
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

// MARK: - SPUUpdaterDelegate

extension Updater: SPUUpdaterDelegate {
    // Method names below are Swift's own translation of Sparkle's Objective-C
    // selectors (the selector is quoted above each one); deviating from them —
    // e.g. `withRequest:` instead of `with:`, or `NSError` instead of
    // `any Error` — produces a method that merely "nearly matches" the optional
    // requirement and is never called.

    /// We own the consent question in Settings → About, so suppress Sparkle's
    /// own first-run prompt (and honour the Info.plist default of off).
    /// `updaterShouldPromptForPermissionToCheckForUpdates:`
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    /// `updaterDidNotFindUpdate:error:`
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // "No update found" arrives here as well as via the parameterless
        // variant; anything else is a real failure and should be shown.
        if Self.isNoUpdateError(error) {
            phase = .upToDate
        } else {
            phase = .failed((error as NSError).localizedDescription)
        }
        settings.lastUpdateCheck = updater.lastUpdateCheckDate
    }

    /// `updater:didFindValidUpdate:`
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        phase = .available(item.displayVersionString)
        settings.lastUpdateCheck = updater.lastUpdateCheckDate
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `updater:willDownloadUpdate:withRequest:`
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        phase = .downloading(item.displayVersionString)
    }

    /// `updater:failedToDownloadUpdate:error:`
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        phase = .failed("Couldn't download EmoPic \(item.displayVersionString): \((error as NSError).localizedDescription)")
    }

    /// `updater:willInstallUpdate:`
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        phase = .installing(item.displayVersionString)
    }

    /// `updater:didFinishUpdateCycleForUpdateCheck:error:`
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        settings.lastUpdateCheck = updater.lastUpdateCheckDate
        // Leave .available/.installing alone: Sparkle's own UI owns those
        // moments, and clearing the state here would blank the menu title the
        // user still needs to act on.
        switch phase {
        case .checking, .upToDate, .downloading, .failed:
            if let error, !Self.isNoUpdateError(error) {
                phase = .failed((error as NSError).localizedDescription)
            } else if phase == .checking {
                phase = .upToDate
            }
        default:
            break
        }
    }

    /// `updater:didAbortWithError:`
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        phase = .failed((error as NSError).localizedDescription)
    }
}
