import AVFoundation

// Mirrors MusicManager.kt: one shared looping player across every screen.
// Looks for a bundled "background_music" audio file (any common extension)
// and silently no-ops if it isn't there yet - same "drop the file in, no
// code change needed" contract as the Android version's R.raw lookup.
final class MusicManager {
    // Only ever created/used on the main thread (SwiftUI view code).
    nonisolated(unsafe) static let shared = MusicManager()

    private let defaultsKey = "buddyverse_music_muted"
    private var player: AVAudioPlayer?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let candidateExtensions = ["mp3", "m4a", "wav", "aac"]
        guard let url = candidateExtensions
            .compactMap({ Bundle.main.url(forResource: "background_music", withExtension: $0) })
            .first else {
            return // No track bundled yet - stay silent, nothing to do.
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.35
            player = p
            if !isMuted, !p.play() {
                // Playback failed to start even though the file decoded fine -
                // leave `player` set so a later onAppForegrounded() can retry.
            }
        } catch {
            player = nil
        }
    }

    func onAppForegrounded() {
        guard let player, !isMuted, !player.isPlaying else { return }
        player.play()
    }

    func onAppBackgrounded() {
        player?.pause()
    }

    func toggleMute() {
        let muted = !isMuted
        UserDefaults.standard.set(muted, forKey: defaultsKey)
        if muted {
            player?.pause()
        } else {
            player?.play()
        }
    }

    var isMuted: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
