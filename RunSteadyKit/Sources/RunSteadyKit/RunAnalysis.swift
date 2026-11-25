import Foundation

/// A notable way a finished run differed from its schedule. One per kind per run,
/// so `id` is stable and can key a reason on the check-in.
public struct Deviation: Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case runExtended, walkExtended, extraRounds, stoppedEarly, easierThanPlan
    }

    public var kind: Kind
    /// Affected rounds (1-based); empty for `easierThanPlan`.
    public var rounds: [Int]
    /// Extra seconds (extended, extra rounds) or missing run seconds (stopped early, easier than plan).
    public var seconds: Int

    public init(kind: Kind, rounds: [Int], seconds: Int) {
        self.kind = kind
        self.rounds = rounds
        self.seconds = seconds
    }

    public var id: String { kind.rawValue }
}

/// Computes the facts about a run. Deterministic; the coach only gets to talk about the result.
public enum RunAnalysis {
    public static let minimumSeconds = 20
    public static let minimumFraction = 0.1

    /// Differences under about 20 s or 10% of the target are noise.
    public static func isNotable(difference: Int, target: Int) -> Bool {
        difference >= max(minimumSeconds, Int((Double(target) * minimumFraction).rounded(.up)))
    }

    /// - Parameter plannedSchedule: what the automatic plan would have run; used to spot easier manual runs.
    public static func deviations(in record: SessionRecord, plannedSchedule: Schedule? = nil) -> [Deviation] {
        let schedule = record.schedule
        let planned = schedule.rounds
        // The walk after the last run is cool-down (G7), also in records from older watch builds.
        let intervals = schedule.mergingClosingWalk(record.segments).filter { $0.kind == .run || $0.kind == .walk }
        var result: [Deviation] = []

        let longRuns = intervals.filter {
            $0.kind == .run && $0.round <= planned && isNotable(difference: $0.actual - $0.target, target: $0.target)
        }
        if !longRuns.isEmpty {
            result.append(Deviation(kind: .runExtended, rounds: longRuns.map(\.round),
                                    seconds: longRuns.reduce(0) { $0 + $1.overrun }))
        }
        // Planned walks are the ones between planned runs. A walk after the last planned run that
        // another run follows belongs to the extra round.
        if let walks = walkExtended(intervals.filter { $0.kind == .walk && $0.round < planned }, schedule: schedule) {
            result.append(walks)
        }

        let extra = intervals.filter { $0.round > planned || ($0.kind == .walk && $0.round == planned) }
        let extraRuns = extra.filter { $0.kind == .run }
        // Judged on the extra running, so a stray tap on next before the cool-down is noise.
        if isNotable(difference: extraRuns.reduce(0) { $0 + $1.actual }, target: schedule.run) {
            result.append(Deviation(kind: .extraRounds, rounds: extraRuns.map(\.round),
                                    seconds: extra.reduce(0) { $0 + $1.actual }))
        }

        // Missing run time in the planned rounds: runs never started, or the last run cut short.
        // A skipped final walk doesn't count; heading into the cool-down there is normal.
        let runs = Dictionary(intervals.filter { $0.kind == .run }.map { ($0.round, $0.actual) }, uniquingKeysWith: +)
        let lastRun = runs.keys.max() ?? 0
        var shortRounds: [Int] = []
        var missing = 0
        for round in 1...max(1, planned) where round >= lastRun {
            let short = schedule.run - (runs[round] ?? 0)
            if short > 0, round > lastRun || isNotable(difference: short, target: schedule.run) {
                shortRounds.append(round)
                missing += short
            }
        }
        if isNotable(difference: missing, target: schedule.run) {
            result.append(Deviation(kind: .stoppedEarly, rounds: shortRounds, seconds: missing))
        }

        if record.stageIndex == nil, let plannedSchedule {
            let easier = plannedSchedule.totalRunSeconds - schedule.totalRunSeconds
            if isNotable(difference: easier, target: plannedSchedule.totalRunSeconds) {
                result.append(Deviation(kind: .easierThanPlan, rounds: [], seconds: easier))
            }
        }
        return result
    }

    /// Walk breaks count as extended when they ran long in enough rounds and by enough in total,
    /// or one walk ran far over, or all walks together ran well over. See TASKS.md decisions.
    static func walkExtended(_ walks: [SegmentRecord], schedule: Schedule) -> Deviation? {
        let plannedWalking = schedule.totalWalkSeconds
        guard plannedWalking > 0 else { return nil }
        let longRounds = walks.filter { isNotable(difference: $0.actual - $0.target, target: $0.target) }.map(\.round)
        let extra = walks.reduce(0) { $0 + $1.overrun }

        let roundsNeeded = min(2, (schedule.rounds + 2) / 3)
        let enoughRoundsAndTime = longRounds.count >= roundsNeeded
            && Double(extra) >= max(60, Double(plannedWalking) * 0.10)
        let oneFarOver = walks.contains { Double($0.overrun) > Double($0.target) * 0.75 }
        let allWellOver = Double(extra) > Double(plannedWalking) * 0.25

        guard enoughRoundsAndTime || oneFarOver || allWellOver else { return nil }
        return Deviation(kind: .walkExtended, rounds: longRounds, seconds: extra)
    }
}
