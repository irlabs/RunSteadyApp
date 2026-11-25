import Foundation
import Testing
@testable import RunSteadyKit

/// G7: a planned session has no walk after its last run. On the watch, the walk after the last run
/// is part of the cool-down, unless another run follows it.
@Suite struct ClosingWalkTests {
    /// 2 × 1 min run / 2 min walk.
    private let schedule = Schedule(name: "T", warmUp: 300, run: 60, walk: 120, rounds: 2, coolDown: 300)

    private func seg(_ kind: SegmentKind, _ round: Int, _ actual: Int) -> SegmentRecord {
        let target = switch kind {
        case .warmUp: schedule.warmUp
        case .run: schedule.run
        case .walk: schedule.walk
        case .coolDown: schedule.coolDown
        }
        return SegmentRecord(kind: kind, round: round, target: target, actual: actual)
    }

    @Test func plannedSessionEndsWithRunThenCoolDown() {
        #expect(schedule.plannedSegments.map(\.kind) == [.warmUp, .run, .walk, .run, .coolDown])
        #expect(schedule.totalSeconds == 300 + 60 + 120 + 60 + 300)
    }

    @Test func singleRoundHasNoWalk() {
        let one = Schedule(name: "1", warmUp: 300, run: 600, walk: 120, rounds: 1, coolDown: 300)
        #expect(one.plannedSegments.map(\.kind) == [.warmUp, .run, .coolDown])
    }

    @Test func continuousRunIsUnchanged() {
        let continuous = ProgressionPlan.fiveK[7].schedule
        #expect(continuous.plannedSegments.map(\.kind) == [.warmUp, .run, .coolDown])
        #expect(continuous.totalSeconds == 300 + 1800 + 300)
    }

    @Test func week2TakesThirtyTwoMinutes() {
        #expect(ProgressionPlan.fiveK[1].schedule.totalSeconds / 60 == 32)
    }

    @Test func closingWalkJoinsTheCoolDown() {
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.run, 2, 60),
                    seg(.walk, 2, 90), seg(.coolDown, 0, 240)]
        let merged = schedule.mergingClosingWalk(done)
        #expect(merged.map(\.kind) == [.warmUp, .run, .walk, .run, .coolDown])
        #expect(merged.last?.actual == 330)
        #expect(merged.last?.target == 300)
        #expect(merged.reduce(0) { $0 + $1.actual } == done.reduce(0) { $0 + $1.actual })
    }

    @Test func closingWalkBecomesTheCoolDownWhenThereIsNone() {
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.run, 2, 60), seg(.walk, 2, 200)]
        let merged = schedule.mergingClosingWalk(done)
        #expect(merged.map(\.kind) == [.warmUp, .run, .walk, .run, .coolDown])
        #expect(merged.last == SegmentRecord(kind: .coolDown, round: 0, target: 300, actual: 200))
    }

    @Test func walkBeforeAnExtraRunStaysAWalk() {
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.run, 2, 60),
                    seg(.walk, 2, 120), seg(.run, 3, 60), seg(.coolDown, 0, 300)]
        #expect(schedule.mergingClosingWalk(done) == done)
    }

    @Test func walkAfterTheLastExtraRunJoinsTheCoolDown() {
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.run, 2, 60),
                    seg(.walk, 2, 120), seg(.run, 3, 60), seg(.walk, 3, 100), seg(.coolDown, 0, 300)]
        let merged = schedule.mergingClosingWalk(done)
        #expect(merged.map(\.kind) == [.warmUp, .run, .walk, .run, .walk, .run, .coolDown])
        #expect(merged.last?.actual == 400)
    }

    @Test func walkAfterAnEarlierRoundStays() {
        // Stopped after round 1 of 2: that walk was planned, it isn't a closing walk.
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.coolDown, 0, 300)]
        #expect(schedule.mergingClosingWalk(done) == done)
    }

    @Test func mergingTwiceChangesNothing() {
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.run, 2, 60),
                    seg(.walk, 2, 90), seg(.coolDown, 0, 240)]
        let once = schedule.mergingClosingWalk(done)
        #expect(schedule.mergingClosingWalk(once) == once)
    }

    @Test func longClosingWalkIsNoDeviation() {
        let done = [seg(.warmUp, 0, 300), seg(.run, 1, 60), seg(.walk, 1, 120), seg(.run, 2, 60),
                    seg(.walk, 2, 400), seg(.coolDown, 0, 300)]
        let record = SessionRecord(startedAt: .now, schedule: schedule, stageIndex: 0, sessionInStage: 1,
                                   segments: done, distanceMeters: 2000, averageHeartRate: nil)
        #expect(RunAnalysis.deviations(in: record).isEmpty)
    }
}
