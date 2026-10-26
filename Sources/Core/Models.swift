import Foundation
import SwiftUI

enum Phase: String, Codable, CaseIterable, Identifiable {
    case pomodoro, shortBreak, longBreak

    var id: String { rawValue }
    var isBreak: Bool { self != .pomodoro }

    var title: String {
        switch self {
        case .pomodoro: String(localized: "Pomodoro")
        case .shortBreak: String(localized: "Short Break")
        case .longBreak: String(localized: "Long Break")
        }
    }

    var symbol: String {
        switch self {
        case .pomodoro: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .pomodoro: Color(red: 0.93, green: 0.33, blue: 0.29)
        case .shortBreak: Color(red: 0.18, green: 0.68, blue: 0.58)
        case .longBreak: Color(red: 0.27, green: 0.52, blue: 0.90)
        }
    }
}

enum TimerStatus: String, Codable {
    /// Nothing is running.
    case stopped
    case running
    case paused
    /// The previous interval finished and the next one waits for confirmation.
    case waiting
}

/// A finished (or interrupted) interval, kept for statistics.
struct TimeBlock: Codable, Identifiable, Hashable {
    var id = UUID()
    var phase: Phase
    var start: Date
    var end: Date
    /// Planned length in seconds.
    var planned: TimeInterval
    /// Time actually spent, pauses excluded.
    var elapsed: TimeInterval
    var completed: Bool
    var task: String?
    var profile: String?
}

enum TimerEvent: String, Codable, CaseIterable, Identifiable {
    case started, paused, resumed, stopped, skipped, finished
    case pomodoroStarted, breakStarted, waiting, aboutToEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .started: String(localized: "Timer started")
        case .paused: String(localized: "Paused")
        case .resumed: String(localized: "Resumed")
        case .stopped: String(localized: "Stopped")
        case .skipped: String(localized: "Skipped")
        case .finished: String(localized: "Interval finished")
        case .pomodoroStarted: String(localized: "Pomodoro started")
        case .breakStarted: String(localized: "Break started")
        case .waiting: String(localized: "Waiting for confirmation")
        case .aboutToEnd: String(localized: "About to end")
        }
    }
}

func formatClock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    if m < 60 { return String(localized: "\(m)m") }
    return m % 60 == 0 ? String(localized: "\(m / 60)h") : String(localized: "\(m / 60)h \(m % 60)m")
}
