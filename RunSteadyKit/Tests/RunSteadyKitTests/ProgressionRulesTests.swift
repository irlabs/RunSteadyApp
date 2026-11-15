import Foundation
import Testing
@testable import RunSteadyKit

private let day: TimeInterval = 86_400
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func outcome(
    daysAfterStart: Double, stage: Int?, completed: Bool = true,
    feeling: Feeling = .okay, comfortable: Bool = true, knee: PainLevel = .none,
    checkedIn: Bool = true
) -> SessionOutcome {
    SessionOutcome(
        date: t0.addingTimeInterval(daysAfterStart * day),
        stageIndex: stage,
        completedPlannedRounds: completed,
        checkIn: checkedIn ? CheckIn(feeling: feeling, comfortable: comfortable, knee: knee) : nil
    )
}

@Suite struct ProgressionRulesTests {
    @Test func noHistoryStartsAtStageOne() {
        let s = ProgressionRules.suggestion(history: [], now: t0)
        #expect(s.stageIndex == 0)
        #expect(s.sessionInStage == 1)
        #expect(s.decision == .start)
        #expect(s.schedule == ProgressionPlan.fiveK[0].schedule)
    }

    @Test func goodSessionMovesToNextSessionInSameStage() {
        let s = ProgressionRules.suggestion(history: [outcome(daysAfterStart: 0, stage: 0)], now: t0.addingTimeInterval(2 * day))
        #expect(s.stageIndex == 0)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .proceed)
    }

    @Test func threeGoodSessionsAdvanceAStage() {
        let h = [0.0, 2, 4].map { outcome(daysAfterStart: $0, stage: 0) }
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(6 * day))
        #expect(s.stageIndex == 1)
        #expect(s.sessionInStage == 1)
        #expect(s.decision == .advance)
    }

    @Test func mildKneeDiscomfortRepeats() {
        let h = [outcome(daysAfterStart: 0, stage: 0), outcome(daysAfterStart: 2, stage: 0, knee: .mild)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(4 * day))
        #expect(s.stageIndex == 0)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .repeatSession)
    }

    @Test func toughOrUncomfortableOrIncompleteRepeats() {
        for o in [
            outcome(daysAfterStart: 0, stage: 2, feeling: .tough),
            outcome(daysAfterStart: 0, stage: 2, comfortable: false),
            outcome(daysAfterStart: 0, stage: 2, completed: false),
        ] {
            let s = ProgressionRules.suggestion(history: [o], now: t0.addingTimeInterval(2 * day))
            #expect(s.decision == .repeatSession)
            #expect(s.stageIndex == 2)
            #expect(s.sessionInStage == 1)
        }
    }

    @Test func painStepsBackAStage() {
        let h = [outcome(daysAfterStart: 0, stage: 3), outcome(daysAfterStart: 2, stage: 3, knee: .painful)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(4 * day))
        #expect(s.stageIndex == 2)
        #expect(s.sessionInStage == 1)
        #expect(s.decision == .stepBack)
    }

    @Test func painAtFirstStageHoldsAtFirstStage() {
        let s = ProgressionRules.suggestion(history: [outcome(daysAfterStart: 0, stage: 0, knee: .painful)], now: t0.addingTimeInterval(day))
        #expect(s.stageIndex == 0)
        #expect(s.decision == .stepBack)
    }

    @Test func weekGapRepeatsLastSession() {
        let h = [outcome(daysAfterStart: 0, stage: 2), outcome(daysAfterStart: 2, stage: 2)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(9 * day))
        #expect(s.stageIndex == 2)
        #expect(s.sessionInStage == 2) // would have been 3
        #expect(s.decision == .repeatAfterGap)
    }

    @Test func twoWeekGapStepsBackOneStage() {
        let s = ProgressionRules.suggestion(history: [outcome(daysAfterStart: 0, stage: 4)], now: t0.addingTimeInterval(14 * day))
        #expect(s.stageIndex == 3)
        #expect(s.sessionInStage == 1)
        #expect(s.decision == .stepBackAfterGap)
    }

    @Test func monthGapStepsBackTwoStages() {
        let s = ProgressionRules.suggestion(history: [outcome(daysAfterStart: 0, stage: 4)], now: t0.addingTimeInterval(30 * day))
        #expect(s.stageIndex == 2)
        #expect(s.decision == .stepBackAfterGap)
    }

    @Test func manualSessionsDoNotMoveTheProgression() {
        let h = [outcome(daysAfterStart: 0, stage: 1), outcome(daysAfterStart: 2, stage: nil)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(3 * day))
        #expect(s.stageIndex == 1)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .proceed)
    }

    @Test func manualSessionsDoNotCountTowardAStepUp() {
        let h = [
            outcome(daysAfterStart: 0, stage: 1), outcome(daysAfterStart: 2, stage: 1),
            outcome(daysAfterStart: 4, stage: nil), outcome(daysAfterStart: 5, stage: nil),
        ]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(6 * day))
        #expect(s.stageIndex == 1)
        #expect(s.sessionInStage == 3)
    }

    @Test func toughOrIncompleteManualSessionIsIgnored() {
        for manual in [
            outcome(daysAfterStart: 2, stage: nil, feeling: .tough),
            outcome(daysAfterStart: 2, stage: nil, comfortable: false),
            outcome(daysAfterStart: 2, stage: nil, completed: false),
        ] {
            let s = ProgressionRules.suggestion(history: [outcome(daysAfterStart: 0, stage: 1), manual],
                                                now: t0.addingTimeInterval(3 * day))
            #expect(s.stageIndex == 1)
            #expect(s.sessionInStage == 2)
            #expect(s.decision == .proceed)
        }
    }

    @Test func painOnManualSessionStepsBack() {
        let h = [outcome(daysAfterStart: 0, stage: 3), outcome(daysAfterStart: 2, stage: nil, knee: .painful)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(3 * day))
        #expect(s.stageIndex == 2)
        #expect(s.sessionInStage == 1)
        #expect(s.decision == .stepBack)
    }

    @Test func soreOnManualSessionRepeats() {
        let h = [outcome(daysAfterStart: 0, stage: 3), outcome(daysAfterStart: 2, stage: nil, knee: .mild)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(3 * day))
        #expect(s.stageIndex == 3)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .repeatSession)
    }

    @Test func gapClockCountsFromManualSessions() {
        // Last planned run 14 days ago, but a manual run 3 days ago: no gap step-back.
        let h = [outcome(daysAfterStart: 0, stage: 4), outcome(daysAfterStart: 11, stage: nil)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(14 * day))
        #expect(s.stageIndex == 4)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .proceed)
    }

    @Test func gapClockStillRunsWhenManualSessionIsOld() {
        let h = [outcome(daysAfterStart: 0, stage: 4), outcome(daysAfterStart: 1, stage: nil)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(14 * day))
        #expect(s.stageIndex == 3)
        #expect(s.decision == .stepBackAfterGap)
    }

    @Test func missingCheckInCountsWhenRoundsCompleted() {
        let s = ProgressionRules.suggestion(history: [outcome(daysAfterStart: 0, stage: 0, checkedIn: false)], now: t0.addingTimeInterval(day))
        #expect(s.sessionInStage == 2)
    }

    @Test func finalStageHolds() {
        let last = ProgressionPlan.fiveK.count - 1
        let h = [0.0, 2, 4].map { outcome(daysAfterStart: $0, stage: last) }
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(6 * day))
        #expect(s.stageIndex == last)
        #expect(s.decision == .maintain)
    }

    @Test func planIsGradual() {
        let runTotals = ProgressionPlan.fiveK.map { $0.schedule.run * $0.schedule.rounds }
        #expect(ProgressionPlan.fiveK.count == 8)
        #expect(runTotals == runTotals.sorted())
        #expect(ProgressionPlan.fiveK.last?.schedule.walk == 0)
    }

    @Test func sessionRecordDerivedValues() {
        let schedule = Schedule(name: "T", warmUp: 300, run: 60, walk: 120, rounds: 2, coolDown: 300)
        let record = SessionRecord(
            startedAt: t0, schedule: schedule, stageIndex: 0, sessionInStage: 1,
            segments: [
                SegmentRecord(kind: .warmUp, round: 0, target: 300, actual: 300),
                SegmentRecord(kind: .run, round: 1, target: 60, actual: 70),
                SegmentRecord(kind: .walk, round: 1, target: 120, actual: 120),
                SegmentRecord(kind: .run, round: 2, target: 60, actual: 60),
                SegmentRecord(kind: .walk, round: 2, target: 120, actual: 130),
                SegmentRecord(kind: .run, round: 3, target: 60, actual: 60),
            ],
            distanceMeters: 1000, averageHeartRate: 130)
        #expect(record.duration == 740)
        #expect(record.roundsDone == 3)
        #expect(record.extraRounds == 1)
        #expect(record.completedPlannedRounds)
        #expect(record.totalOverrun == 20)
        #expect(record.paceSecondsPerKm == 740)
    }
}
