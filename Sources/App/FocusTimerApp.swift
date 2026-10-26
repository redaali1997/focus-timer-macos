import SwiftUI

@main
struct FocusTimerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegateProxy
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("Focus Timer", id: "main") {
            MainView()
                .frame(minWidth: 380, minHeight: 600)
                .preferredColorScheme(settings.colorScheme.colorScheme)
        }
        .defaultSize(width: 440, height: 640)
        .commands { TimerCommands() }

        Window("Compact Timer", id: "compact") {
            CompactTimerView()
                .preferredColorScheme(settings.colorScheme.colorScheme)
        }
        .windowStyle(.plain)
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .preferredColorScheme(settings.colorScheme.colorScheme)
        }

        MenuBarExtra {
            MenuBarMenu()
        } label: {
            MenuBarLabel()
        }
    }
}

/// `NSApplicationDelegateAdaptor` needs a type it can instantiate; forward to the shared controller.
final class AppDelegateProxy: NSObject, NSApplicationDelegate {
    @MainActor func applicationWillFinishLaunching(_ n: Notification) { AppController.shared.applicationWillFinishLaunching(n) }
    @MainActor func applicationDidFinishLaunching(_ n: Notification) { AppController.shared.applicationDidFinishLaunching(n) }
    @MainActor func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    @MainActor func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        AppController.shared.applicationShouldHandleReopen(s, hasVisibleWindows: f)
    }
    @MainActor func application(_ a: NSApplication, open urls: [URL]) { AppController.shared.application(a, open: urls) }
    @MainActor func applicationWillTerminate(_ n: Notification) { AppController.shared.applicationWillTerminate(n) }
}

struct TimerCommands: Commands {
    @ObservedObject private var state = SessionState.shared
    private let session = SessionManager.shared

    var body: some Commands {
        CommandMenu("Timer") {
            Button(toggleTitle) { session.toggle() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Skip") { session.skip() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(state.status == .stopped)
            Button("Stop") { session.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(state.status == .stopped)
            Button("Add One Minute") { session.extend(by: 60) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(state.status == .stopped)
            Button("Restart Interval") { session.rewind() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!(state.status == .running || state.status == .paused))
            Divider()
            ForEach(Phase.allCases) { phase in
                Button("Start \(phase.title)") { session.start(phase) }
            }
            Button("Reset Session") { session.resetSession() }
            Divider()
            Button("Compact Timer") { AppController.shared.toggleCompact() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }

    private var toggleTitle: String {
        switch state.status {
        case .stopped, .waiting: String(localized: "Start")
        case .running: String(localized: "Pause")
        case .paused: String(localized: "Resume")
        }
    }
}
