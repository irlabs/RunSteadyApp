import AVFoundation
import RunSteadyKit
import WatchKit

/// Haptic, chime and spoken cues. Other audio (the user's music or podcast) is ducked
/// while a cue is pending and restored once the user taps next or the announcement ends.
@MainActor
final class Cues: NSObject, AVSpeechSynthesizerDelegate {
    /// F5, chosen in the voice lab on the Series 5: Daniel (en-GB), a little slower, full volume.
    static let voiceIdentifier = "com.apple.voice.compact.en-GB.Daniel"
    static let rate: Float = 0.45
    static let volume: Float = 1.0

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private lazy var chime = Self.makeChime()
    /// The target was reached and next isn't tapped yet: other audio stays ducked between reminders.
    private var awaitingTap = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Daniel when this watch has him, otherwise the default British English voice.
    static var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: voiceIdentifier) ?? AVSpeechSynthesisVoice(language: "en-GB")
    }

    func targetReached() {
        awaitingTap = true
        duck()
        chimeAndTap()
    }

    /// F4: the same chime and haptic every few seconds until next is tapped.
    func reminder() {
        guard awaitingTap else { return }
        chimeAndTap()
    }

    /// The user tapped next: let their audio come back up.
    func acknowledged() {
        awaitingTap = false
        guard !synthesizer.isSpeaking else { return }
        unduck()
    }

    private func chimeAndTap() {
        WKInterfaceDevice.current().play(.notification)
        player = try? AVAudioPlayer(data: chime)
        player?.play()
    }

    func announce(kilometre: Int, paceSecondsPerKm: Double?) {
        duck()
        var text = "\(kilometre) kilometre\(kilometre == 1 ? "" : "s")."
        if let pace = paceSecondsPerKm, pace.isFinite, pace > 0 {
            let total = Int(pace.rounded())
            text += " Pace \(total / 60) minutes \(total % 60) per kilometre."
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        utterance.rate = Self.rate
        utterance.volume = Self.volume
        synthesizer.speak(utterance)
    }

    /// Voice lab (diagnostics): speak `text` the way a run cue would, through the same ducking audio session.
    func preview(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float, volume: Float) {
        synthesizer.stopSpeaking(at: .immediate)
        duck()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = rate
        utterance.volume = volume
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // A spoken kilometre during overtime must not bring the music back up before the tap.
            if !self.awaitingTap { self.unduck() }
        }
    }

    private func duck() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func unduck() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Two-note chime as an in-memory 16-bit mono WAV, so no audio asset is needed.
    private static func makeChime() -> Data {
        let sampleRate = 22_050.0
        var samples: [Int16] = []
        for (frequency, length) in [(880.0, 0.14), (1318.5, 0.26)] {
            let count = Int(sampleRate * length)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let envelope = min(1, Double(i) / 200) * pow(1 - Double(i) / Double(count), 1.5)
                samples.append(Int16(sin(2 * .pi * frequency * t) * envelope * 0.6 * Double(Int16.max)))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.forEach { append($0) }
        return data
    }
}
