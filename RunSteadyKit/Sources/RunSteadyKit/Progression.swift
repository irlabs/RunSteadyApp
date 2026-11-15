import Foundation

public struct Stage: Hashable, Sendable {
    public let week: Int
    public let schedule: Schedule
    public let focus: String
}

/// Default 8-week run-walk build-up to a continuous 30 minutes (≈ 5K at an easy pace).
public enum ProgressionPlan {
    public static let sessionsPerStage = 3

    public static let fiveK: [Stage] = [
        stage(1, run: 60, walk: 120, rounds: 8, "Find an easy rhythm"),
        stage(2, run: 120, walk: 120, rounds: 6, "Equal parts run and walk"),
        stage(3, run: 180, walk: 120, rounds: 5, "Running starts to lead"),
        stage(4, run: 300, walk: 120, rounds: 4, "Five-minute runs"),
        stage(5, run: 480, walk: 120, rounds: 3, "Longer steady blocks"),
        stage(6, run: 720, walk: 60, rounds: 2, "Short walk breaks only"),
        stage(7, run: 900, walk: 60, rounds: 2, "Two long runs"),
        stage(8, run: 1800, walk: 0, rounds: 1, "30 minutes non-stop"),
    ]

    private static func stage(_ week: Int, run: Int, walk: Int, rounds: Int, _ focus: String) -> Stage {
        Stage(week: week,
              schedule: Schedule(name: "Week \(week)", warmUp: 300, run: run, walk: walk, rounds: rounds, coolDown: 300),
              focus: focus)
    }
}

/// What the rule layer needs to know about a finished session.
public struct SessionOutcome: Hashable, Sendable {
    public var date: Date
    public var stageIndex: Int?
    public var completedPlannedRounds: Bool
    public var checkIn: CheckIn?

    public init(date: Date, stageIndex: Int?, completedPlannedRounds: Bool, checkIn: CheckIn?) {
        self.date = date
        self.stageIndex = stageIndex
        self.completedPlannedRounds = completedPlannedRounds
        self.checkIn = checkIn
    }

    public init(_ record: SessionRecord, checkIn: CheckIn?) {
        self.init(date: record.startedAt, stageIndex: record.stageIndex,
                  completedPlannedRounds: record.completedPlannedRounds, checkIn: checkIn)
    }
}

public enum Decision: String, Codable, Sendable {
    case start, proceed, advance, repeatSession, stepBack, repeatAfterGap, stepBackAfterGap, maintain

    public var title: String {
        switch self {
        case .start: "Let's begin"
        case .proceed: "On track"
        case .advance: "Step up"
        case .repeatSession: "Repeat"
        case .stepBack: "Ease back"
        case .repeatAfterGap: "Welcome back"
        case .stepBackAfterGap: "Rebuild gently"
        case .maintain: "Hold steady"
        }
    }
}

public struct Suggestion: Hashable, Sendable {
    public var stageIndex: Int
    public var sessionInStage: Int
    public var decision: Decision
    public var reason: String
    public var schedule: Schedule { ProgressionPlan.fiveK[stageIndex].schedule }
    public var stage: Stage { ProgressionPlan.fiveK[stageIndex] }
}

/// Tunable thresholds for the rule layer.
public struct ProgressionPolicy: Sendable {
    /// A gap of at least this many days repeats the last session.
    public var repeatAfterDays = 6
    /// A gap of at least this many days steps back one stage.
    public var stepBackAfterDays = 12
    /// A gap of at least this many days steps back two stages.
    public var stepBackTwoAfterDays = 24

    public init() {}
    public static let standard = ProgressionPolicy()
}

/// Deterministic hold / repeat / step-back logic. The language model never decides any of this.
public enum ProgressionRules {
    public static func suggestion(
        history: [SessionOutcome], now: Date, policy: ProgressionPolicy = .standard
    ) -> Suggestion {
        let plan = ProgressionPlan.fiveK
        let lastStage = plan.count - 1
        let planned = history.filter { $0.stageIndex != nil }.sorted { $0.date < $1.date }

        guard let last = planned.last else {
            return Suggestion(stageIndex: 0, sessionInStage: 1, decision: .start,
                              reason: "Start easy: short runs with generous walk breaks.")
        }

        // Fold the history into (stage, sessions banked at that stage).
        var stage = 0
        var banked = 0
        var decision = Decision.start
        var reason = ""
        for outcome in planned {
            if let s = outcome.stageIndex, s != stage {
                stage = min(max(0, s), lastStage)
                banked = 0
            }
            let check = outcome.checkIn
            if check?.knee == .painful {
                stage = max(0, stage - 1)
                banked = 0
                decision = .stepBack
                reason = "You reported pain, so the next session is an easier one. Pain is a signal to back off, not push through."
            } else if check?.knee == .mild {
                decision = .repeatSession
                reason = "A little soreness: repeat this session until it feels fine before adding more."
            } else if check?.feeling == .tough || check?.comfortable == false {
                decision = .repeatSession
                reason = "That one felt hard. Repeating it lets your body catch up."
            } else if !outcome.completedPlannedRounds {
                decision = .repeatSession
                reason = "You stopped before the planned rounds, so this session comes around again."
            } else {
                banked += 1
                if banked >= ProgressionPlan.sessionsPerStage {
                    if stage < lastStage {
                        stage += 1
                        banked = 0
                        decision = .advance
                        reason = "Three comfortable sessions done. Time for a small step up."
                    } else {
                        banked = ProgressionPlan.sessionsPerStage - 1
                        decision = .maintain
                        reason = "You're running 30 minutes non-stop. Keep it steady and enjoy it."
                    }
                } else {
                    decision = .proceed
                    reason = "Comfortable session. Same intervals again to let them settle."
                }
            }
        }

        // Gap handling, measured from the last planned session.
        let gapDays = Int(now.timeIntervalSince(last.date) / 86_400)
        if gapDays >= policy.stepBackTwoAfterDays {
            stage = max(0, stage - 2)
            banked = 0
            decision = .stepBackAfterGap
            reason = "It's been \(gapDays) days. Stepping back two weeks rebuilds safely."
        } else if gapDays >= policy.stepBackAfterDays {
            stage = max(0, stage - 1)
            banked = 0
            decision = .stepBackAfterGap
            reason = "It's been \(gapDays) days. Stepping back a week keeps your knees happy."
        } else if gapDays >= policy.repeatAfterDays, decision == .proceed || decision == .advance {
            if decision == .advance { stage = max(0, stage - 1); banked = ProgressionPlan.sessionsPerStage }
            banked = max(0, banked - 1)
            decision = .repeatAfterGap
            reason = "It's been \(gapDays) days, so repeat the last session before moving on."
        }

        return Suggestion(stageIndex: stage, sessionInStage: banked + 1, decision: decision, reason: reason)
    }
}

/// The schedule the watch will run next. `stageIndex == nil` means a manual schedule,
/// which always wins over the automatic progression.
public struct ActivePlan: Codable, Hashable, Sendable {
    public var schedule: Schedule
    public var stageIndex: Int?
    public var sessionInStage: Int?

    public init(schedule: Schedule, stageIndex: Int? = nil, sessionInStage: Int? = nil) {
        self.schedule = schedule
        self.stageIndex = stageIndex
        self.sessionInStage = sessionInStage
    }

    public init(_ suggestion: Suggestion) {
        self.init(schedule: suggestion.schedule, stageIndex: suggestion.stageIndex, sessionInStage: suggestion.sessionInStage)
    }

    public var isManual: Bool { stageIndex == nil }

    public var title: String {
        guard let stageIndex, let sessionInStage else { return "My schedule" }
        return "Week \(stageIndex + 1) · Session \(sessionInStage)"
    }

    public static let initial = ActivePlan(ProgressionRules.suggestion(history: [], now: .now))
}
