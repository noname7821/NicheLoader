import Foundation
import AVFoundation

/// Keeps the app alive in the background while iOS installs an app,
/// by playing silent audio on loop. Same trick Ksign uses for its
/// background downloads and installs.
final class BackgroundAudioService {
    static let shared = BackgroundAudioService()

    private var player: AVAudioPlayer?

    var isPlaying: Bool { player?.isPlaying == true }

    func start() {
        if isPlaying { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let url = try silenceURL()
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.play()
            self.player = player
        } catch {
            print("Background audio failed: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func silenceURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // 1 second of silence: 8000 Hz, 8-bit mono.
        let sampleRate: UInt32 = 8000
        let samples = [UInt8](repeating: 0x80, count: Int(sampleRate))
        var wav = Data()
        func append32(_ value: UInt32) {
            wav.append(UInt8(value & 0xFF))
            wav.append(UInt8((value >> 8) & 0xFF))
            wav.append(UInt8((value >> 16) & 0xFF))
            wav.append(UInt8((value >> 24) & 0xFF))
        }
        func append16(_ value: UInt16) {
            wav.append(UInt8(value & 0xFF))
            wav.append(UInt8((value >> 8) & 0xFF))
        }
        wav.append(Data("RIFF".utf8)); append32(36 + UInt32(samples.count))
        wav.append(Data("WAVE".utf8)); wav.append(Data("fmt ".utf8))
        append32(16); append16(1); append16(1); append32(sampleRate); append32(sampleRate); append16(1); append16(8)
        wav.append(Data("data".utf8)); append32(UInt32(samples.count))
        wav.append(contentsOf: samples)
        try wav.write(to: url)
        return url
    }
}
