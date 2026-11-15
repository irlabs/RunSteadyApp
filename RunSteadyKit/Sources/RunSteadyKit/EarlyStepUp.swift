import Foundation

/// Spots runs that went long because they felt good, as a sign the runner is ready to step up early.
public enum EarlyStepUp {
    static func feltGood(_ outcome: SessionOutcome) -> Bool {
        outcome.deviations.contains(.runExtended) && outcome.reason(for: .runExtended) == .feltGood
    }

    /// Any sign the runner should not be pushed: soreness, an uncomfortable pace or a "Tough" rating.
    static func hadTrouble(_ outcome: SessionOutcome) -> Bool {
        guard let check = outcome.checkIn else { return false }
        return check.knee != .none || !check.comfortable || check.feeling == .tough
    }

    /// - Parameter window: the last planned sessions (`policy.earlyWindow`), oldest first.
    public static func isReady<C: Collection<SessionOutcome>>(_ window: C, policy: ProgressionPolicy) -> Bool {
        window.filter(feltGood).count >= policy.earlyCount && !window.contains(where: hadTrouble)
    }
}
