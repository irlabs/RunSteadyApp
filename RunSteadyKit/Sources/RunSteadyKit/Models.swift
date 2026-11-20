import Foundation

public enum SegmentKind: String, Codable, Sendable, CaseIterable {
    case warmUp, run, walk, coolDown

    public var title: String {
        switch self {
        case .warmUp: "Warm-up"
        case .run: "Run"
        case .walk: "Walk"
        case .coolDown: "Cool-down"
        }
    }
}

public struct PlannedSegment: Hashable, Sendable {
    public let kind: SegmentKind
    /// 1-based round for run/walk, 0 for warm-up and cool-down.
    public let round: Int
    public let target: Int
}

/// A run-walk session: warm-up, `rounds` × (run, walk), cool-down. All durations in seconds.
public struct Schedule: Codable, Hashable, Sendable {
    public var name: String
    public var warmUp: Int
    public var run: Int
    public var walk: Int
    public var rounds: Int
    public var coolDown: Int

    public init(name: String, warmUp: Int, run: Int, walk: Int, rounds: Int, coolDown: Int) {
        self.name = name
        self.warmUp = warmUp
        self.run = run
        self.walk = walk
        self.rounds = rounds
        self.coolDown = coolDown
    }

    public var plannedSegments: [PlannedSegment] {
        var result = [PlannedSegment(kind: .warmUp, round: 0, target: warmUp)]
        for round in 1...max(1, rounds) {
            result.append(PlannedSegment(kind: .run, round: round, target: run))
            if walk > 0 { result.append(PlannedSegment(kind: .walk, round: round, target: walk)) }
        }
        result.append(PlannedSegment(kind: .coolDown, round: 0, target: coolDown))
        return result.filter { $0.target > 0 }
    }

    public var totalSeconds: Int { plannedSegments.reduce(0) { $0 + $1.target } }
    public var totalRunSeconds: Int { run * rounds }

    /// e.g. "5 × 3 min run / 2 min walk"
    public var summary: String {
        if walk == 0 {
            return rounds == 1 ? "\(Format.minutes(run)) continuous run" : "\(rounds) × \(Format.minutes(run)) run"
        }
        return "\(rounds) × \(Format.minutes(run)) run / \(Format.minutes(walk)) walk"
    }
}

public struct SegmentRecord: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var kind: SegmentKind
    public var round: Int
    public var target: Int
    public var actual: Int

    public init(kind: SegmentKind, round: Int, target: Int, actual: Int) {
        self.kind = kind
        self.round = round
        self.target = target
        self.actual = actual
    }

    public var overrun: Int { max(0, actual - target) }

    public static func == (a: Self, b: Self) -> Bool {
        a.kind == b.kind && a.round == b.round && a.target == b.target && a.actual == b.actual
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind); hasher.combine(round); hasher.combine(target); hasher.combine(actual)
    }
}

public enum Feeling: String, Codable, Sendable, CaseIterable {
    case great, okay, tough
    public var title: String {
        switch self {
        case .great: "Great"
        case .okay: "Okay"
        case .tough: "Tough"
        }
    }
}

public enum PainLevel: String, Codable, Sendable, CaseIterable {
    case none, mild, painful
    public var title: String {
        switch self {
        case .none: "No issues"
        case .mild: "A little sore"
        case .painful: "Painful"
        }
    }
}

/// Why a run differed from the schedule, answered with a tap in the check-in.
public enum DeviationReason: String, Codable, Sendable, CaseIterable {
    case traffic, terrain, withSomeone, feltGood
    case neededRest, discomfort

    public enum Category: Sendable { case incidental, physical }

    /// Incidental reasons never count toward rules; physical ones do.
    public var category: Category {
        switch self {
        case .traffic, .terrain, .withSomeone, .feltGood: .incidental
        case .neededRest, .discomfort: .physical
        }
    }

    public var isPhysical: Bool { category == .physical }

    public var title: String {
        switch self {
        case .traffic: "Traffic"
        case .terrain: "Hill or terrain"
        case .withSomeone: "Ran with someone"
        case .feltGood: "Felt good"
        case .neededRest: "Needed the rest"
        case .discomfort: "Discomfort"
        }
    }
}

public struct CheckIn: Codable, Hashable, Sendable {
    public var feeling: Feeling
    public var comfortable: Bool
    public var knee: PainLevel
    public var note: String?
    public var date: Date
    /// Reasons per `Deviation.id`. Optional so check-ins stored before this field still decode.
    public var reasons: [Deviation.ID: DeviationReason]?

    public init(feeling: Feeling, comfortable: Bool, knee: PainLevel, note: String? = nil, date: Date = .now) {
        self.feeling = feeling
        self.comfortable = comfortable
        self.knee = knee
        self.note = note
        self.date = date
    }
}

/// A finished session as recorded on the watch.
public struct SessionRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var schedule: Schedule
    /// Position in the automatic plan; nil when the session used a manual schedule.
    public var stageIndex: Int?
    public var sessionInStage: Int?
    public var segments: [SegmentRecord]
    public var distanceMeters: Double
    public var averageHeartRate: Double?
    /// A synthetic record from the watch's diagnostics screen. The phone never stores it.
    /// Optional so records from older watch builds still decode.
    public var isTest: Bool?

    public init(
        id: UUID = UUID(), startedAt: Date, schedule: Schedule, stageIndex: Int?, sessionInStage: Int?,
        segments: [SegmentRecord], distanceMeters: Double, averageHeartRate: Double?, isTest: Bool? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.schedule = schedule
        self.stageIndex = stageIndex
        self.sessionInStage = sessionInStage
        self.segments = segments
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.isTest = isTest
    }

    public var isTestRun: Bool { isTest == true }

    public var duration: Int { segments.reduce(0) { $0 + $1.actual } }
    public var roundsDone: Int { segments.filter { $0.kind == .run }.count }
    public var extraRounds: Int { max(0, roundsDone - schedule.rounds) }
    public var completedPlannedRounds: Bool { roundsDone >= schedule.rounds }
    public var totalOverrun: Int { segments.reduce(0) { $0 + $1.overrun } }
    public var runSeconds: Int { segments.filter { $0.kind == .run }.reduce(0) { $0 + $1.actual } }
    public var paceSecondsPerKm: Double? {
        distanceMeters > 10 ? Double(duration) / (distanceMeters / 1000) : nil
    }
}

public enum Format {
    /// 65 -> "1:05", 3725 -> "1:02:05"
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        return h > 0
            ? "\(h):" + String(format: "%02d:%02d", m, sec)
            : "\(m):" + String(format: "%02d", sec)
    }

    /// Pace in min/km, e.g. "7:42".
    public static func pace(secondsPerKm: Double?) -> String {
        guard let p = secondsPerKm, p.isFinite, p > 0, p < 3600 else { return "–:––" }
        return clock(Int(p.rounded()))
    }

    public static func km(meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }

    /// 120 -> "2 min", 90 -> "1:30 min", 45 -> "45 s"
    public static func minutes(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(clock(seconds)) min"
    }
}
