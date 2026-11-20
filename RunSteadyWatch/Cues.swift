import AVFoundation
import RunSteadyKit
import WatchKit

/// Haptic, chime and spoken cues. Other audio (the user's music or podcast) is ducked
/// while a cue is pending and restored once the user taps next or the announcement ends.
@MainActor
final class Cues: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private lazy var chime = Self.makeChime()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func targetReached() {
        WKInterfaceDevice.current().play(.notification)
        duck()
        player = try? AVAudioPlayer(data: chime)
        player?.play()
    }

    /// The user tapped next: let their audio come back up.
    func acknowledged() {
        guard !synthesizer.isSpeaking else { return }
        unduck()
    }

    func announce(kilometre: Int, paceSecondsPerKm: Double?) {
        duck()
        var text = "\(kilometre) kilometre\(kilometre == 1 ? "" : "s")."
        if let pace = paceSecondsPerKm, pace.isFinite, pace > 0 {
            let total = Int(pace.rounded())
            text += " Pace \(total / 60) minutes \(total % 60) per kilometre."
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
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
        Task { @MainActor in self.unduck() }
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
