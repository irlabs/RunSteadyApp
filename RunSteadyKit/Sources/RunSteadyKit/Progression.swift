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
    /// Notable deviations from the schedule, as found by `RunAnalysis`.
    public var deviations: Set<Deviation.Kind>

    public init(date: Date, stageIndex: Int?, completedPlannedRounds: Bool, checkIn: CheckIn?,
                deviations: Set<Deviation.Kind> = []) {
        self.date = date
        self.stageIndex = stageIndex
        self.completedPlannedRounds = completedPlannedRounds
        self.checkIn = checkIn
        self.deviations = deviations
    }

    public init(_ record: SessionRecord, checkIn: CheckIn?) {
        self.init(date: record.startedAt, stageIndex: record.stageIndex,
                  completedPlannedRounds: record.completedPlannedRounds, checkIn: checkIn,
                  deviations: Set(RunAnalysis.deviations(in: record).map(\.kind)))
    }

    /// The tapped reason for a deviation, or nil when it wasn't answered.
    public func reason(for kind: Deviation.Kind) -> DeviationReason? {
        checkIn?.reasons?[kind.rawValue]
    }
}

public enum Decision: String, Codable, Sendable {
    case start, proceed, advance, repeatSession, stepBack, repeatAfterGap, stepBackAfterGap, maintain
    /// Walk breaks keep running long: offered, never applied automatically.
    case stepBackStructural
    /// Runs extended because they felt good: step up after two sessions instead of three. Offered only.
    case advanceEarly

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
        case .stepBackStructural: "Settle in"
        case .advanceEarly: "Ready early"
        }
    }
}

public struct Suggestion: Hashable, Sendable {
    public var stageIndex: Int
    public var sessionInStage: Int
    public var decision: Decision
    public var reason: String
    /// What "Keep mine" / "Stay steady" applies instead: the normal plan. Only set for offers with a
    /// fallback (`.stepBackStructural`, `.advanceEarly`).
    public var alternative: ActivePlan? = nil
    public var schedule: Schedule { ProgressionPlan.fiveK[stageIndex].schedule }
    public var stage: Stage { ProgressionPlan.fiveK[stageIndex] }

    /// Where the runner stands. An early step-up is only an offer (staying steady is the default),
    /// so it doesn't move them to the next week until they try it.
    public var position: Suggestion {
        guard decision == .advanceEarly, let stay = alternative, let stage = stay.stageIndex else { return self }
        return Suggestion(stageIndex: stage, sessionInStage: stay.sessionInStage ?? 1, decision: .proceed, reason: reason)
    }
}

/// Tunable thresholds for the rule layer.
public struct ProgressionPolicy: Sendable {
    /// A gap of at least this many days repeats the last session.
    public var repeatAfterDays = 6
    /// A gap of at least this many days steps back one stage.
    public var stepBackAfterDays = 12
    /// A gap of at least this many days steps back two stages.
    public var stepBackTwoAfterDays = 24
    /// Structural walking: a walk extended in `structuralCount` of the last `structuralWindow` planned sessions.
    public var structuralWindow = 5
    public var structuralCount = 3
    /// Early step-up: runs extended with "Felt good" in `earlyCount` of the last `earlyWindow` planned sessions.
    public var earlyWindow = 3
    public var earlyCount = 2
    /// No early step-up within this many days of a step-back or of a hard run right after an early step-up.
    public var earlyCooldownDays = 14

    public init() {}
    public static let standard = ProgressionPolicy()
}

/// Deterministic hold / repeat / step-back logic. The language model never decides any of this.
public enum ProgressionRules {
    /// - Parameters:
    ///   - structuralDeclinedAt: when the runner last declined a structural step-back;
    ///     only later sessions count toward a new pattern.
    ///   - hasOpenInjury: an open injury note blocks an early step-up. It can only make the plan more careful.
    public static func suggestion(
        history: [SessionOutcome], now: Date, policy: ProgressionPolicy = .standard,
        structuralDeclinedAt: Date? = nil, hasOpenInjury: Bool = false
    ) -> Suggestion {
        let plan = ProgressionPlan.fiveK
        let lastStage = plan.count - 1
        let sessions = history.sorted { $0.date < $1.date }

        // Manual sessions never start the plan; the gap clock counts from any session.
        guard sessions.contains(where: { $0.stageIndex != nil }), let last = sessions.last else {
            return Suggestion(stageIndex: 0, sessionInStage: 1, decision: .start,
                              reason: "Start easy: short runs with generous walk breaks.")
        }

        // Fold the history into (stage, sessions banked at that stage).
        // Manual sessions only count for pain; they never bank progress or move the week.
        var stage = 0
        var banked = 0
        var decision = Decision.start
        var reason = ""
        // Planned sessions since the last step-back, for the structural walking rule.
        var sinceStepBack: [SessionOutcome] = []
        // For the early step-up cooldowns and limits.
        var lastStepBack: Date?
        var lastHardAfterEarly: Date?
        var weeksLeftEarly: Set<Int> = []
        for outcome in sessions {
            var isFirstAfterEarly = false
            if let s = outcome.stageIndex, s != stage {
                // A lower week than the fold reached means a step-back was applied (gap or accepted offer).
                if s < stage { sinceStepBack = []; lastStepBack = outcome.date }
                // A higher one means an accepted early step-up: the fold advances on its own after three.
                if s > stage { weeksLeftEarly.insert(stage); isFirstAfterEarly = true }
                stage = min(max(0, s), lastStage)
                banked = 0
            }
            if outcome.stageIndex != nil { sinceStepBack.append(outcome) }
            let isManual = outcome.stageIndex == nil
            let check = outcome.checkIn
            if isFirstAfterEarly, let check, check.feeling == .tough || !check.comfortable || check.knee != .none {
                lastHardAfterEarly = outcome.date
            }
            if check?.knee == .painful {
                stage = max(0, stage - 1)
                banked = 0
                sinceStepBack = []
                lastStepBack = outcome.date
                decision = .stepBack
                reason = "You reported pain, so the next session is an easier one. Pain is a signal to back off, not push through."
            } else if check?.knee == .mild {
                decision = .repeatSession
                reason = "A little soreness: repeat this session until it feels fine before adding more."
            } else if isManual {
                continue
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

        // Gap handling, measured from the last session of any kind.
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

        // Walk breaks that keep running long: offer the week below the one actually run,
        // unless pain or a gap already steps back. Declining falls back to the normal plan.
        if let declined = structuralDeclinedAt { sinceStepBack.removeAll { $0.date <= declined } }
        let ranWeek = min(stage, sessions.last(where: { $0.stageIndex != nil })?.stageIndex ?? 0)
        if ranWeek > 0, decision != .stepBack, decision != .stepBackAfterGap,
           let (hits, window) = StructuralWalking.pattern(sinceStepBack, policy: policy) {
            let normal = Suggestion(stageIndex: stage, sessionInStage: banked + 1, decision: decision, reason: reason)
            let runs = hits == window ? "in your last \(hits) runs" : "in \(hits) of your last \(window) runs"
            var offer = Suggestion(
                stageIndex: ranWeek - 1, sessionInStage: 1, decision: .stepBackStructural,
                reason: "Your walk breaks ran long \(runs). A week back lets the running catch up. "
                    + "Prefer to carry on with week \(stage + 1)? Tap Keep mine.")
            offer.alternative = ActivePlan(normal)
            return offer
        }

        // Two comfortable runs that went long because they felt good: offer the next week now.
        // Checked after the gap handling, so a gap undoes it just like a normal step-up.
        let planned = sessions.filter { $0.stageIndex != nil }
        let cooldownStart = now.addingTimeInterval(-Double(policy.earlyCooldownDays) * 86_400)
        if decision == .proceed, banked == ProgressionPlan.sessionsPerStage - 1, stage + 1 < lastStage,
           !hasOpenInjury, !weeksLeftEarly.contains(stage),
           (lastStepBack ?? .distantPast) < cooldownStart, (lastHardAfterEarly ?? .distantPast) < cooldownStart,
           EarlyStepUp.isReady(planned.suffix(policy.earlyWindow), policy: policy) {
            var offer = Suggestion(
                stageIndex: stage + 1, sessionInStage: 1, decision: .advanceEarly,
                reason: "You kept running because it felt good, and nothing hurt. You could start week \(stage + 2) now, "
                    + "or stay steady and finish week \(stage + 1) first.")
            offer.alternative = ActivePlan(Suggestion(stageIndex: stage, sessionInStage: banked + 1,
                                                      decision: decision, reason: reason))
            return offer
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
