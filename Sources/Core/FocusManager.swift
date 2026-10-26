import AppKit
import UserNotifications

struct BlockedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// What a pomodoro does to the Mac for a kind of work: which macOS Focus to turn on
/// (through a Shortcut, since apps can't toggle Focus directly) and which apps to keep closed.
struct FocusProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = String(localized: "New Profile")
    var emoji = "🎯"
    /// Shortcut run when a pomodoro starts, e.g. one with a "Set Focus → Study → On" action.
    var focusOnShortcut = ""
    var blockedApps: [BlockedApp] = []
    /// Hide blocked apps instead of quitting them.
    var hideInsteadOfQuit = false

    static var defaults: [FocusProfile] {
        [
            FocusProfile(name: String(localized: "Study"), emoji: "📚", blockedApps: [
                BlockedApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
                BlockedApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
                BlockedApp(bundleID: "com.hnc.Discord", name: "Discord"),
            ]),
            FocusProfile(name: String(localized: "Work"), emoji: "💼"),
        ]
    }
}

/// Applies the selected focus profile while a pomodoro runs and undoes it during breaks.
@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published private(set) var availableShortcuts: [String] = []
    @Published private(set) var activeProfile: FocusProfile?
    /// Apps we quit, to reopen them on the break.
    private var quitApps: [URL] = []
    private var launchObserver: Any?

    private let settings = AppSettings.shared

    var currentProfile: FocusProfile? {
        settings.focusProfiles.first { $0.id == SessionManager.shared.profileID }
    }

    func handle(_ event: TimerEvent) {
        let session = SessionManager.shared
        switch event {
        case .pomodoroStarted, .resumed where session.phase == .pomodoro:
            activate()
        case .breakStarted, .stopped, .waiting:
            deactivate()
        default:
            break
        }
    }

    /// Re-apply when the user switches profile in the middle of a pomodoro.
    func profileChanged() {
        let session = SessionManager.shared
        guard session.phase == .pomodoro, session.isActive else { return }
        deactivate()
        activate()
    }

    private func activate() {
        guard let profile = currentProfile, activeProfile?.id != profile.id else { return }
        activeProfile = profile
        if !profile.focusOnShortcut.isEmpty { runShortcut(profile.focusOnShortcut) }
        for app in profile.blockedApps {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
                close(running, profile: profile)
            }
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { FocusManager.shared.appLaunched(app) }
        }
    }

    private func deactivate() {
        guard activeProfile != nil else { return }
        activeProfile = nil
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        if !settings.focusOffShortcut.isEmpty { runShortcut(settings.focusOffShortcut) }
        if settings.reopenBlockedApps {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            for url in quitApps { NSWorkspace.shared.openApplication(at: url, configuration: config) }
        }
        quitApps.removeAll()
    }

    private func appLaunched(_ app: NSRunningApplication?) {
        guard let app, let profile = activeProfile,
              let blocked = profile.blockedApps.first(where: { $0.bundleID == app.bundleIdentifier }) else { return }
        // Give the app a moment to finish launching before closing it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { FocusManager.shared.close(app, profile: profile) }
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(blocked.name) is blocked")
        content.body = String(localized: "\(profile.name) focus is on. It'll be back on your break.")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "blocked", content: content, trigger: nil))
    }

    private func close(_ app: NSRunningApplication, profile: FocusProfile) {
        if profile.hideInsteadOfQuit {
            app.hide()
        } else {
            if let url = app.bundleURL, !quitApps.contains(url) { quitApps.append(url) }
            app.terminate()
        }
    }

    // MARK: - Shortcuts

    func runShortcut(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }

    func reloadShortcuts() {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let names = String(decoding: data, as: UTF8.self)
                .split(separator: "\n").map(String.init).sorted()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { FocusManager.shared.availableShortcuts = names }
            }
        }
    }
}
