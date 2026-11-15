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

    @Test func walkExtendedCollectsRoundsAndExtraTime() {
        let r = record(runs: [180, 180, 180], walks: [180, 130, 170])
        let d = RunAnalysis.deviations(in: r)
        #expect(kinds(d) == [.walkExtended])
        #expect(d[0].rounds == [1, 3])
        #expect(d[0].seconds == 110)
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
