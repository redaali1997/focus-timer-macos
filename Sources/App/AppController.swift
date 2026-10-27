import AppKit
import SwiftUI
import ServiceManagement

/// Wires the managers together and handles app-level actions (windows, URL scheme, dock icon).
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    /// Captured from a SwiftUI view so non-view code can open scenes.
    var openWindow: OpenWindowAction?
    var dismissWindow: DismissWindowAction?
    private(set) var compactVisible = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        applyDockPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let session = SessionManager.shared
        session.listeners = [
            { SoundManager.shared.handle($0) },
            { NotificationManager.shared.handle($0) },
            { OverlayManager.shared.handle($0) },
            { AutomationManager.shared.handle($0) },
            { FocusManager.shared.handle($0) },
            { _ in AppController.shared.writeStatusFile() },
        ]
        NotificationManager.shared.setUp()
        HotKeyManager.shared.reload()
        session.armForLaunch()
        writeStatusFile()
        if AppSettings.shared.preferCompactSize {
            DispatchQueue.main.async { self.toggleCompact() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle(url:))
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.stop()
    }

    // MARK: - Windows

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
    }

    func showStats() {
        UserDefaults.standard.set("stats", forKey: "mainTab")
        showMainWindow()
    }

    func toggleCompact() {
        if compactVisible {
            dismissWindow?(id: "compact")
        } else {
            openWindow?(id: "compact")
        }
    }

    func compactDidAppear(_ visible: Bool) { compactVisible = visible }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(AppSettings.shared.showDockIcon ? .regular : .accessory)
    }

    func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    // MARK: - URL scheme: focustimer://<command>

    func handle(url: URL) {
        guard url.scheme == "focustimer" else { return }
        let session = SessionManager.shared
        let command = url.host ?? ""
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch command {
        case "start": session.status == .paused ? session.resume() : session.start()
        case "pause": session.pause()
        case "resume": session.resume()
        case "toggle": session.toggle()
        case "skip": session.skip()
        case "stop": session.stop()
        case "reset": session.resetSession()
        case "extend": session.extend(by: TimeInterval(items.first { $0.name == "seconds" }?.value ?? "60") ?? 60)
        case "rewind": session.rewind()
        case "pomodoro": session.start(.pomodoro)
        case "short-break": session.start(.shortBreak)
        case "long-break": session.start(.longBreak)
        case "break": session.start(session.completedInCycle >= AppSettings.shared.cycles ? .longBreak : .shortBreak)
        case "task": session.task = items.first { $0.name == "name" }?.value ?? ""
        case "profile":
            let name = items.first { $0.name == "name" }?.value ?? ""
            session.profileID = AppSettings.shared.focusProfiles.first { $0.name == name }?.id
        case "show": showMainWindow()
        case "stats": showStats()
        case "compact": toggleCompact()
        default: break
        }
    }

    // MARK: - Status file for scripts / CLI (`focustimer status`)

    static let statusFile = StatsStore.directory.appendingPathComponent("status.json")

    func writeStatusFile() {
        let session = SessionManager.shared
        let endsAt: Date? = session.status == .running ? Date().addingTimeInterval(session.remaining) : nil
        let status: [String: Any] = [
            "phase": session.phase.rawValue,
            "status": session.status.rawValue,
            "duration": Int(session.duration),
            "remaining": Int(session.remaining),
            "ends_at": endsAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "task": session.task,
            "completed_in_cycle": session.completedInCycle,
            "pomodoros_today": StatsStore.shared.pomodorosToday,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.statusFile, options: .atomic)
        }
    }
}
