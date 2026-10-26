import SwiftUI

/// Captures window actions so AppController can open scenes from non-view code.
struct WindowActionsCapture: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content.onAppear {
            AppController.shared.openWindow = openWindow
            AppController.shared.dismissWindow = dismissWindow
        }
    }
}

struct MainView: View {
    @AppStorage("mainTab") private var tab = "timer"
    @ObservedObject private var session = SessionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Timer").tag("timer")
                Text("Stats").tag("stats")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .padding(.top, 10)

            if tab == "stats" {
                StatsView()
            } else {
                TimerView()
            }
        }
        .modifier(WindowActionsCapture())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppController.shared.toggleCompact()
                } label: {
                    Label("Compact Timer", systemImage: "pip")
                }
                .help("Compact floating timer (⇧⌘K)")
            }
        }
        .background(session.phase.color.opacity(tab == "timer" ? 0.08 : 0))
    }
}

struct TimerView: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stats = StatsStore.shared

    var body: some View {
        VStack(spacing: 16) {
            phaseMenu
            ZStack {
                TimerRing(progress: session.progress, color: session.phase.color, lineWidth: 12)
                VStack(spacing: 6) {
                    Text(formatClock(session.remaining))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 230, height: 230)

            CycleIndicator(completed: session.completedInCycle, total: settings.cycles,
                           current: session.phase == .pomodoro && session.status != .stopped)

            VStack(spacing: 6) {
                TextField("What are you working on?", text: $session.task)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .padding(.horizontal, 40)
                ProfileMenu()
            }

            controls

            goalBar
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: session.phase)
    }

    private var phaseMenu: some View {
        Menu {
            ForEach(Phase.allCases) { phase in
                Button {
                    session.start(phase)
                } label: {
                    Label(phase.title, systemImage: phase.symbol)
                }
            }
        } label: {
            Label(session.phase.title, systemImage: session.phase.symbol)
                .font(.headline)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(session.phase.color)
    }

    private var statusText: String {
        switch session.status {
        case .stopped: String(localized: "Ready")
        case .running: session.phase.isBreak ? String(localized: "Relax") : String(localized: "Focus")
        case .paused: String(localized: "Paused")
        case .waiting: session.waitsForActivity
            ? String(localized: "Starts when you're back")
            : String(localized: "Start \(session.phase.title)?")
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            CircleButton(symbol: "stop.fill", help: "Stop (⌘.)") { session.stop() }
                .disabled(session.status == .stopped)
            Button {
                session.toggle()
            } label: {
                Image(systemName: session.status == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(session.phase.color))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Start / Pause (⌘↩)")
            CircleButton(symbol: "forward.end.fill", help: "Skip (⌘→)") { session.skip() }
        }
        .overlay(alignment: .trailing) {
            if session.status != .stopped {
                Button("+1 min") { session.extend(by: 60) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .offset(x: 70)
            }
        }
    }

    private var goalBar: some View {
        let done = stats.pomodorosToday
        return VStack(spacing: 4) {
            ProgressView(value: Double(min(done, settings.dailyGoal)), total: Double(max(1, settings.dailyGoal)))
                .tint(Phase.pomodoro.color)
            HStack {
                Text("Today: \(done)/\(settings.dailyGoal) pomodoros")
                Spacer()
                if stats.streak > 0 { Text("🔥 \(stats.streak) day streak") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 300)
    }
}

struct TimerRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

struct CycleIndicator: View {
    var completed: Int
    var total: Int
    var current: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < completed ? Phase.pomodoro.color : Color.secondary.opacity(0.25))
                    .overlay(Circle().stroke(Phase.pomodoro.color, lineWidth: i == completed && current ? 2 : 0))
                    .frame(width: 10, height: 10)
            }
        }
        .help("\(completed) of \(total) pomodoros until a long break")
    }
}

struct CircleButton: View {
    var symbol: String
    var help: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Chooses the focus profile (Focus mode + blocked apps) for the current task.
struct ProfileMenu: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var focus = FocusManager.shared

    var body: some View {
        let profile = settings.focusProfiles.first { $0.id == session.profileID }
        Menu {
            Button("No focus profile") { session.profileID = nil }
            Divider()
            ForEach(settings.focusProfiles) { p in
                Button { session.profileID = p.id } label: { Text(verbatim: "\(p.emoji) \(p.name)") }
            }
            Divider()
            SettingsLink { Text("Edit profiles…") }
        } label: {
            HStack(spacing: 4) {
                if let profile {
                    Text(verbatim: "\(profile.emoji) \(profile.name)")
                    if focus.activeProfile != nil {
                        Image(systemName: "moon.fill").foregroundStyle(.indigo)
                    }
                } else {
                    Text("No focus profile")
                }
            }
            .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help(profile.map { p in p.blockedApps.isEmpty ? p.name : p.blockedApps.map(\.name).joined(separator: ", ") } ?? "")
    }
}
