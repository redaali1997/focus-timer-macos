import AppKit
import SwiftUI

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen overlay covering every display during breaks.
@MainActor
final class OverlayManager {
    static let shared = OverlayManager()

    private var windows: [NSWindow] = []
    private var reopenWork: DispatchWorkItem?
    private var lockWork: DispatchWorkItem?
    private let settings = AppSettings.shared

    var isVisible: Bool { !windows.isEmpty }

    func handle(_ event: TimerEvent) {
        let session = SessionManager.shared
        switch event {
        case .breakStarted:
            if settings.screenOverlay { show() }
        case .pomodoroStarted, .stopped, .waiting:
            hide()
        case .finished where session.lastEventPhase.isBreak:
            hide()
        default:
            break
        }
    }

    func show() {
        reopenWork?.cancel()
        guard windows.isEmpty, SessionManager.shared.phase.isBreak else { return }
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = NSHostingView(rootView: OverlayView(
                session: SessionManager.shared, settings: settings,
                dismiss: { [weak self] in self?.dismiss() }))
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.6
                window.animator().alphaValue = 1
            }
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)

        if settings.screenOverlayLockDelay > 0 {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isVisible else { return }
                Self.lockScreen()
            }
            lockWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(settings.screenOverlayLockDelay), execute: work)
        }
    }

    /// User closed the overlay; reopen it later if the break is still on.
    func dismiss() {
        hide()
        guard settings.screenOverlayReopenDelay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            let session = SessionManager.shared
            if session.phase.isBreak, session.status == .running { self?.show() }
        }
        reopenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(settings.screenOverlayReopenDelay), execute: work)
    }

    func hide() {
        reopenWork?.cancel()
        lockWork?.cancel()
        let closing = windows
        windows = []
        for window in closing {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }

    static func lockScreen() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}
