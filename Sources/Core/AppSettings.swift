import Foundation
import SwiftUI

enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// All user preferences, persisted in UserDefaults.
/// Mirrors the gsettings schema of the original app plus a few macOS-specific additions.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // Timer
    @Published var pomodoroDuration: Int { didSet { d.set(pomodoroDuration, forKey: "pomodoroDuration") } }
    @Published var shortBreakDuration: Int { didSet { d.set(shortBreakDuration, forKey: "shortBreakDuration") } }
    @Published var longBreakDuration: Int { didSet { d.set(longBreakDuration, forKey: "longBreakDuration") } }
    @Published var cycles: Int { didSet { d.set(cycles, forKey: "cycles") } }
    @Published var confirmStartingBreak: Bool { didSet { d.set(confirmStartingBreak, forKey: "confirmStartingBreak") } }
    @Published var confirmStartingPomodoro: Bool { didSet { d.set(confirmStartingPomodoro, forKey: "confirmStartingPomodoro") } }
    /// After a break, start the pomodoro on the first mouse/keyboard activity instead of right away.
    @Published var startPomodoroOnActivity: Bool { didSet { d.set(startPomodoroOnActivity, forKey: "startPomodoroOnActivity") } }
    @Published var pauseOnLockScreen: Bool { didSet { d.set(pauseOnLockScreen, forKey: "pauseOnLockScreen") } }
    @Published var expiryTimeout: Int { didSet { d.set(expiryTimeout, forKey: "expiryTimeout") } }
    @Published var dailyGoal: Int { didSet { d.set(dailyGoal, forKey: "dailyGoal") } }

    // Notifications
    @Published var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var announceAboutToEnd: Bool { didSet { d.set(announceAboutToEnd, forKey: "announceAboutToEnd") } }
    @Published var announcementLeadTime: Int { didSet { d.set(announcementLeadTime, forKey: "announcementLeadTime") } }
    @Published var screenOverlay: Bool { didSet { d.set(screenOverlay, forKey: "screenOverlay") } }
    @Published var screenOverlayLockDelay: Int { didSet { d.set(screenOverlayLockDelay, forKey: "screenOverlayLockDelay") } }
    @Published var screenOverlayReopenDelay: Int { didSet { d.set(screenOverlayReopenDelay, forKey: "screenOverlayReopenDelay") } }
    @Published var dismissGesture: Bool { didSet { d.set(dismissGesture, forKey: "dismissGesture") } }

    // Appearance
    @Published var colorScheme: ColorSchemePreference { didSet { d.set(colorScheme.rawValue, forKey: "colorScheme") } }
    @Published var preferCompactSize: Bool { didSet { d.set(preferCompactSize, forKey: "preferCompactSize") } }
    @Published var blurEffect: Bool { didSet { d.set(blurEffect, forKey: "blurEffect") } }
    @Published var showTimeInMenuBar: Bool { didSet { d.set(showTimeInMenuBar, forKey: "showTimeInMenuBar") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon"); AppController.shared.applyDockPolicy() } }

    /// "system", "ar" or "en". Takes effect after a relaunch.
    @Published var language: String { didSet { d.set(language, forKey: "language"); applyLanguage() } }

    // Sounds
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var pomodoroFinishedSound: String { didSet { d.set(pomodoroFinishedSound, forKey: "pomodoroFinishedSound") } }
    @Published var pomodoroFinishedVolume: Double { didSet { d.set(pomodoroFinishedVolume, forKey: "pomodoroFinishedVolume") } }
    @Published var breakFinishedSound: String { didSet { d.set(breakFinishedSound, forKey: "breakFinishedSound") } }
    @Published var breakFinishedVolume: Double { didSet { d.set(breakFinishedVolume, forKey: "breakFinishedVolume") } }
    @Published var backgroundSound: String { didSet { d.set(backgroundSound, forKey: "backgroundSound"); SoundManager.shared.refreshBackground() } }
    @Published var backgroundVolume: Double { didSet { d.set(backgroundVolume, forKey: "backgroundVolume"); SoundManager.shared.refreshBackground() } }

    // Shortcuts & automation
    @Published var hotKeys: [HotKeyAction: KeyCombo] { didSet { save(hotKeys, "hotKeys"); HotKeyManager.shared.reload() } }
    @Published var automations: [AutomationAction] { didSet { save(automations, "automations") } }

    // Focus profiles
    @Published var focusProfiles: [FocusProfile] { didSet { save(focusProfiles, "focusProfiles") } }
    /// Shortcut run when a break starts or the timer stops, e.g. "Set Focus → Turn Off".
    @Published var focusOffShortcut: String { didSet { d.set(focusOffShortcut, forKey: "focusOffShortcut") } }
    @Published var reopenBlockedApps: Bool { didSet { d.set(reopenBlockedApps, forKey: "reopenBlockedApps") } }

    private init() {
        d.register(defaults: [
            "pomodoroDuration": 1500, "shortBreakDuration": 300, "longBreakDuration": 900,
            "cycles": 4, "confirmStartingBreak": false, "confirmStartingPomodoro": false, "startPomodoroOnActivity": false,
            "pauseOnLockScreen": true, "expiryTimeout": 3600, "dailyGoal": 8,
            "notificationsEnabled": true, "announceAboutToEnd": true, "announcementLeadTime": 15,
            "screenOverlay": true, "screenOverlayLockDelay": 0, "screenOverlayReopenDelay": 30,
            "dismissGesture": false, "colorScheme": "system", "language": "system", "preferCompactSize": false,
            "blurEffect": true, "showTimeInMenuBar": true, "showDockIcon": true,
            "soundsEnabled": true, "pomodoroFinishedSound": "bell", "pomodoroFinishedVolume": 1.0,
            "breakFinishedSound": "loud-bell", "breakFinishedVolume": 1.0,
            "backgroundSound": "", "backgroundVolume": 0.5,
            "focusOffShortcut": "", "reopenBlockedApps": true,
        ])
        pomodoroDuration = d.integer(forKey: "pomodoroDuration")
        shortBreakDuration = d.integer(forKey: "shortBreakDuration")
        longBreakDuration = d.integer(forKey: "longBreakDuration")
        cycles = d.integer(forKey: "cycles")
        confirmStartingBreak = d.bool(forKey: "confirmStartingBreak")
        confirmStartingPomodoro = d.bool(forKey: "confirmStartingPomodoro")
        startPomodoroOnActivity = d.bool(forKey: "startPomodoroOnActivity")
        pauseOnLockScreen = d.bool(forKey: "pauseOnLockScreen")
        expiryTimeout = d.integer(forKey: "expiryTimeout")
        dailyGoal = d.integer(forKey: "dailyGoal")
        notificationsEnabled = d.bool(forKey: "notificationsEnabled")
        announceAboutToEnd = d.bool(forKey: "announceAboutToEnd")
        announcementLeadTime = d.integer(forKey: "announcementLeadTime")
        screenOverlay = d.bool(forKey: "screenOverlay")
        screenOverlayLockDelay = d.integer(forKey: "screenOverlayLockDelay")
        screenOverlayReopenDelay = d.integer(forKey: "screenOverlayReopenDelay")
        dismissGesture = d.bool(forKey: "dismissGesture")
        colorScheme = ColorSchemePreference(rawValue: d.string(forKey: "colorScheme") ?? "") ?? .system
        language = d.string(forKey: "language") ?? "system"
        preferCompactSize = d.bool(forKey: "preferCompactSize")
        blurEffect = d.bool(forKey: "blurEffect")
        showTimeInMenuBar = d.bool(forKey: "showTimeInMenuBar")
        showDockIcon = d.bool(forKey: "showDockIcon")
        soundsEnabled = d.bool(forKey: "soundsEnabled")
        pomodoroFinishedSound = d.string(forKey: "pomodoroFinishedSound") ?? ""
        pomodoroFinishedVolume = d.double(forKey: "pomodoroFinishedVolume")
        breakFinishedSound = d.string(forKey: "breakFinishedSound") ?? ""
        breakFinishedVolume = d.double(forKey: "breakFinishedVolume")
        backgroundSound = d.string(forKey: "backgroundSound") ?? ""
        backgroundVolume = d.double(forKey: "backgroundVolume")
        hotKeys = Self.load("hotKeys") ?? HotKeyAction.defaults
        automations = Self.load("automations") ?? []
        focusProfiles = Self.load("focusProfiles") ?? FocusProfile.defaults
        focusOffShortcut = d.string(forKey: "focusOffShortcut") ?? ""
        reopenBlockedApps = d.bool(forKey: "reopenBlockedApps")
    }

    func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .pomodoro: TimeInterval(pomodoroDuration)
        case .shortBreak: TimeInterval(shortBreakDuration)
        case .longBreak: TimeInterval(longBreakDuration)
        }
    }

    /// Overrides the app's language; Arabic keeps Latin digits so the clock matches the rest of the UI.
    private func applyLanguage() {
        switch language {
        case "ar":
            d.set(["ar"], forKey: "AppleLanguages")
            d.set("ar_EG@numbers=latn", forKey: "AppleLocale")
        case "en":
            d.set(["en"], forKey: "AppleLanguages")
            d.removeObject(forKey: "AppleLocale")
        default:
            d.removeObject(forKey: "AppleLanguages")
            d.removeObject(forKey: "AppleLocale")
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        d.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
