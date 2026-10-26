import AppKit
import Carbon.HIToolbox

enum HotKeyAction: String, Codable, CaseIterable, Identifiable {
    case toggle, skip, stop, extend, showWindow, compact
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggle: String(localized: "Start / Pause / Resume")
        case .skip: String(localized: "Skip to next interval")
        case .stop: String(localized: "Stop timer")
        case .extend: String(localized: "Add one minute")
        case .showWindow: String(localized: "Show main window")
        case .compact: String(localized: "Toggle compact timer")
        }
    }

    static let defaults: [HotKeyAction: KeyCombo] = [
        .toggle: KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥P"),
        .skip: KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥S"),
        .stop: KeyCombo(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥X"),
    ]

    @MainActor
    func perform() {
        let session = SessionManager.shared
        switch self {
        case .toggle: session.toggle()
        case .skip: session.skip()
        case .stop: session.stop()
        case .extend: session.extend(by: 60)
        case .showWindow: AppController.shared.showMainWindow()
        case .compact: AppController.shared.toggleCompact()
        }
    }
}

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    /// Carbon modifier flags.
    var modifiers: UInt32
    var display: String

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }
        var carbon: UInt32 = 0
        var text = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); text += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); text += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); text += "⌘" }
        let key = Self.keyNames[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, display: text + key)
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// System-wide shortcuts via Carbon's RegisterEventHotKey (no accessibility permission needed).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: HotKeyAction] = [:]
    private var handlerInstalled = false
    /// Suspended while the user records a new shortcut.
    var isSuspended = false

    func reload() {
        installHandler()
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
        guard !isSuspended else { return }
        for (index, (action, combo)) in AppSettings.shared.hotKeys.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4654_4D52), id: id) // "FTMR"
            if RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
                actions[id] = action
            }
        }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?.perform()
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyManager.shared.fire(id) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
