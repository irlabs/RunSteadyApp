import Foundation

/// Spots walk breaks that keep running long for physical reasons, as opposed to one-offs.
public enum StructuralWalking {
    /// A session counts when its walks ran long (see `RunAnalysis.walkExtended`) and the tapped
    /// reason was physical or skipped. A missing check-in counts as skipped; incidental reasons never count.
    static func counts(_ outcome: SessionOutcome) -> Bool {
        outcome.deviations.contains(.walkExtended) && (outcome.reason(for: .walkExtended)?.isPhysical ?? true)
    }

    /// The pattern, if there is one: `hits` counting sessions among the last `window` (at most
    /// `policy.structuralWindow`), with `hits >= policy.structuralCount`.
    ///
    /// - Parameter sessions: planned sessions since the last step-back or declined offer, oldest first.
    public static func pattern(_ sessions: [SessionOutcome], policy: ProgressionPolicy) -> (hits: Int, window: Int)? {
        let window = sessions.suffix(policy.structuralWindow)
        let hits = window.filter(counts).count
        return hits >= policy.structuralCount ? (hits, window.count) : nil
    }

    public static func isStructural(_ sessions: [SessionOutcome], policy: ProgressionPolicy) -> Bool {
        pattern(sessions, policy: policy) != nil
    }
}
