import Foundation

/// Holds the latest value until someone listens (G8). WatchConnectivity can deliver the phone's plan
/// while the watch app is still launching, before its model has set a handler; without this the plan
/// was dropped and the watch kept running the previous one.
@MainActor
public final class Inbox<Value> {
    private var waiting: Value?

    /// Setting a handler hands over the value that is waiting, if any.
    public var handler: ((Value) -> Void)? {
        didSet {
            guard let handler, let value = waiting else { return }
            waiting = nil
            handler(value)
        }
    }

    nonisolated public init() {}

    /// Straight to the handler, or kept (latest wins) until there is one.
    public func receive(_ value: Value) {
        if let handler { handler(value) } else { waiting = value }
    }
}

/// The plan the watch holds, as it reports it back to the phone (G9).
public struct PlanReceipt: Codable, Hashable, Sendable {
    public var plan: ActivePlan
    /// `PlanInfo.decidedAt` of that plan; nil when the phone sent none.
    public var decidedAt: Date?
    /// When the watch reported this (watch clock).
    public var reportedAt: Date

    public init(plan: ActivePlan, decidedAt: Date?, reportedAt: Date) {
        self.plan = plan
        self.decidedAt = decidedAt
        self.reportedAt = reportedAt
    }

    /// Same session and same decision. Dates within a second, as they travel through storage and JSON.
    public func matches(plan: ActivePlan, decidedAt: Date) -> Bool {
        guard plan == self.plan, let mine = self.decidedAt else { return false }
        return abs(mine.timeIntervalSince(decidedAt)) < 1
    }
}

/// What Today says about the next session on the watch (G9).
public enum WatchPlanStatus: Equatable, Sendable {
    /// The watch hasn't reported a plan (an older watch build, or never opened): claim nothing.
    case unknown
    /// The watch holds this plan.
    case onWatch
    /// Sent, and the watch hasn't reported since.
    case sending
    /// The watch reported after the send, still with another plan.
    case older(ActivePlan)

    /// - Parameters:
    ///   - decidedAt: when the phone set or kept `plan`.
    ///   - sentAt: when this phone app last sent it; nil when it hasn't since launch.
    public static func evaluate(plan: ActivePlan, decidedAt: Date, watch: PlanReceipt?, sentAt: Date?) -> WatchPlanStatus {
        guard let watch else { return .unknown }
        if watch.matches(plan: plan, decidedAt: decidedAt) { return .onWatch }
        let since = max(sentAt ?? decidedAt, decidedAt)
        return watch.reportedAt > since ? .older(watch.plan) : .sending
    }
}
