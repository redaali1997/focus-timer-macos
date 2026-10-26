import SwiftUI

/// Small always-on-top timer.
struct CompactTimerView: View {
    @ObservedObject private var session = SessionManager.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                TimerRing(progress: session.progress, color: session.phase.color, lineWidth: 4)
                Image(systemName: session.phase.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(session.phase.color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text(formatClock(session.remaining))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(session.task.isEmpty ? session.phase.title : session.task)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            HStack(spacing: 4) {
                Button { session.toggle() } label: {
                    Image(systemName: session.status == .running ? "pause.fill" : "play.fill")
                }
                Button { session.skip() } label: { Image(systemName: "forward.end.fill") }
                Button { AppController.shared.toggleCompact() } label: { Image(systemName: "xmark") }
                    .opacity(hovering ? 1 : 0)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(session.phase.color.opacity(0.4)))
        .onHover { hovering = $0 }
        .modifier(WindowActionsCapture())
        .onAppear { AppController.shared.compactDidAppear(true) }
        .onDisappear { AppController.shared.compactDidAppear(false) }
        .gesture(WindowDragGesture())
    }
}

struct MenuBarLabel: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: session.status == .stopped ? "timer" : session.phase.symbol)
            if settings.showTimeInMenuBar, session.isActive {
                Text(formatClock(session.remaining)).monospacedDigit()
            }
        }
        .modifier(WindowActionsCapture())
    }
}

struct MenuBarMenu: View {
    @ObservedObject private var session = SessionState.shared
    private let manager = SessionManager.shared
    @ObservedObject private var stats = StatsStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Text(headline)
        Text("Today: \(stats.pomodorosToday)/\(settings.dailyGoal) pomodoros")
        Divider()
        Button(toggleTitle) { manager.toggle() }
        if session.status != .stopped {
            Button("Skip") { manager.skip() }
            Button("+1 Minute") { manager.extend(by: 60) }
            Button("Stop") { manager.stop() }
        }
        Divider()
        ForEach(Phase.allCases) { phase in
            Button("Start \(phase.title)") { manager.start(phase) }
        }
        Divider()
        Button("Show Timer") { AppController.shared.showMainWindow() }
        Button("Compact Timer") { AppController.shared.toggleCompact() }
        Button("Statistics") { AppController.shared.showStats() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Focus Timer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var headline: String {
        switch session.status {
        case .stopped: String(localized: "Timer stopped")
        case .running: String(localized: "\(session.phase.title) — running")
        case .paused: String(localized: "\(session.phase.title) — paused")
        case .waiting: String(localized: "Waiting to start \(session.phase.title)")
        }
    }

    private var toggleTitle: String {
        switch session.status {
        case .stopped: String(localized: "Start Pomodoro")
        case .running: String(localized: "Pause")
        case .paused: String(localized: "Resume")
        case .waiting: String(localized: "Start \(session.phase.title)")
        }
    }
}

/// Content of the full-screen break overlay.
struct OverlayView: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var settings: AppSettings
    var dismiss: () -> Void

    var body: some View {
        ZStack {
            if settings.blurEffect {
                VisualEffectBackground().ignoresSafeArea()
            }
            Color.black.opacity(settings.blurEffect ? 0.35 : 0.85).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if settings.dismissGesture { dismiss() } }

            VStack(spacing: 28) {
                Image(systemName: session.phase.symbol)
                    .font(.system(size: 48))
                    .foregroundStyle(session.phase.color)
                Text(session.phase == .longBreak ? "Take a long break" as LocalizedStringKey : "Take a break")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(formatClock(session.remaining))
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(tip)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 16) {
                    Button("Skip Break") { session.skip() }
                    Button("+1 Minute") { session.extend(by: 60) }
                    Button("Dismiss") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.extraLarge)
                .padding(.top, 10)
            }
            .foregroundStyle(.white)
        }
    }

    private var tip: String {
        let tips = [String(localized: "Stand up and stretch."), String(localized: "Look at something 20 feet away."),
                    String(localized: "Drink some water."), String(localized: "Take a few deep breaths."),
                    String(localized: "Walk around for a minute."), String(localized: "Rest your eyes.")]
        // Rotates every minute.
        return tips[Int(Date().timeIntervalSince1970 / 60) % tips.count]
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
