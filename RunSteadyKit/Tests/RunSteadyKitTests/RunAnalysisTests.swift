import Foundation
import Testing
@testable import RunSteadyKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
/// 3 × 3 min run / 2 min walk, 5 min warm-up and cool-down.
private let plan = Schedule(name: "T", warmUp: 300, run: 180, walk: 120, rounds: 3, coolDown: 300)

/// Builds a record. `runs`/`walks` are actual seconds per round; missing entries mean the segment never happened.
private func record(
    _ schedule: Schedule = plan, runs: [Int], walks: [Int], stage: Int? = 2
) -> SessionRecord {
    var segments = [SegmentRecord(kind: .warmUp, round: 0, target: schedule.warmUp, actual: schedule.warmUp)]
    for (i, run) in runs.enumerated() {
        segments.append(SegmentRecord(kind: .run, round: i + 1, target: schedule.run, actual: run))
        if i < walks.count {
            segments.append(SegmentRecord(kind: .walk, round: i + 1, target: schedule.walk, actual: walks[i]))
        }
    }
    segments.append(SegmentRecord(kind: .coolDown, round: 0, target: schedule.coolDown, actual: schedule.coolDown))
    return SessionRecord(startedAt: t0, schedule: schedule, stageIndex: stage, sessionInStage: stage == nil ? nil : 1,
                         segments: segments, distanceMeters: 3000, averageHeartRate: nil)
}

private func kinds(_ deviations: [Deviation]) -> [Deviation.Kind] { deviations.map(\.kind) }

@Suite struct RunAnalysisTests {
    @Test func noiseThresholdIsTwentySecondsOrTenPercent() {
        #expect(!RunAnalysis.isNotable(difference: 19, target: 60))
        #expect(RunAnalysis.isNotable(difference: 20, target: 60))
        #expect(!RunAnalysis.isNotable(difference: 89, target: 900))
        #expect(RunAnalysis.isNotable(difference: 90, target: 900))
        #expect(!RunAnalysis.isNotable(difference: -30, target: 60))
    }

    @Test func runAsPlannedHasNoDeviations() {
        let r = record(runs: [185, 179, 195], walks: [125, 120, 110])
        #expect(RunAnalysis.deviations(in: r).isEmpty)
    }

    @Test func walkExtendedCollectsLongRoundsAndAllExtraTime() {
        let r = record(runs: [180, 180, 180], walks: [180, 130, 170])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.walkExtended])
        #expect(d[0].rounds == [1, 3])
        #expect(d[0].seconds == 120) // includes the 10 s of round 2
    }

    // Week 2 shape: 6 × 2 min run / 2 min walk, 12 min planned walking.
    private let week2 = Schedule(name: "W2", warmUp: 300, run: 120, walk: 120, rounds: 6, coolDown: 300)

    @Test func oneModeratelyLongWalkIsNotEnough() {
        // One round only (needs 2), 50 s total (needs 72 s), 42% (needs > 75%).
        let r = record(week2, runs: Array(repeating: 120, count: 6), walks: [170, 120, 120, 120, 120, 120])
        #expect(RunAnalysis.deviations(in: r).isEmpty)
    }

    @Test func twoLongWalksNeedEnoughTotalTime() {
        let short = record(week2, runs: Array(repeating: 120, count: 6), walks: [150, 150, 120, 120, 120, 120])
        #expect(RunAnalysis.deviations(in: short).isEmpty) // 60 s < max(60, 72)
        let long = record(week2, runs: Array(repeating: 120, count: 6), walks: [160, 160, 120, 120, 120, 120])
        #expect(kinds(RunAnalysis.deviations(in: long)) == [.walkExtended]) // 80 s
    }

    @Test func singleWalkFarOverTargetCounts() {
        let r = record(week2, runs: Array(repeating: 120, count: 6), walks: [215, 120, 120, 120, 120, 120]) // +79%
        #expect(kinds(RunAnalysis.deviations(in: r)) == [.walkExtended])
        let justUnder = record(week2, runs: Array(repeating: 120, count: 6), walks: [210, 120, 120, 120, 120, 120]) // +75%
        #expect(RunAnalysis.deviations(in: justUnder).isEmpty)
    }

    @Test func manySmallOverrunsAreNotEnoughBelowAQuarter() {
        let r = record(week2, runs: Array(repeating: 120, count: 6), walks: Array(repeating: 135, count: 6)) // 90 s, 12.5%
        #expect(RunAnalysis.deviations(in: r).isEmpty)
    }

    @Test func totalOverAQuarterCountsEvenWithoutLongRounds() {
        // Week 6 shape: 2 × 12 min run / 1 min walk. 18 s over each (under the noise floor), 30% in total.
        let week6 = Schedule(name: "W6", warmUp: 300, run: 720, walk: 60, rounds: 2, coolDown: 300)
        let r = record(week6, runs: [720, 720], walks: [78, 78])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.walkExtended])
        #expect(d[0].rounds.isEmpty)
        #expect(d[0].seconds == 36)
    }

    @Test func fewRoundsNeedOnlyOneLongWalk() {
        // Week 5 shape: 3 rounds, so one long round is enough; total must still reach 60 s.
        let week5 = Schedule(name: "W5", warmUp: 300, run: 480, walk: 120, rounds: 3, coolDown: 300)
        let r = record(week5, runs: [480, 480, 480], walks: [185, 120, 120])
        #expect(kinds(RunAnalysis.deviations(in: r)) == [.walkExtended])
    }

    @Test func runExtended() {
        let r = record(runs: [240, 180, 180], walks: [120, 120, 120])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.runExtended])
        #expect(d[0].rounds == [1])
        #expect(d[0].seconds == 60)
    }

    @Test func extraRoundsAreNotCountedAsExtendedSegments() {
        let r = record(runs: [180, 180, 180, 180], walks: [120, 120, 120, 120])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.extraRounds])
        #expect(d[0].rounds == [4])
        #expect(d[0].seconds == 300)
    }

    @Test func tinyExtraRoundIsNoise() {
        let r = record(runs: [180, 180, 180, 8], walks: [120, 120, 120])
        #expect(RunAnalysis.deviations(in: r).isEmpty)
    }

    @Test func stoppedEarlyWithMissingRounds() {
        let r = record(runs: [180, 180], walks: [120])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.stoppedEarly])
        #expect(d[0].rounds == [3])
        #expect(d[0].seconds == 180) // missing run time only
    }

    @Test func skippingTheLastWalkIsNotStoppingEarly() {
        let r = record(runs: [180, 180, 180], walks: [120, 120])
        #expect(RunAnalysis.deviations(in: r).isEmpty)
    }

    @Test func finalRunCutShortCountsAsStoppedEarly() {
        let r = record(runs: [180, 180, 60], walks: [120, 120])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.stoppedEarly])
        #expect(d[0].rounds == [3])
        #expect(d[0].seconds == 120)
    }

    @Test func easierManualRunComparedToPlan() {
        let easy = Schedule(name: "Easy", warmUp: 300, run: 60, walk: 120, rounds: 4, coolDown: 300)
        let r = record(easy, runs: [60, 60, 60, 60], walks: [120, 120, 120, 120], stage: nil)
        let d = RunAnalysis.deviations(in: r, plannedSchedule: plan)
        #expect(kinds(d) == [.easierThanPlan])
        #expect(d[0].seconds == 540 - 240)
    }

    @Test func easierThanPlanOnlyForManualSessions() {
        let r = record(runs: [180, 180, 180], walks: [120, 120, 120])
        let harder = Schedule(name: "H", warmUp: 300, run: 300, walk: 120, rounds: 4, coolDown: 300)
        #expect(RunAnalysis.deviations(in: r, plannedSchedule: harder).isEmpty)
    }

    @Test func manualRunAtPlanLevelIsNotEasier() {
        let r = record(runs: [180, 180, 180], walks: [120, 120, 120], stage: nil)
        #expect(RunAnalysis.deviations(in: r, plannedSchedule: plan).isEmpty)
    }

    @Test func severalDeviationsComeInFixedOrderWithStableIds() {
        let r = record(runs: [240, 180, 180, 180], walks: [200, 120, 120])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.runExtended, .walkExtended, .extraRounds])
        #expect(d.map(\.id) == ["runExtended", "walkExtended", "extraRounds"])
        #expect(RunAnalysis.deviations(in: r) == d)
    }
}
