// SingleInstanceGuard.swift
// Two EmoPics is always worse than one: each copy installs its own system-wide
// event tap (so `:smile:` gets swapped twice), fights for the same ⌥⌘E global
// hotkey, doubles up colon-suggestion popups, and shows a second menu bar icon
// that looks identical to the first. This guard makes the second copy stand
// down before any of that starts.

import Cocoa
import os

/// Outcome of trying to claim the single-instance lock.
enum InstanceClaim: Equatable {
    /// We own the lock — carry on launching.
    case unique
    /// Another live copy owns it.
    case alreadyRunning
    /// The lock file could not be created or locked for a reason that has
    /// nothing to do with another copy (read-only home, a volume without
    /// locking). Fail open: refusing to start would be worse than a possible
    /// duplicate. Carries `errno`.
    case lockUnavailable(Int32)
}

final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    private static let log = Logger(subsystem: "net.emopic.app", category: "SingleInstance")

    /// Escape hatch for development: `EMOPIC_ALLOW_MULTIPLE=1 open -n EmoPic.app`
    /// runs a second copy next to an installed one (Xcode sessions, release
    /// testing). Ignored in normal use.
    static let allowMultipleEnvKey = "EMOPIC_ALLOW_MULTIPLE"

    /// Posted by a copy that had to stand down, so the copy that owns the menu
    /// bar surfaces its picker instead of appearing to ignore the click.
    static let openPickerNotification = NSNotification.Name("net.emopic.app.openPicker")

    private let lockFileURL: URL
    /// Held open for the life of the process; the kernel drops `flock` on exit.
    private var fd: Int32 = -1

    init(lockFileURL: URL = SingleInstanceGuard.defaultLockFileURL()) {
        self.lockFileURL = lockFileURL
    }

    deinit { release() }

    // MARK: - Lock

    /// Keyed to the *user*, not to the app's location on disk — the duplicate
    /// usually comes from a second copy of the app (Applications + a DMG or a
    /// build folder), which `LSMultipleInstancesProhibited` cannot see.
    static func defaultLockFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("EmoPic", isDirectory: true)
            .appendingPathComponent("single-instance.lock")
    }

    static func allowsMultipleInstances(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let raw = environment[allowMultipleEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(raw)
    }

    /// Try to become the one running EmoPic. Idempotent within a process.
    ///
    /// Retries briefly, because relaunch races are ordinary: Sparkle starts the
    /// updated copy while the old process is still on its way out, and a login
    /// item can beat a double-click. `flock` is released by the kernel the
    /// instant a holder dies, so a crash or a force-quit can never wedge the
    /// lock shut — waiting is always safe.
    @discardableResult
    func claim(retries: Int = 6, retryInterval: TimeInterval = 0.25) -> InstanceClaim {
        var result = attempt()
        for _ in 0..<max(0, retries) {
            guard case .alreadyRunning = result else { break }
            Thread.sleep(forTimeInterval: retryInterval)
            result = attempt()
        }
        return result
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    private func attempt() -> InstanceClaim {
        if fd >= 0 { return .unique }

        do {
            try FileManager.default.createDirectory(
                at: lockFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return .lockUnavailable(errno)
        }

        let handle = open(lockFileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard handle >= 0 else { return .lockUnavailable(errno) }

        guard flock(handle, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(handle)
            // EWOULDBLOCK is the only "someone else has it" answer; anything
            // else (ENOLCK/EINVAL on odd filesystems) must not block launch.
            return code == EWOULDBLOCK ? .alreadyRunning : .lockUnavailable(code)
        }

        fd = handle
        writePID()
        return .unique
    }

    /// Best-effort breadcrumb for anyone debugging a stuck menu bar icon:
    /// `cat ~/Library/Application\ Support/EmoPic/single-instance.lock`.
    private func writePID() {
        guard fd >= 0 else { return }
        ftruncate(fd, 0)
        let data = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, data.count) }
    }

    // MARK: - Launch decision

    /// XCTest runs *inside* the app bundle, so the test host is a second copy
    /// next to the EmoPic already sitting in the developer's menu bar.
    /// Refusing it would mean refusing to run the tests.
    static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    /// Call before anything else starts up. `false` means this copy must not
    /// continue: it has handed off to the running one and is on its way out.
    @discardableResult
    func enforce(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if SingleInstanceGuard.isRunningTests { return true }
        if SingleInstanceGuard.allowsMultipleInstances(environment) {
            Self.log.info("\(Self.allowMultipleEnvKey) set — allowing a second copy")
            return true
        }

        switch claim() {
        case .unique:
            return true
        case .lockUnavailable(let code):
            Self.log.warning("Single-instance lock unavailable (errno \(code)) — continuing")
            return true
        case .alreadyRunning:
            Self.log.notice("EmoPic is already running — this copy is standing down")
            standDown()
            return false
        }
    }

    /// Tell the user why nothing happened, then quit this copy.
    private func standDown() {
        let running = runningCopies()
        running.first?.activate()

        // Silence is a bad answer: the app was just double-clicked and, with no
        // dock icon and no window, it would look like EmoPic simply refused to
        // open. Two buttons because "then show me the picker" is what people
        // wanted in the first place.
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "EmoPic is already running"
        alert.informativeText = """
            Look for the double-chevron icon in your menu bar — ⌥⌘E opens the \
            picker from any app. This copy will now quit: two running at once \
            would double up colon shortcuts and fight over the hotkey.
            """
        alert.addButton(withTitle: "Quit This Copy")
        alert.addButton(withTitle: "Open Emoji Picker")

        NSApp.activate(ignoringOtherApps: true)
        // An accessory (LSUIElement) app is not necessarily allowed to become
        // active, and `runModal` alone then leaves the alert under the app the
        // user was actually using. Order it up ourselves, at panel level.
        alert.layout()
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()

        // A copy started by a login item can raise this with nobody watching;
        // an unattended modal must not keep a useless process alive.
        let watchdog = DispatchWorkItem { exit(0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: watchdog)
        let answer = alert.runModal()
        watchdog.cancel()

        if answer == .alertSecondButtonReturn, let runningApp = running.first {
            runningApp.activate()
            DistributedNotificationCenter.default().postNotificationName(
                Self.openPickerNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }

        NSApp.terminate(nil)
        // Termination is immediate in practice; if SwiftUI is mid-launch and it
        // ever stalls, this copy still must not linger.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
    }

    /// Live copies of this bundle identifier, excluding this process.
    private func runningCopies() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
    }
}
