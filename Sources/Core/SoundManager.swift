import AVFoundation
import AppKit

struct SoundOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Plays the "finished" alerts and the looping background sound during pomodoros.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    static let alertSounds: [SoundOption] = [
        .init(id: "", name: String(localized: "None")),
        .init(id: "bell", name: String(localized: "Bell")),
        .init(id: "loud-bell", name: String(localized: "Loud Bell")),
    ] + ["Glass", "Hero", "Ping", "Purr", "Submarine", "Tink", "Blow", "Funk"].map {
        .init(id: "system:\($0)", name: $0)
    }

    static let backgroundSounds: [SoundOption] = [
        .init(id: "", name: String(localized: "None")),
        .init(id: "clock", name: String(localized: "Clock Ticking")),
        .init(id: "metronome", name: String(localized: "Metronome")),
        .init(id: "brown-noise", name: String(localized: "Brown Noise")),
    ]

    private let settings = AppSettings.shared
    private var alertPlayer: AVAudioPlayer?
    private var backgroundPlayer: AVAudioPlayer?
    private var backgroundID: String?

    /// `id` is a bundled sound name, `system:<name>` or an absolute file path.
    static func url(for id: String) -> URL? {
        if id.isEmpty { return nil }
        if id.hasPrefix("/") { return URL(fileURLWithPath: id) }
        if id.hasPrefix("system:") {
            return URL(fileURLWithPath: "/System/Library/Sounds/\(id.dropFirst(7)).aiff")
        }
        return Bundle.main.url(forResource: id, withExtension: "m4a")
    }

    static func displayName(for id: String) -> String {
        if id.hasPrefix("/") { return URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent }
        return (alertSounds + backgroundSounds).first { $0.id == id }?.name ?? id
    }

    func play(_ id: String, volume: Double) {
        guard let url = Self.url(for: id), let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = Float(volume)
        player.play()
        alertPlayer = player
    }

    func handle(_ event: TimerEvent) {
        if event == .finished, settings.soundsEnabled {
            if SessionManager.shared.lastEventPhase == .pomodoro {
                play(settings.pomodoroFinishedSound, volume: settings.pomodoroFinishedVolume)
            } else {
                play(settings.breakFinishedSound, volume: settings.breakFinishedVolume)
            }
        }
        refreshBackground()
    }

    /// Background sound plays only while a pomodoro is running.
    func refreshBackground() {
        let session = SessionManager.shared
        let shouldPlay = settings.soundsEnabled && !settings.backgroundSound.isEmpty
            && session.status == .running && session.phase == .pomodoro
        guard shouldPlay, let url = Self.url(for: settings.backgroundSound) else {
            backgroundPlayer?.setVolume(0, fadeDuration: 0.5)
            let player = backgroundPlayer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { player?.stop() }
            backgroundPlayer = nil
            backgroundID = nil
            return
        }
        if backgroundID != settings.backgroundSound || backgroundPlayer == nil {
            backgroundPlayer?.stop()
            backgroundPlayer = try? AVAudioPlayer(contentsOf: url)
            backgroundPlayer?.numberOfLoops = -1
            backgroundPlayer?.volume = 0
            backgroundPlayer?.play()
            backgroundID = settings.backgroundSound
        }
        backgroundPlayer?.setVolume(Float(settings.backgroundVolume), fadeDuration: 0.5)
    }
}
