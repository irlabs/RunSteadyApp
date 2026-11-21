import Foundation
import Testing
@testable import RunSteadyKit

private let day: TimeInterval = 86_400
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func plan(_ stage: Int, _ session: Int) -> ActivePlan {
    ActivePlan(schedule: ProgressionPlan.fiveK[stage].schedule, stageIndex: stage, sessionInStage: session)
}

private func good(_ days: Double, stage: Int) -> SessionOutcome {
    SessionOutcome(date: t0.addingTimeInterval(days * day), stageIndex: stage, completedPlannedRounds: true,
                   checkIn: CheckIn(feeling: .okay, comfortable: true, knee: .none))
}

/// F15: the watch applies the same gap rules as the phone, from the same shared code.
@Suite struct GapRuleTests {
    @Test func noGapUnderSixDays() {
        #expect(GapRule.adjust(plan(3, 2), decision: .proceed, since: t0, now: t0.addingTimeInterval(5.9 * day)) == nil)
    }

    @Test func noClockNoAdjustment() {
        #expect(GapRule.adjust(plan(3, 2), decision: .proceed, since: nil, now: t0) == nil)
    }

    @Test func sixDaysRepeatsTheLastSession() {
        let a = GapRule.adjust(plan(3, 2), decision: .proceed, since: t0, now: t0.addingTimeInterval(6 * day))
        #expect(a?.plan == plan(3, 1))
        #expect(a?.decision == .repeatAfterGap)
        #expect(a?.gapDays == 6)
    }

    @Test func sixDaysAfterAStepUpRepeatsTheLastSessionOfThePreviousWeek() {
        let a = GapRule.adjust(plan(3, 1), decision: .advance, since: t0, now: t0.addingTimeInterval(7 * day))
        #expect(a?.plan == plan(2, 3))
    }

    /// The phone only repeats after a good session; a plan that is already a repeat stays.
    @Test func sixDaysAfterARepeatChangesNothing() {
        #expect(GapRule.adjust(plan(3, 2), decision: .repeatSession, since: t0, now: t0.addingTimeInterval(7 * day)) == nil)
        #expect(GapRule.adjust(plan(7, 3), decision: .maintain, since: t0, now: t0.addingTimeInterval(7 * day)) == nil)
    }

    @Test func twelveDaysStepsBackAWeek() {
        let a = GapRule.adjust(plan(3, 2), decision: .proceed, since: t0, now: t0.addingTimeInterval(12 * day))
        #expect(a?.plan == plan(2, 1))
        #expect(a?.decision == .stepBackAfterGap)
    }

    @Test func twentyFourDaysStepsBackTwoWeeksButNotBelowWeekOne() {
        #expect(GapRule.adjust(plan(3, 2), decision: .proceed, since: t0, now: t0.addingTimeInterval(24 * day))?.plan == plan(1, 1))
        #expect(GapRule.adjust(plan(1, 3), decision: .proceed, since: t0, now: t0.addingTimeInterval(30 * day))?.plan == plan(0, 1))
    }

    @Test func weekOneSessionOneHasNothingToRepeatOrStepBackTo() {
        #expect(GapRule.adjust(plan(0, 1), decision: .start, since: t0, now: t0.addingTimeInterval(30 * day)) == nil)
    }

    /// Manual schedules always win over automatic progression.
    @Test func manualPlansAreNeverAdjusted() {
        let manual = ActivePlan(schedule: Schedule(name: "Mine", warmUp: 300, run: 90, walk: 90, rounds: 6, coolDown: 300))
        #expect(GapRule.adjust(manual, decision: nil, since: t0, now: t0.addingTimeInterval(30 * day)) == nil)
    }

    /// Without the phone's decision the watch infers it from the position: session 1 means a step-up.
    @Test func infersTheDecisionWhenThePhoneSentNone() {
        #expect(GapRule.adjust(plan(3, 1), decision: nil, since: t0, now: t0.addingTimeInterval(7 * day))?.plan == plan(2, 3))
        #expect(GapRule.adjust(plan(3, 3), decision: nil, since: t0, now: t0.addingTimeInterval(7 * day))?.plan == plan(3, 2))
    }

    @Test func clockStartsAtTheLaterOfLastRunAndPhoneDecision() {
        let run = t0
        let decided = t0.addingTimeInterval(3 * day)
        #expect(GapRule.clockStart(lastSession: run, planDecidedAt: decided) == decided)
        #expect(GapRule.clockStart(lastSession: decided, planDecidedAt: run) == decided)
        #expect(GapRule.clockStart(lastSession: nil, planDecidedAt: run) == run)
        #expect(GapRule.clockStart(lastSession: nil, planDecidedAt: nil) == nil)
    }

    @Test func welcomeText() {
        #expect(GapRule.describe(days: 6) == "6 days")
        #expect(GapRule.describe(days: 13) == "13 days")
        #expect(GapRule.describe(days: 14) == "2 weeks")
        #expect(GapRule.describe(days: 25) == "3 weeks")
    }

    /// Same inputs, same answer: the watch's adjustment of the phone's no-gap plan equals the
    /// phone's own suggestion with the gap.
    @Test func watchMatchesThePhone() {
        let histories: [[SessionOutcome]] = [
            [good(0, stage: 2)],
            [good(0, stage: 2), good(2, stage: 2)],
            [good(0, stage: 2), good(2, stage: 2), good(4, stage: 2)],
            [good(0, stage: 0)],
            [good(0, stage: 6), good(2, stage: 6), good(4, stage: 6)],
            [good(0, stage: 7), good(2, stage: 7), good(4, stage: 7)],
        ]
        for history in histories {
            let last = history.map(\.date).max()!
            let noGap = ProgressionRules.suggestion(history: history, now: last.addingTimeInterval(day))
            for gap in [3.0, 6, 8, 12, 20, 24, 40] {
                let now = last.addingTimeInterval(gap * day)
                let phone = ActivePlan(ProgressionRules.suggestion(history: history, now: now))
                let watch = GapRule.adjust(ActivePlan(noGap), decision: noGap.decision, since: last, now: now)?.plan
                    ?? ActivePlan(noGap)
                #expect(watch == phone, "history \(history.count) sessions at week \(history[0].stageIndex! + 1), gap \(gap) days")
            }
        }
    }
}
