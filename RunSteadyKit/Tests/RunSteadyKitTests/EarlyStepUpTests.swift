import Foundation
import Testing
@testable import RunSteadyKit

private let day: TimeInterval = 86_400
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// A planned session. `feltGood` = runs extended with the "Felt good" reason.
private func session(
    _ days: Double, stage: Int, feltGood: Bool = false, reason: DeviationReason = .feltGood,
    feeling: Feeling = .okay, comfortable: Bool = true, knee: PainLevel = .none, completed: Bool = true
) -> SessionOutcome {
    var checkIn = CheckIn(feeling: feeling, comfortable: comfortable, knee: knee)
    if feltGood { checkIn.reasons = [Deviation.Kind.runExtended.rawValue: reason] }
    return SessionOutcome(date: t0.addingTimeInterval(days * day), stageIndex: stage,
                          completedPlannedRounds: completed, checkIn: checkIn,
                          deviations: feltGood ? [.runExtended] : [])
}

private func suggest(_ history: [SessionOutcome], at days: Double, injury: Bool = false) -> Suggestion {
    ProgressionRules.suggestion(history: history, now: t0.addingTimeInterval(days * day), hasOpenInjury: injury)
}

@Suite struct EarlyStepUpTests {
    @Test func twoFeltGoodRunsOfferAnEarlyStepUp() {
        let s = suggest([session(0, stage: 2, feltGood: true), session(2, stage: 2, feltGood: true)], at: 3)
        #expect(s.decision == .advanceEarly)
        #expect(s.stageIndex == 3)
        #expect(s.sessionInStage == 1)
        // Stay steady: the third session of the current week, as normal.
        #expect(s.alternative == ActivePlan(schedule: ProgressionPlan.fiveK[2].schedule, stageIndex: 2, sessionInStage: 3))
    }

    @Test func anOfferDoesNotMoveTheRunnerYet() {
        let s = suggest([session(0, stage: 2, feltGood: true), session(2, stage: 2, feltGood: true)], at: 3)
        #expect(s.position.stageIndex == 2)
        #expect(s.position.sessionInStage == 3)
        let normal = suggest([session(0, stage: 2)], at: 1)
        #expect(normal.position == normal)
    }

    @Test func oneFeltGoodRunIsNotEnough() {
        let s = suggest([session(0, stage: 2), session(2, stage: 2, feltGood: true)], at: 3)
        #expect(s.decision == .proceed)
        #expect(s.alternative == nil)
    }

    @Test func incidentalReasonsOtherThanFeltGoodDontCount() {
        let s = suggest([session(0, stage: 2, feltGood: true, reason: .traffic),
                         session(2, stage: 2, feltGood: true)], at: 3)
        #expect(s.decision == .proceed)
    }

    @Test func feltGoodNeverSkipsTheThirdSessionWhenAdvancingAnyway() {
        let h = [0.0, 2, 4].map { session($0, stage: 2, feltGood: true) }
        let s = suggest(h, at: 5)
        #expect(s.decision == .advance)
        #expect(s.stageIndex == 3)
    }

    @Test func soreToughOrUncomfortableInTheLastThreeBlocks() {
        for spoiler in [session(0, stage: 2, knee: .mild),
                        session(0, stage: 2, feeling: .tough),
                        session(0, stage: 2, comfortable: false)] {
            let s = suggest([spoiler, session(2, stage: 2, feltGood: true), session(4, stage: 2, feltGood: true)], at: 5)
            #expect(s.decision == .proceed)
            #expect(s.stageIndex == 2)
        }
    }

    @Test func openInjuryNoteBlocks() {
        let s = suggest([session(0, stage: 2, feltGood: true), session(2, stage: 2, feltGood: true)], at: 3, injury: true)
        #expect(s.decision == .proceed)
    }

    @Test func recentStepBackBlocks() {
        let h = [
            session(0, stage: 3, knee: .painful), // steps back to week 3
            session(2, stage: 2, completed: false),
            session(4, stage: 2, feltGood: true),
            session(6, stage: 2, feltGood: true),
        ]
        #expect(suggest(h, at: 7).decision == .proceed)
    }

    @Test func stepBackOverTwoWeeksAgoDoesNotBlock() {
        let h = [
            session(0, stage: 3, knee: .painful),
            session(5, stage: 2, completed: false),
            session(10, stage: 2, completed: false),
            session(15, stage: 2, feltGood: true),
            session(17, stage: 2, feltGood: true),
        ]
        #expect(suggest(h, at: 18).decision == .advanceEarly)
    }

    @Test func neverEarlyIntoTheLastWeek() {
        let s = suggest([session(0, stage: 6, feltGood: true), session(2, stage: 6, feltGood: true)], at: 3)
        #expect(s.decision == .proceed)
        #expect(s.stageIndex == 6)
    }

    @Test func aGapRepeatsInstead() {
        let s = suggest([session(0, stage: 2, feltGood: true), session(2, stage: 2, feltGood: true)], at: 9)
        #expect(s.decision == .repeatAfterGap)
        #expect(s.stageIndex == 2)
    }

    @Test func consecutiveEarlyStepUpsAreAllowedAfterAGoodRun() {
        let h = [
            session(0, stage: 2, feltGood: true),
            session(2, stage: 2, feltGood: true),
            session(4, stage: 3), // accepted early step-up, felt fine
            session(6, stage: 3, feltGood: true),
        ]
        let s = suggest(h, at: 7)
        #expect(s.decision == .advanceEarly)
        #expect(s.stageIndex == 4)
    }

    @Test func safetyNetAfterAToughEarlyStepUp() {
        let h = [
            session(0, stage: 2, feltGood: true),
            session(2, stage: 2, feltGood: true),
            session(4, stage: 3, feeling: .tough), // the run after the early step-up
        ]
        let next = suggest(h, at: 5)
        #expect(next.decision == .repeatSession)
        #expect(next.stageIndex == 3)

        let later = h + [session(6, stage: 3, completed: false),
                         session(8, stage: 3, feltGood: true), session(10, stage: 3, feltGood: true)]
        #expect(suggest(later, at: 11).decision == .proceed) // within ~2 weeks of the tough run
    }

    @Test func eachWeekCanBeLeftEarlyOnlyOnce() {
        let h = [
            session(0, stage: 2, feltGood: true),
            session(2, stage: 2, feltGood: true),
            session(4, stage: 3, knee: .painful), // back to week 3
            session(8, stage: 2, completed: false),
            session(12, stage: 2, completed: false),
            session(16, stage: 2, completed: false),
            session(20, stage: 2, feltGood: true),
            session(22, stage: 2, feltGood: true),
        ]
        #expect(suggest(h, at: 23).decision == .proceed)
    }

    @Test func manualSessionsDontCountTowardTheWindow() {
        var manual = session(3, stage: 0, feltGood: true)
        manual.stageIndex = nil
        let s = suggest([session(0, stage: 2), manual, session(4, stage: 2, feltGood: true)], at: 5)
        #expect(s.decision == .proceed)
    }
}
