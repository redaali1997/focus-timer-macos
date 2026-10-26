import Foundation

/// A user-defined shell command run on timer events (the "Automation" panel of the original app).
struct AutomationAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = String(localized: "New Action")
    var enabled = true
    var events: Set<TimerEvent> = [.finished]
    /// Only run for these phases (empty = any).
    var phases: Set<Phase> = []
    var command = ""
}

struct AutomationLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let action: String
    let event: TimerEvent
    let exitCode: Int32
    let output: String
}

/// Runs automation commands with the timer state exposed as environment variables
/// (FT_EVENT, FT_PHASE, FT_STATUS, FT_DURATION, FT_ELAPSED, FT_REMAINING, FT_TASK, FT_POMODOROS_TODAY).
@MainActor
final class AutomationManager: ObservableObject {
    static let shared = AutomationManager()

    @Published private(set) var log: [AutomationLogEntry] = []

    func handle(_ event: TimerEvent) {
        let session = SessionManager.shared
        let phase = session.lastEventPhase
        for action in AppSettings.shared.automations
        where action.enabled && action.events.contains(event) && (action.phases.isEmpty || action.phases.contains(phase)) {
            run(action, event: event)
        }
    }

    func run(_ action: AutomationAction, event: TimerEvent) {
        let session = SessionManager.shared
        var env = ProcessInfo.processInfo.environment
        env["FT_EVENT"] = event.rawValue
        env["FT_PHASE"] = session.lastEventPhase.rawValue
        env["FT_STATUS"] = session.status.rawValue
        env["FT_DURATION"] = String(Int(session.duration))
        env["FT_ELAPSED"] = String(Int(session.elapsed))
        env["FT_REMAINING"] = String(Int(session.remaining))
        env["FT_TASK"] = session.task
        env["FT_POMODOROS_TODAY"] = String(StatsStore.shared.pomodorosToday)
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        let command = action.command
        let name = action.name

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var output = ""
            var code: Int32 = -1
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                output = String(decoding: data, as: UTF8.self)
                code = process.terminationStatus
            } catch {
                output = error.localizedDescription
            }
            let entry = AutomationLogEntry(date: Date(), action: name, event: event, exitCode: code,
                                           output: output.trimmingCharacters(in: .whitespacesAndNewlines))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let manager = AutomationManager.shared
                    manager.log.insert(entry, at: 0)
                    if manager.log.count > 50 { manager.log.removeLast() }
                }
            }
        }
    }
}
