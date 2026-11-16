import Foundation
import Testing
@testable import RunSteadyKit

private let day: TimeInterval = 86_400
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func schedule(run: Int, walk: Int = 60, rounds: Int) -> Schedule {
    Schedule(name: "My schedule", warmUp: 300, run: run, walk: walk, rounds: rounds, coolDown: 300)
}

private func planned(_ days: Double, stage: Int) -> SessionOutcome {
    SessionOutcome(date: t0.addingTimeInterval(days * day), stageIndex: stage, completedPlannedRounds: true,
                   checkIn: CheckIn(feeling: .okay, comfortable: true, knee: .none))
}

private func manual(
    _ days: Double, _ schedule: Schedule, completed: Bool = true,
    feeling: Feeling = .great, comfortable: Bool = true, knee: PainLevel = .none, checkedIn: Bool = true
) -> SessionOutcome {
    SessionOutcome(date: t0.addingTimeInterval(days * day), stageIndex: nil, completedPlannedRounds: completed,
                   checkIn: checkedIn ? CheckIn(feeling: feeling, comfortable: comfortable, knee: knee) : nil,
                   schedule: schedule)
}

@Suite struct ManualLevelTests {
    @Test func planWeeksMapToThemselves() {
        for (index, stage) in ProgressionPlan.fiveK.enumerated() {
            #expect(ProgressionPlan.level(of: stage.schedule) == index)
        }
    }

    @Test func sixTimesThreeIsWeekThree() {
        // 18 min running (week 3: 15) with 3 min blocks (week 3).
        #expect(ProgressionPlan.level(of: schedule(run: 180, rounds: 6)) == 2)
    }

    @Test func longBlocksWeighMoreThanTotal() {
        // Blocks at week 5 (8 min), total at week 3 (16 min): week 4.
        #expect(ProgressionPlan.level(of: schedule(run: 480, rounds: 2)) == 3)
    }

    @Test func shortBlocksHoldBackALargeTotal() {
        // Total at week 6 (24 min), blocks at week 3 (3 min): week 4, not 5.
        #expect(ProgressionPlan.level(of: schedule(run: 180, rounds: 8)) == 3)
    }

    @Test func belowWeekOneHasNoLevel() {
        #expect(ProgressionPlan.level(of: schedule(run: 30, rounds: 4)) == nil)
    }
}

@Suite struct ManualProgressionTests {
    private let sixByThree = schedule(run: 180, rounds: 6)

    @Test func goodManualRunAboveThePlanStepsUpOneWeek() {
        let s = ProgressionRules.suggestion(history: [manual(0, sixByThree)], now: t0.addingTimeInterval(day))
        #expect(s.stageIndex == 1)
        #expect(s.sessionInStage == 1)
        #expect(s.decision == .advanceFromManual)
    }

    @Test func eachGoodManualRunStepsUpOneMoreWeek() {
        let h = [planned(0, stage: 0), manual(2, sixByThree), manual(4, sixByThree)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(5 * day))
        #expect(s.stageIndex == 2)
        #expect(s.decision == .advanceFromManual)
    }

    @Test func stepsStopAtTheManualLevel() {
        let h = [planned(0, stage: 0), manual(2, sixByThree), manual(4, sixByThree), manual(6, sixByThree)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(7 * day))
        #expect(s.stageIndex == 2)
        #expect(s.sessionInStage == 1)
    }

    @Test func manualRunAtOrBelowThePlanDoesNotMoveIt() {
        let h = [planned(0, stage: 2), manual(2, sixByThree)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(3 * day))
        #expect(s.stageIndex == 2)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .proceed)
    }

    @Test func toughUncomfortableOrIncompleteManualRunIsIgnored() {
        for run in [
            manual(2, sixByThree, feeling: .tough),
            manual(2, sixByThree, comfortable: false),
            manual(2, sixByThree, completed: false),
        ] {
            let s = ProgressionRules.suggestion(history: [planned(0, stage: 0), run], now: t0.addingTimeInterval(3 * day))
            #expect(s.stageIndex == 0)
            #expect(s.sessionInStage == 2)
        }
    }

    @Test func manualRunWaitsForItsCheckIn() {
        let h = [planned(0, stage: 0), manual(2, sixByThree, checkedIn: false)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(3 * day))
        #expect(s.stageIndex == 0)
    }

    @Test func soreManualRunDoesNotStepUp() {
        let h = [planned(0, stage: 0), manual(2, sixByThree, knee: .mild)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(3 * day))
        #expect(s.stageIndex == 0)
        #expect(s.decision == .repeatSession)
    }

    @Test func plannedRunAfterTheStepUpCountsInTheNewWeek() {
        let h = [planned(0, stage: 0), manual(2, sixByThree), planned(4, stage: 1)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(5 * day))
        #expect(s.stageIndex == 1)
        #expect(s.sessionInStage == 2)
        #expect(s.decision == .proceed)
    }

    @Test func gapAfterAManualStepUpRepeatsTheOldWeek() {
        let h = [planned(0, stage: 1), manual(2, sixByThree)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(9 * day))
        #expect(s.stageIndex == 1)
        #expect(s.decision == .repeatAfterGap)
    }
}
