import Foundation
import AppKit
import CoreGraphics

/// Phase and status without the per-tick elapsed time, for views that must not re-render
/// every tick (re-rendering the menu bar menu moves its highlight).
@MainActor
final class SessionState: ObservableObject {
    static let shared = SessionState()
    @Published fileprivate(set) var phase: Phase = .pomodoro
    @Published fileprivate(set) var status: TimerStatus = .stopped
}

/// The Pomodoro state machine: pomodoro → short break → … → long break, every `cycles` pomodoros.
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var phase: Phase = .pomodoro {
        didSet { if SessionState.shared.phase != phase { SessionState.shared.phase = phase } }
    }
    @Published private(set) var status: TimerStatus = .stopped {
        didSet { if SessionState.shared.status != status { SessionState.shared.status = status } }
    }
    @Published private(set) var duration: TimeInterval
    @Published private(set) var elapsed: TimeInterval = 0
    /// Pomodoros completed since the last long break.
    @Published private(set) var completedInCycle = 0
    @Published var task: String = UserDefaults.standard.string(forKey: "currentTask") ?? "" {
        didSet {
            UserDefaults.standard.set(task, forKey: "currentTask")
            // Tasks remember the focus profile they were last used with.
            if let id = taskProfiles[taskKey].flatMap(UUID.init(uuidString:)), id != profileID { profileID = id }
        }
    }
    /// Focus profile for the current task (see FocusManager).
    @Published var profileID: UUID? = UserDefaults.standard.string(forKey: "currentProfile").flatMap(UUID.init(uuidString:)) {
        didSet {
            UserDefaults.standard.set(profileID?.uuidString, forKey: "currentProfile")
            if !taskKey.isEmpty { taskProfiles[taskKey] = profileID?.uuidString }
            FocusManager.shared.profileChanged()
        }
    }
    private var taskKey: String { task.trimmingCharacters(in: .whitespaces).lowercased() }
    private var taskProfiles: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "taskProfiles") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "taskProfiles") }
    }

    var remaining: TimeInterval { max(0, duration - elapsed) }
    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 0 }
    var isActive: Bool { status == .running || status == .paused }
    /// Waiting for the user to come back rather than for an explicit "Start".
    var waitsForActivity: Bool { status == .waiting && phase == .pomodoro && settings.startPomodoroOnActivity }

    /// Observers of timer events (sounds, notifications, overlay, automation…).
    var listeners: [(TimerEvent) -> Void] = []

    private let settings = AppSettings.shared
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date?
    private var blockStart: Date?
    private var pausedAt: Date?
    private var stoppedAt: Date?
    private var waitingSince: Date?
    private var announced = false
    private var pausedByLock = false
    private var ticker: Timer?

    private init() {
        duration = AppSettings.shared.duration(for: .pomodoro)
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { SessionManager.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        observeSystem()
    }

    // MARK: - Public actions

    /// Start/pause/resume depending on the current state.
    func toggle() {
        switch status {
        case .stopped, .waiting: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    /// Start the given phase, or the pending/current one.
    func start(_ requested: Phase? = nil) {
        if let requested, isActive {
            recordCurrent(completed: false)
        }
        if status == .stopped, let stoppedAt, Date().timeIntervalSince(stoppedAt) > TimeInterval(settings.expiryTimeout) {
            completedInCycle = 0
        }
        begin(requested ?? phase)
    }

    func pause() {
        guard status == .running, let resumedAt else { return }
        accumulated += Date().timeIntervalSince(resumedAt)
        self.resumedAt = nil
        pausedAt = Date()
        status = .paused
        emit(.paused)
    }

    func resume() {
        guard status == .paused else { return }
        resumedAt = Date()
        pausedAt = nil
        pausedByLock = false
        status = .running
        emit(.resumed)
    }

    /// Jump to the next interval right away.
    func skip() {
        if isActive { recordCurrent(completed: false) }
        emit(.skipped)
        let next = nextPhase(after: phase)
        if phase == .longBreak { completedInCycle = 0 }
        begin(next)
    }

    /// Stop the timer. The cycle position is kept until the session expires.
    func stop() {
        guard status != .stopped else { return }
        if isActive { recordCurrent(completed: false) }
        resetInterval(to: .pomodoro)
        status = .stopped
        stoppedAt = Date()
        emit(.stopped)
    }

    /// Stop and forget the cycle position.
    func resetSession() {
        stop()
        completedInCycle = 0
    }

    /// Add (or remove, with a negative value) time to the current interval.
    func extend(by seconds: TimeInterval) {
        guard status != .stopped else { return }
        duration = max(elapsed + 5, duration + seconds)
        if remaining > TimeInterval(settings.announcementLeadTime) { announced = false }
        AppController.shared.writeStatusFile()
    }

    /// Restart the current interval from zero.
    func rewind() {
        guard isActive else { return }
        accumulated = 0
        if status == .running { resumedAt = Date() }
        elapsed = 0
        announced = false
        AppController.shared.writeStatusFile()
    }

    /// Re-read durations when settings change while idle.
    func settingsChanged() {
        if status == .stopped || status == .waiting {
            duration = settings.duration(for: phase)
        }
    }

    // MARK: - Internals

    private func begin(_ p: Phase) {
        resetInterval(to: p)
        blockStart = Date()
        resumedAt = Date()
        status = .running
        emit(.started)
        emit(p.isBreak ? .breakStarted : .pomodoroStarted)
    }

    private func resetInterval(to p: Phase) {
        phase = p
        duration = settings.duration(for: p)
        accumulated = 0
        elapsed = 0
        resumedAt = nil
        pausedAt = nil
        pausedByLock = false
        announced = false
        blockStart = nil
    }

    private func nextPhase(after p: Phase) -> Phase {
        switch p {
        case .pomodoro: completedInCycle >= settings.cycles ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: .pomodoro
        }
    }

    private func tick() {
        let now = Date()
        if status == .running {
            elapsed = accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
            let lead = TimeInterval(settings.announcementLeadTime)
            if !announced, settings.announceAboutToEnd, remaining <= lead, duration > lead * 2 {
                announced = true
                emit(.aboutToEnd)
            }
            if elapsed >= duration { finish() }
        } else if status == .paused, let pausedAt,
                  now.timeIntervalSince(pausedAt) > TimeInterval(settings.expiryTimeout) {
            expire()
        } else if status == .waiting, waitsForActivity, let waitingSince, !Self.isScreenLocked {
            // Any mouse/keyboard input after the break ended means the user is back.
            // Input on the lock screen (e.g. waking the Mac) doesn't count.
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle < now.timeIntervalSince(waitingSince) - 1 { start() }
        }
    }

    /// A paused interval went stale. With start-on-activity, wait for the user instead of stopping.
    private func expire() {
        guard settings.startPomodoroOnActivity else { return resetSession() }
        recordCurrent(completed: false)
        completedInCycle = 0
        resetInterval(to: .pomodoro)
        waitingSince = Date()
        status = .waiting
        emit(.stopped)
    }

    private func finish() {
        let finished = phase
        recordCurrent(completed: true)
        if finished == .pomodoro { completedInCycle += 1 }
        let next = nextPhase(after: finished)
        if finished == .longBreak { completedInCycle = 0 }
        emit(.finished, phase: finished)

        let needsConfirmation = next.isBreak
            ? settings.confirmStartingBreak
            : settings.confirmStartingPomodoro || settings.startPomodoroOnActivity
        if needsConfirmation {
            resetInterval(to: next)
            waitingSince = Date()
            status = .waiting
            emit(.waiting)
        } else {
            begin(next)
        }
    }

    private func recordCurrent(completed: Bool) {
        guard let blockStart else { return }
        let spent = completed ? duration : elapsed
        guard spent >= 5 else { return }
        StatsStore.shared.add(TimeBlock(
            phase: phase, start: blockStart, end: Date(), planned: duration,
            elapsed: spent, completed: completed,
            task: task.trimmingCharacters(in: .whitespaces).isEmpty ? nil : task,
            profile: FocusManager.shared.currentProfile?.name))
        self.blockStart = nil
    }

    private func emit(_ event: TimerEvent, phase override: Phase? = nil) {
        lastEventPhase = override ?? phase
        for listener in listeners { listener(event) }
    }

    /// Phase the last emitted event refers to (differs from `phase` for `.finished`).
    private(set) var lastEventPhase: Phase = .pomodoro

    // MARK: - Lock screen & sleep

    private func observeSystem() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SessionManager.shared.screenLocked() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SessionManager.shared.screenUnlocked() }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SessionManager.shared.screenLocked() }
        }
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SessionManager.shared.tick() }
            // Woke without a lock screen: no unlock notification will come, so resume here.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated {
                    if !SessionManager.isScreenLocked { SessionManager.shared.screenUnlocked() }
                }
            }
        }
    }

    private func screenLocked() {
        guard settings.pauseOnLockScreen, status == .running, phase == .pomodoro else { return }
        pause()
        pausedByLock = true
    }

    static var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func screenUnlocked() {
        if pausedByLock, status == .paused { resume() }
    }
}
