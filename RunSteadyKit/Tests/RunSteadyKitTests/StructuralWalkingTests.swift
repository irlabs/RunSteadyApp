import Foundation
import Testing
@testable import RunSteadyKit

private let day: TimeInterval = 86_400
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// A session whose walk breaks may have run long. `reason` is the tapped answer (nil = skipped).
private func session(
    _ daysAfterStart: Double, stage: Int?, walkExtended: Bool = false, reason: DeviationReason? = nil,
    knee: PainLevel = .none, checkedIn: Bool = true, runExtended: Bool = false
) -> SessionOutcome {
    var deviations: Set<Deviation.Kind> = []
    if walkExtended { deviations.insert(.walkExtended) }
    if runExtended { deviations.insert(.runExtended) }
    var checkIn = CheckIn(feeling: .okay, comfortable: true, knee: knee)
    if let reason {
        checkIn.reasons = [(walkExtended ? Deviation.Kind.walkExtended : .runExtended).rawValue: reason]
    }
    return SessionOutcome(date: t0.addingTimeInterval(daysAfterStart * day), stageIndex: stage,
                          completedPlannedRounds: true, checkIn: checkedIn ? checkIn : nil, deviations: deviations)
}

private func isStructural(_ sessions: [SessionOutcome]) -> Bool {
    StructuralWalking.isStructural(sessions, policy: .standard)
}

@Suite struct StructuralWalkingTests {
    // MARK: The core function

    @Test func physicalReasonInThreeOfFive() {
        let s = [
            session(0, stage: 2, walkExtended: true, reason: .neededRest),
            session(2, stage: 2),
            session(4, stage: 2, walkExtended: true, reason: .discomfort),
            session(6, stage: 3),
            session(8, stage: 3, walkExtended: true, reason: .neededRest),
        ]
        #expect(isStructural(s))
    }

    @Test func skippedReasonCountsTowardThePattern() {
        let s = [
            session(0, stage: 2, walkExtended: true),
            session(2, stage: 2, walkExtended: true, checkedIn: false),
            session(4, stage: 2, walkExtended: true, reason: .neededRest),
        ]
        #expect(isStructural(s))
    }

    @Test func incidentalReasonsNeverCount() {
        let s = [
            session(0, stage: 2, walkExtended: true, reason: .traffic),
            session(2, stage: 2, walkExtended: true, reason: .withSomeone),
            session(4, stage: 2, walkExtended: true, reason: .terrain),
            session(6, stage: 3, walkExtended: true, reason: .neededRest),
            session(8, stage: 3, walkExtended: true),
        ]
        #expect(!isStructural(s))
    }

    @Test func onlyTheLastFiveCount() {
        let s = [
            session(0, stage: 2, walkExtended: true, reason: .neededRest), // outside the window
            session(2, stage: 2),
            session(4, stage: 2, walkExtended: true, reason: .neededRest),
            session(6, stage: 3),
            session(8, stage: 3, walkExtended: true, reason: .neededRest),
            session(10, stage: 3),
        ]
        #expect(!isStructural(s))
    }

    @Test func extendedRunsAreNotExtendedWalks() {
        let s = (0..<3).map { session(Double($0 * 2), stage: 2, reason: .discomfort, runExtended: true) }
        #expect(!isStructural(s))
    }

    @Test func emptyHistoryIsNotStructural() {
        #expect(!isStructural([]))
    }

    // MARK: Wired into the suggestion

    private let pattern = [
        session(0, stage: 3, walkExtended: true, reason: .neededRest),
        session(2, stage: 3, walkExtended: true),
        session(4, stage: 3, walkExtended: true, reason: .discomfort),
        session(6, stage: 4),
        session(8, stage: 4),
    ]

    @Test func patternOffersAStepBack() {
        let s = ProgressionRules.suggestion(history: pattern, now: t0.addingTimeInterval(10 * day))
        #expect(s.decision == .stepBackStructural)
        #expect(s.decision.title == "Settle in")
        #expect(s.stageIndex == 3)
        #expect(s.sessionInStage == 1)
        #expect(s.reason == "Your walk breaks ran long in 3 of your last 5 runs. A week back lets the running "
                + "catch up. Prefer to carry on with week 5? Tap Keep mine.")
    }

    @Test func keepMineFallsBackToTheNormalPlan() {
        let s = ProgressionRules.suggestion(history: pattern, now: t0.addingTimeInterval(10 * day))
        #expect(s.alternative == ActivePlan(schedule: ProgressionPlan.fiveK[4].schedule, stageIndex: 4, sessionInStage: 3))
        let normal = ProgressionRules.suggestion(history: [session(0, stage: 3)], now: t0.addingTimeInterval(2 * day))
        #expect(normal.alternative == nil)
    }

    @Test func stepUpRunStepsBackFromTheWeekActuallyRun() {
        let h = (0..<3).map { session(Double($0 * 2), stage: 3, walkExtended: true, reason: .neededRest) }
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(6 * day))
        #expect(s.decision == .stepBackStructural)
        #expect(s.stageIndex == 2) // ran week 4 (index 3), so week 3; not "week 4 again"
        #expect(s.alternative?.stageIndex == 4) // declining keeps the step-up
        #expect(s.reason.hasPrefix("Your walk breaks ran long in your last 3 runs."))
        #expect(s.reason.contains("carry on with week 5?"))
    }

    @Test func structuralWinsOverARepeat() {
        let h = [
            session(0, stage: 3, walkExtended: true, reason: .neededRest),
            session(2, stage: 3, walkExtended: true),
            session(4, stage: 3, walkExtended: true, knee: .mild),
        ]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(6 * day))
        #expect(s.decision == .stepBackStructural)
        #expect(s.stageIndex == 2)
        #expect(s.alternative?.stageIndex == 3)
        #expect(s.alternative?.sessionInStage == 3)
    }

    @Test func gapStepBackIsNotDoubled() {
        let s = ProgressionRules.suggestion(history: pattern, now: t0.addingTimeInterval(22 * day))
        #expect(s.decision == .stepBackAfterGap)
        #expect(s.stageIndex == 3)
    }

    @Test func decliningRestartsTheWindow() {
        let declined = t0.addingTimeInterval(9 * day)
        let after = pattern + [session(10, stage: 4, walkExtended: true)]
        let s1 = ProgressionRules.suggestion(history: after, now: t0.addingTimeInterval(11 * day),
                                             structuralDeclinedAt: declined)
        #expect(s1.decision == .advance)

        let more = after + [session(12, stage: 5, walkExtended: true), session(14, stage: 5, walkExtended: true)]
        let s2 = ProgressionRules.suggestion(history: more, now: t0.addingTimeInterval(15 * day),
                                             structuralDeclinedAt: declined)
        #expect(s2.decision == .stepBackStructural)
        #expect(s2.stageIndex == 4)
    }

    @Test func noStructuralStepBackBelowWeekOne() {
        let h = [
            session(0, stage: 0, walkExtended: true, reason: .neededRest),
            session(2, stage: 0, walkExtended: true, reason: .neededRest),
            session(4, stage: 0, walkExtended: true, reason: .neededRest, knee: .mild), // stays in week 1
        ]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(6 * day))
        #expect(s.decision == .repeatSession)
        #expect(s.stageIndex == 0)
    }

    @Test func painStepBackIsNotDoubled() {
        let h = pattern + [session(10, stage: 4, knee: .painful)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(12 * day))
        #expect(s.decision == .stepBack)
        #expect(s.stageIndex == 3)
    }

    @Test func onlySessionsSinceTheLastStepBackCount() {
        let h = [
            session(0, stage: 3, walkExtended: true, reason: .neededRest),
            session(2, stage: 3, walkExtended: true, reason: .neededRest),
            session(4, stage: 3, knee: .painful), // steps back to week 3
            session(6, stage: 2, walkExtended: true, reason: .neededRest),
            session(8, stage: 2),
        ]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(10 * day))
        #expect(s.decision == .proceed)
        #expect(s.stageIndex == 2)
    }

    @Test func acceptedStructuralStepBackDoesNotTriggerTwiceInARow() {
        let h = pattern + [session(10, stage: 3, walkExtended: true, reason: .neededRest)]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(12 * day))
        #expect(s.decision == .proceed)
        #expect(s.stageIndex == 3)
        #expect(s.sessionInStage == 2)
    }

    @Test func manualSessionsAreNotPartOfThePattern() {
        let h = [
            session(0, stage: 3),
            session(1, stage: nil, walkExtended: true, reason: .neededRest),
            session(2, stage: nil, walkExtended: true, reason: .neededRest),
            session(3, stage: nil, walkExtended: true, reason: .neededRest),
        ]
        let s = ProgressionRules.suggestion(history: h, now: t0.addingTimeInterval(5 * day))
        #expect(s.decision == .proceed)
    }
}
