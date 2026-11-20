import AVFoundation
import SwiftUI

/// Hidden device-check screen (long-press the tortoise on the start screen). Phase 0 spike, kept for later checks.
struct WatchDiagnosticsView: View {
    @ObservedObject private var store = DiagStore.shared
    private let spike = WatchSpike.shared

    var body: some View {
        List {
            Section("Permissions (F1)") {
                Button("Check status") { spike.checkPermissions() }
                    .accessibilityIdentifier("checkPermissions")
                Button("Read birth date") { spike.readDateOfBirth() }
                Button("Request here") { Task { await spike.requestHere() } }
            }
            Section("Voice (F5)") {
                NavigationLink("Voice lab") { VoiceLabView() }
                    .accessibilityIdentifier("voiceLab")
            }
            Section("Sync (F10)") {
                Button("Fake run") { Task { await spike.fakeRun() } }
                    .accessibilityIdentifier("fakeRun")
                Button("Delete test workouts") { spike.deleteAllTestWorkouts() }
            }
            Section("Log") {
                NavigationLink("Log (\(store.entries.count))") { WatchLogView() }
                    .accessibilityIdentifier("logLink")
                Button("Send log to phone") {
                    if let url = store.snapshot() { Connectivity.shared.sendLog(url) }
                }
                .accessibilityIdentifier("sendLog")
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear { Diag.log("WC", "Now: \(Connectivity.describe(.default))") }
    }
}

private struct WatchLogView: View {
    @ObservedObject private var store = DiagStore.shared

    var body: some View {
        List {
            DiagLogList(entries: store.entries, limit: 150)
            Button("Clear log", role: .destructive) { store.clear() }
        }
        .navigationTitle("Log")
    }
}

/// F5: hear every English voice on this watch with a real cue, at the rates and volumes we are considering.
struct VoiceLabView: View {
    static let sample = "Walk. 2 kilometres. 8 minutes 15 per kilometre."

    @State private var cues = Cues()
    @State private var rate: Float = 0.5
    @State private var volume: Float = 1.0
    private let voices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .sorted { ($0.language, $0.name) < ($1.language, $1.name) }

    var body: some View {
        List {
            Section {
                Button("Rate \(rate, specifier: "%.2f")") { rate = rate == 0.5 ? 0.45 : 0.5 }
                    .accessibilityIdentifier("rateToggle")
                Button("Volume \(volume, specifier: "%.1f")") { volume = volume == 1.0 ? 0.7 : 1.0 }
                    .accessibilityIdentifier("volumeToggle")
                Button("Default en-GB") { speak(nil) }
            } footer: {
                Text("\(voices.count) English voices. Tap one to hear a cue.")
            }
            ForEach(voices, id: \.identifier) { voice in
                Button { speak(voice) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(voice.name).font(.system(size: 15, weight: .semibold))
                        Text("\(voice.language) · \(voice.gender.label) · \(voice.quality.label)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("voice-\(voice.identifier)")
            }
        }
        .navigationTitle("Voice lab")
        .onAppear {
            Diag.log("Voice", "\(voices.count) English voices (of \(AVSpeechSynthesisVoice.speechVoices().count))")
            for v in voices {
                Diag.log("Voice", "\(v.language) \(v.name) · \(v.gender.label) · \(v.quality.label) · \(v.identifier)")
            }
        }
    }

    private func speak(_ voice: AVSpeechSynthesisVoice?) {
        Diag.log("Voice", "Speak \(voice?.identifier ?? "default en-GB") rate \(rate) volume \(volume)")
        cues.preview(Self.sample, voice: voice, rate: rate, volume: volume)
    }
}

extension AVSpeechSynthesisVoiceGender {
    var label: String {
        switch self {
        case .female: "female"
        case .male: "male"
        case .unspecified: "unspecified"
        @unknown default: "?"
        }
    }
}

extension AVSpeechSynthesisVoiceQuality {
    var label: String {
        switch self {
        case .default: "default"
        case .enhanced: "enhanced"
        case .premium: "premium"
        @unknown default: "?"
        }
    }
}
