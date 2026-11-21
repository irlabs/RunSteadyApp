import Foundation

/// The plan the watch runs after a break, worked out on the watch itself (F15).
public struct GapAdjustment: Hashable, Sendable {
    public var plan: ActivePlan
    public var gapDays: Int
    public var decision: Decision
    public var reason: String
}

/// Repeat or step back after days without a run. Shared by the phone (`ProgressionRules`) and the
/// watch, so both reach the same plan from the same inputs.
public enum GapRule {
    /// Whole days from `start` to `now`; 0 without a start.
    public static func days(since start: Date?, now: Date) -> Int {
        guard let start else { return 0 }
        return max(0, Int(now.timeIntervalSince(start) / 86_400))
    }

    /// Where the watch starts its gap clock: the last run, or the moment the runner last decided
    /// about the plan on the phone (accepting or declining a step-back), whichever is later.
    /// So a step-back already taken on the phone is not taken twice.
    public static func clockStart(lastSession: Date?, planDecidedAt: Date?) -> Date? {
        [lastSession, planDecidedAt].compactMap { $0 }.max()
    }

    /// "6 days", "2 weeks"
    public static func describe(days: Int) -> String {
        days < 14 ? "\(days) day\(days == 1 ? "" : "s")" : "\(days / 7) weeks"
    }

    /// The fold state after `gapDays` without a run, or nil when the gap changes nothing.
    /// `banked` is the number of comfortable sessions already done at `stage`.
    static func apply(stage: Int, banked: Int, decision: Decision, gapDays: Int,
                      policy: ProgressionPolicy) -> (stage: Int, banked: Int, decision: Decision, reason: String)? {
        if gapDays >= policy.stepBackTwoAfterDays {
            return (max(0, stage - 2), 0, .stepBackAfterGap,
                    "It's been \(gapDays) days. Stepping back two weeks rebuilds safely.")
        }
        if gapDays >= policy.stepBackAfterDays {
            return (max(0, stage - 1), 0, .stepBackAfterGap,
                    "It's been \(gapDays) days. Stepping back a week keeps your knees happy.")
        }
        if gapDays >= policy.repeatAfterDays, [.proceed, .advance, .advanceFromManual].contains(decision) {
            var (stage, banked) = (stage, banked)
            if decision != .proceed { stage = max(0, stage - 1); banked = ProgressionPlan.sessionsPerStage }
            return (stage, max(0, banked - 1), .repeatAfterGap,
                    "It's been \(gapDays) days, so repeat the last session before moving on.")
        }
        return nil
    }

    /// The watch's plan after a break. nil when nothing changes, and always nil for a manual schedule.
    /// - Parameters:
    ///   - decision: why the phone chose `plan`; when missing it is inferred from the position
    ///     (session 1 of a later week = a step-up, later sessions = on track).
    ///   - since: start of the gap clock (`clockStart`).
    public static func adjust(_ plan: ActivePlan, decision: Decision?, since: Date?, now: Date,
                              policy: ProgressionPolicy = .standard) -> GapAdjustment? {
        guard let stage = plan.stageIndex, let session = plan.sessionInStage else { return nil }
        let gap = days(since: since, now: now)
        let inferred = decision ?? (session > 1 ? .proceed : stage > 0 ? .advance : .start)
        guard let result = apply(stage: stage, banked: session - 1, decision: inferred, gapDays: gap, policy: policy)
        else { return nil }
        let adjusted = ActivePlan(Suggestion(stageIndex: result.stage, sessionInStage: result.banked + 1,
                                             decision: result.decision, reason: result.reason))
        guard adjusted != plan else { return nil }
        return GapAdjustment(plan: adjusted, gapDays: gap, decision: result.decision, reason: result.reason)
    }
}
