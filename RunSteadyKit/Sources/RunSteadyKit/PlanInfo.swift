import Foundation

/// What the phone sends along with the active plan (next to it, under its own key, so older
/// watches that only read the plan keep working).
public struct PlanInfo: Codable, Hashable, Sendable {
    /// When the runner (or the phone, silently) last set or kept this plan. The watch starts its
    /// gap clock here if it is later than the last run, so a break already handled on the phone
    /// is not handled twice.
    public var decidedAt: Date
    /// Why the phone chose this plan, when known. Decides whether a 6-day gap repeats a session.
    public var decision: Decision?
    /// Heart rate zones from the phone's date of birth. The watch falls back to its own.
    public var zones: HeartRateZones?

    public init(decidedAt: Date, decision: Decision?, zones: HeartRateZones?) {
        self.decidedAt = decidedAt
        self.decision = decision
        self.zones = zones
    }
}
