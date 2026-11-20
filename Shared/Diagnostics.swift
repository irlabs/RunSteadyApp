import Foundation
import os
import SwiftUI

/// One line of the diagnostics log. Stored as JSON lines in the app container.
struct DiagEntry: Codable, Hashable, Identifiable {
    /// Time, device ("phone"/"watch"), category, message.
    let t: Date
    let d: String
    let c: String
    let m: String
    var id: String { "\(t.timeIntervalSince1970)-\(d)-\(c)-\(m.hashValue)" }
}

/// Device diagnostics for the Phase 0 spike, kept in the app (hidden) for later device checks.
/// Everything goes to `os.Logger` (subsystem "RunSteady", for Console.app when tethered) and to a
/// capped JSON-lines file, so a test can be read back on the device or shared afterwards.
enum Diag {
    #if os(iOS)
    static let device = "phone"
    #else
    static let device = "watch"
    #endif

    private static let phaseLock = NSLock()
    nonisolated(unsafe) private static var _phase = "launching"
    /// Last known app state ("foreground", "background", …), readable from any thread.
    static var phase: String {
        get { phaseLock.withLock { _phase } }
        set { phaseLock.withLock { _phase = newValue } }
    }

    static func log(_ category: String, _ message: String) {
        Logger(subsystem: "RunSteady", category: category).notice("\(message, privacy: .public)")
        DiagStore.shared.append(DiagEntry(t: .now, d: device, c: category, m: message))
    }

    /// "1.4 s" for a delay since `date`, or "?" when the sender gave no time.
    static func delay(since date: Date?, now: Date = .now) -> String {
        guard let date else { return "?" }
        return String(format: "%.1f s", now.timeIntervalSince(date))
    }
}

/// The log file (and, on the phone, the last log received from the watch).
final class DiagStore: ObservableObject, @unchecked Sendable {
    static let shared = DiagStore()
    static let cap = 2_000

    @Published private(set) var entries: [DiagEntry] = []
    /// Phone only: the log the watch sent last.
    @Published private(set) var watchEntries: [DiagEntry] = []

    let fileURL: URL
    let watchFileURL: URL
    private let queue = DispatchQueue(label: "RunSteady.diagnostics")
    private var buffer: [DiagEntry] = []

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(DiagStore.formatter.string(from: date))
        }
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            return DiagStore.formatter.date(from: s) ?? .distantPast
        }
        return d
    }()
    nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        fileURL = dir.appendingPathComponent("diagnostics-\(Diag.device).jsonl")
        watchFileURL = dir.appendingPathComponent("diagnostics-watch-received.jsonl")
        buffer = Self.read(fileURL)
        let initial = buffer
        let watch = Self.read(watchFileURL)
        entries = initial
        watchEntries = watch
    }

    func append(_ entry: DiagEntry) {
        queue.async { [self] in
            buffer.append(entry)
            if buffer.count > Self.cap + 200 {
                buffer.removeFirst(buffer.count - Self.cap)
                Self.write(buffer, to: fileURL)
            } else if let line = Self.line(entry) {
                Self.appendLine(line, to: fileURL)
            }
            publish(buffer)
        }
    }

    func clear() {
        queue.async { [self] in
            buffer = []
            try? FileManager.default.removeItem(at: fileURL)
            publish(buffer)
        }
    }

    /// A stable copy of the log to hand to `transferFile` or a share sheet (the live file keeps growing).
    func snapshot() -> URL? {
        queue.sync {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("RunSteady-\(Diag.device)-log-\(Int(Date().timeIntervalSince1970)).jsonl")
            Self.write(buffer, to: url)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// Phone: keep the log file the watch sent. Must run before the delegate callback returns.
    func importWatchLog(from url: URL) -> Int {
        let received = Self.read(url)
        Self.write(received, to: watchFileURL)
        DispatchQueue.main.async { self.watchEntries = received }
        return received.count
    }

    private func publish(_ snapshot: [DiagEntry]) {
        DispatchQueue.main.async { self.entries = snapshot }
    }

    private static func line(_ entry: DiagEntry) -> Data? {
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(0x0A)
        return data
    }

    private static func appendLine(_ line: Data, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    private static func write(_ entries: [DiagEntry], to url: URL) {
        var data = Data()
        for entry in entries { if let line = line(entry) { data.append(line) } }
        try? data.write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) -> [DiagEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(DiagEntry.self, from: Data($0.utf8)) }
    }
}

/// The log as a list, newest first.
struct DiagLogList: View {
    let entries: [DiagEntry]
    var limit = 300

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        if entries.isEmpty {
            Text("No entries yet").foregroundStyle(.secondary)
        }
        ForEach(entries.suffix(limit).reversed()) { entry in
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Self.time.string(from: entry.t)) · \(entry.c)")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).monospacedDigit()
                Text(entry.m).font(.system(size: 12))
            }
            .accessibilityIdentifier("logEntry")
        }
    }
}
