import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            TimerSettings().tabItem { Label("Timer", systemImage: "timer") }
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell.badge") }
            SoundSettings().tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            FocusSettings().tabItem { Label("Focus Mode", systemImage: "moon") }
            AutomationSettings().tabItem { Label("Automation", systemImage: "gearshape.2") }
            IntegrationSettings().tabItem { Label("Integrations", systemImage: "terminal") }
        }
        .frame(width: 620, height: 520)
    }
}

/// Edits a duration stored in seconds as whole minutes.
struct MinutesRow: View {
    var title: LocalizedStringKey
    @Binding var seconds: Int
    var range: ClosedRange<Int> = 1...240

    var body: some View {
        let minutes = Binding(get: { seconds / 60 }, set: { seconds = $0 * 60 })
        Stepper(value: minutes, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(seconds / 60) min").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Timer

struct TimerSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Section("Durations") {
                MinutesRow(title: "Pomodoro", seconds: $s.pomodoroDuration)
                MinutesRow(title: "Short break", seconds: $s.shortBreakDuration)
                MinutesRow(title: "Long break", seconds: $s.longBreakDuration)
                Stepper(value: $s.cycles, in: 1...10) {
                    HStack {
                        Text("Pomodoros before a long break")
                        Spacer()
                        Text("\(s.cycles)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Presets")
                    Spacer()
                    Button("25 / 5") { apply(25, 5, 15) }
                    Button("50 / 10") { apply(50, 10, 30) }
                    Button("90 / 20") { apply(90, 20, 30) }
                }
            }
            Section("Flow") {
                Toggle("Wait for confirmation before starting a break", isOn: $s.confirmStartingBreak)
                Toggle("Wait for confirmation before starting a pomodoro", isOn: $s.confirmStartingPomodoro)
                Toggle("After a break, start the pomodoro when I'm back (mouse or keyboard)", isOn: $s.startPomodoroOnActivity)
                    .disabled(s.confirmStartingPomodoro)
                Toggle("Pause pomodoro when the screen locks or Mac sleeps", isOn: $s.pauseOnLockScreen)
                Picker("Session expires after inactivity", selection: $s.expiryTimeout) {
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                    Text("2 hours").tag(7200)
                    Text("4 hours").tag(14400)
                }
            }
            Section("Goal") {
                Stepper(value: $s.dailyGoal, in: 1...24) {
                    HStack {
                        Text("Daily goal")
                        Spacer()
                        Text("\(s.dailyGoal) pomodoros").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: s.pomodoroDuration) { SessionManager.shared.settingsChanged() }
        .onChange(of: s.shortBreakDuration) { SessionManager.shared.settingsChanged() }
        .onChange(of: s.longBreakDuration) { SessionManager.shared.settingsChanged() }
    }

    private func apply(_ work: Int, _ short: Int, _ long: Int) {
        s.pomodoroDuration = work * 60
        s.shortBreakDuration = short * 60
        s.longBreakDuration = long * 60
    }
}

// MARK: - Notifications

struct NotificationSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show notifications when intervals start or end", isOn: $s.notificationsEnabled)
                Toggle("Announce when time is running out", isOn: $s.announceAboutToEnd)
                Stepper(value: $s.announcementLeadTime, in: 5...300, step: 5) {
                    HStack {
                        Text("Announce before the end")
                        Spacer()
                        Text("\(s.announcementLeadTime) s").foregroundStyle(.secondary)
                    }
                }
                .disabled(!s.announceAboutToEnd)
            }
            Section("Screen overlay") {
                Toggle("Cover the screen during breaks", isOn: $s.screenOverlay)
                Picker("Reopen after dismissing", selection: $s.screenOverlayReopenDelay) {
                    Text("Never").tag(0)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .disabled(!s.screenOverlay)
                Picker("Lock the screen after", selection: $s.screenOverlayLockDelay) {
                    Text("Never").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
                .disabled(!s.screenOverlay)
                Toggle("Click anywhere to dismiss", isOn: $s.dismissGesture)
                    .disabled(!s.screenOverlay)
                Button("Preview overlay") {
                    if !SessionManager.shared.phase.isBreak { SessionManager.shared.start(.shortBreak) }
                    OverlayManager.shared.show()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sounds

struct SoundSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Enable sounds", isOn: $s.soundsEnabled)
            Section("Pomodoro finished") {
                SoundPicker(selection: $s.pomodoroFinishedSound, options: SoundManager.alertSounds)
                VolumeRow(volume: $s.pomodoroFinishedVolume) {
                    SoundManager.shared.play(s.pomodoroFinishedSound, volume: s.pomodoroFinishedVolume)
                }
            }
            .disabled(!s.soundsEnabled)
            Section("Break finished") {
                SoundPicker(selection: $s.breakFinishedSound, options: SoundManager.alertSounds)
                VolumeRow(volume: $s.breakFinishedVolume) {
                    SoundManager.shared.play(s.breakFinishedSound, volume: s.breakFinishedVolume)
                }
            }
            .disabled(!s.soundsEnabled)
            Section {
                SoundPicker(selection: $s.backgroundSound, options: SoundManager.backgroundSounds)
                VolumeRow(volume: $s.backgroundVolume) {
                    SoundManager.shared.play(s.backgroundSound, volume: s.backgroundVolume)
                }
            } header: {
                Text("Background sound")
            } footer: {
                Text("Plays in a loop while a pomodoro is running.").foregroundStyle(.secondary)
            }
            .disabled(!s.soundsEnabled)
        }
        .formStyle(.grouped)
    }
}

struct SoundPicker: View {
    @Binding var selection: String
    var options: [SoundOption]

    var body: some View {
        HStack {
            Picker("Sound", selection: $selection) {
                ForEach(options) { Text($0.name).tag($0.id) }
                if selection.hasPrefix("/") {
                    Text(SoundManager.displayName(for: selection)).tag(selection)
                }
            }
            Button("Custom…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.audio]
                if panel.runModal() == .OK, let url = panel.url { selection = url.path }
            }
        }
    }
}

struct VolumeRow: View {
    @Binding var volume: Double
    var preview: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            Button { preview() } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .help("Preview")
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @ObservedObject private var s = AppSettings.shared
    @State private var launchAtLogin = AppController.shared.launchAtLogin
    @State private var initialLanguage = AppSettings.shared.language

    var body: some View {
        Form {
            Picker("Appearance", selection: $s.colorScheme) {
                Text("System").tag(ColorSchemePreference.system)
                Text("Light").tag(ColorSchemePreference.light)
                Text("Dark").tag(ColorSchemePreference.dark)
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("Language", selection: $s.language) {
                    Text("System").tag("system")
                    Text(verbatim: "العربية").tag("ar")
                    Text(verbatim: "English").tag("en")
                }
                if s.language != initialLanguage {
                    Button("Restart to apply") { AppController.shared.relaunch() }
                }
            }
            Toggle("Open compact timer on launch", isOn: $s.preferCompactSize)
            Toggle("Blur behind the break overlay", isOn: $s.blurEffect)
            Toggle("Show remaining time in the menu bar", isOn: $s.showTimeInMenuBar)
            Toggle("Show Dock icon", isOn: $s.showDockIcon)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in AppController.shared.launchAtLogin = value }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

struct ShortcutSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(combo: Binding(
                            get: { s.hotKeys[action] },
                            set: { s.hotKeys[action] = $0 }))
                    }
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Work from any app. Click a shortcut to record a new one, press Delete to clear, Esc to cancel.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore defaults") { s.hotKeys = HotKeyAction.defaults }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? String(localized: "Type shortcut…") : combo?.display ?? String(localized: "None"))
                .monospaced()
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.isSuspended = true
        HotKeyManager.shared.reload()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: stop() // Esc
            case 51, 117: combo = nil; stop() // Delete
            default:
                if let new = KeyCombo(event: event) { combo = new; stop() }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        HotKeyManager.shared.isSuspended = false
        HotKeyManager.shared.reload()
    }
}

// MARK: - Automation

struct AutomationSettings: View {
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var manager = AutomationManager.shared
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(s.automations) { action in
                        HStack {
                            Image(systemName: action.enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(action.enabled ? Color.green : .secondary)
                            Text(action.name)
                        }
                        .tag(action.id)
                    }
                }
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 150, maxWidth: 180)

            if let index = s.automations.firstIndex(where: { $0.id == selection }) {
                AutomationEditor(action: $s.automations[index])
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Run shell commands on timer events").font(.headline)
                    Text("For example: turn on Do Not Disturb with a Shortcut, pause music, update Slack status, or log time.")
                        .foregroundStyle(.secondary)
                    Text("Variables: $FT_EVENT, $FT_PHASE, $FT_STATUS, $FT_DURATION, $FT_ELAPSED, $FT_REMAINING, $FT_TASK, $FT_POMODOROS_TODAY")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Divider()
                    Text("Recent runs").font(.headline)
                    List(manager.log) { entry in
                        VStack(alignment: .leading) {
                            Text("\(entry.action) · \(entry.event.title) · exit \(entry.exitCode)")
                                .foregroundStyle(entry.exitCode == 0 ? Color.primary : .red)
                            if !entry.output.isEmpty {
                                Text(entry.output).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func add() {
        let action = AutomationAction()
        s.automations.append(action)
        selection = action.id
    }

    private func remove() {
        s.automations.removeAll { $0.id == selection }
        selection = nil
    }
}

struct AutomationEditor: View {
    @Binding var action: AutomationAction

    var body: some View {
        Form {
            TextField("Name", text: $action.name)
            Toggle("Enabled", isOn: $action.enabled)
            Section("When") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]) {
                    ForEach(TimerEvent.allCases) { event in
                        Toggle(event.title, isOn: Binding(
                            get: { action.events.contains(event) },
                            set: { if $0 { action.events.insert(event) } else { action.events.remove(event) } }))
                    }
                }
                HStack {
                    Text("Only for")
                    ForEach(Phase.allCases) { phase in
                        Toggle(phase.title, isOn: Binding(
                            get: { action.phases.contains(phase) },
                            set: { if $0 { action.phases.insert(phase) } else { action.phases.remove(phase) } }))
                    }
                }
            }
            Section("Command") {
                TextEditor(text: $action.command)
                    .font(.body.monospaced())
                    .frame(minHeight: 70)
                Button("Run now") { AutomationManager.shared.run(action, event: .started) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Integrations

struct IntegrationSettings: View {
    private let cliPath = Bundle.main.url(forResource: "focustimer", withExtension: nil)?.path ?? ""

    var body: some View {
        Form {
            Section("URL scheme") {
                Text("Control the timer from Shortcuts, Raycast, Alfred, scripts or links:")
                    .foregroundStyle(.secondary)
                Text(verbatim: """
                focustimer://toggle    start · pause · resume · skip · stop · reset
                focustimer://pomodoro  short-break · long-break · break
                focustimer://extend?seconds=60   rewind
                focustimer://task?name=Writing   profile?name=Study
                focustimer://show      stats · compact
                """)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
            Section("Command-line tool") {
                Text("Install by linking it into your PATH:").foregroundStyle(.secondary)
                Text(verbatim: "ln -sf '\(cliPath)' /opt/homebrew/bin/focustimer")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Then: focustimer toggle · focustimer status · focustimer task \"Writing\"")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Section("Status file") {
                Text(verbatim: AppController.statusFile.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Updated on every timer event; use it in SketchyBar, Übersicht or your own scripts.")
                    .foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Export history as CSV…") { StatsStore.shared.exportCSV() }
                Button("Show data folder in Finder") { NSWorkspace.shared.open(StatsStore.directory) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Focus profiles

struct FocusSettings: View {
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var focus = FocusManager.shared
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(s.focusProfiles) { profile in
                        Text(verbatim: "\(profile.emoji) \(profile.name)").tag(profile.id)
                    }
                }
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 150, maxWidth: 180)

            if let index = s.focusProfiles.firstIndex(where: { $0.id == selection }) {
                FocusProfileEditor(profile: $s.focusProfiles[index])
            } else {
                Form {
                    Section {
                        Text("A profile decides what happens during a pomodoro for a kind of work: which macOS Focus turns on and which apps stay closed. Pick the profile under the task name; each task remembers its profile.")
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        ShortcutPicker(title: "When the break starts or the timer stops, run", selection: $s.focusOffShortcut)
                        Toggle("Reopen closed apps on the break", isOn: $s.reopenBlockedApps)
                    } header: {
                        Text("Turning focus off")
                    } footer: {
                        Text("macOS doesn't let apps switch Focus directly, so it's done through Shortcuts: make one shortcut per Focus with the \"Set Focus\" action (On), and one that turns Focus off.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                }
                .formStyle(.grouped)
            }
        }
        .onAppear { focus.reloadShortcuts() }
    }

    private func add() {
        let profile = FocusProfile()
        s.focusProfiles.append(profile)
        selection = profile.id
    }

    private func remove() {
        s.focusProfiles.removeAll { $0.id == selection }
        selection = nil
    }
}

struct ShortcutPicker: View {
    var title: LocalizedStringKey
    @Binding var selection: String
    @ObservedObject private var focus = FocusManager.shared

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag("")
            ForEach(focus.availableShortcuts, id: \.self) { Text(verbatim: $0).tag($0) }
            if !selection.isEmpty && !focus.availableShortcuts.contains(selection) {
                Text(verbatim: selection).tag(selection)
            }
        }
    }
}

struct FocusProfileEditor: View {
    @Binding var profile: FocusProfile

    var body: some View {
        Form {
            HStack {
                TextField("Emoji", text: $profile.emoji).frame(width: 50)
                TextField("Name", text: $profile.name)
            }
            Section("When a pomodoro starts") {
                ShortcutPicker(title: "Run shortcut (turn on Focus)", selection: $profile.focusOnShortcut)
                Button("Test") { FocusManager.shared.runShortcut(profile.focusOnShortcut) }
                    .disabled(profile.focusOnShortcut.isEmpty)
            }
            Section {
                ForEach(profile.blockedApps) { app in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 18, height: 18)
                        }
                        Text(verbatim: app.name)
                        Spacer()
                        Button {
                            profile.blockedApps.removeAll { $0.id == app.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add app…") { addApp() }
                Toggle("Hide them instead of quitting", isOn: $profile.hideInsteadOfQuit)
            } header: {
                Text("Keep these apps closed")
            } footer: {
                Text("They're closed when the pomodoro starts, and closed again if you open them before the break.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !profile.blockedApps.contains(where: { $0.bundleID == id }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            profile.blockedApps.append(BlockedApp(bundleID: id, name: name))
        }
    }
}
