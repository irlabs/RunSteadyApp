import Foundation
import Testing
@testable import RunSteadyKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let week2 = ActivePlan(schedule: ProgressionPlan.fiveK[1].schedule, stageIndex: 1, sessionInStage: 3)
private let week3 = ActivePlan(schedule: ProgressionPlan.fiveK[2].schedule, stageIndex: 2, sessionInStage: 1)

/// G8: a plan that arrives before the watch app listens must not be lost.
@MainActor
@Suite struct InboxTests {
    @Test func valueBeforeTheHandlerIsHandedOverLater() {
        let inbox = Inbox<Int>()
        inbox.receive(1)
        var got: [Int] = []
        inbox.handler = { got.append($0) }
        #expect(got == [1])
    }

    @Test func onlyTheLatestWaitingValueIsKept() {
        let inbox = Inbox<Int>()
        inbox.receive(1)
        inbox.receive(2)
        var got: [Int] = []
        inbox.handler = { got.append($0) }
        #expect(got == [2])
    }

    @Test func withAHandlerValuesGoStraightThroughAndAreNotReplayed() {
        let inbox = Inbox<Int>()
        var got: [Int] = []
        inbox.handler = { got.append($0) }
        inbox.receive(1)
        inbox.receive(2)
        inbox.handler = { got.append($0 * 10) }
        #expect(got == [1, 2])
    }
}

/// G9: what the Today screen says about the plan on the watch.
@Suite struct WatchPlanStatusTests {
    private func receipt(_ plan: ActivePlan, decidedAt: Date?, reportedAt: Date) -> PlanReceipt {
        PlanReceipt(plan: plan, decidedAt: decidedAt, reportedAt: reportedAt)
    }

    @Test func nothingClaimedBeforeTheWatchReports() {
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: nil, sentAt: t0) == .unknown)
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: nil, sentAt: nil) == .unknown)
    }

    @Test func sameSessionAndDecisionIsOnTheWatch() {
        let watch = receipt(week3, decidedAt: t0.addingTimeInterval(0.4), reportedAt: t0.addingTimeInterval(5))
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: watch, sentAt: t0) == .onWatch)
    }

    @Test func sameSessionButAnotherDecisionIsNotAMatch() {
        // "Keep mine" again later: the watch must restart its gap clock from the new decision.
        let watch = receipt(week3, decidedAt: t0, reportedAt: t0.addingTimeInterval(5))
        let later = t0.addingTimeInterval(3600)
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: later, watch: watch, sentAt: later) == .sending)
    }

    @Test func sentButNotReportedSinceIsSending() {
        let watch = receipt(week2, decidedAt: t0.addingTimeInterval(-86_400), reportedAt: t0.addingTimeInterval(-60))
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: watch, sentAt: t0) == .sending)
    }

    @Test func watchReportedAnOlderPlanAfterTheSend() {
        let watch = receipt(week2, decidedAt: t0.addingTimeInterval(-86_400), reportedAt: t0.addingTimeInterval(120))
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: watch, sentAt: t0) == .older(week2))
    }

    @Test func notSentFromThisLaunchCountsFromTheDecision() {
        let stale = receipt(week2, decidedAt: nil, reportedAt: t0.addingTimeInterval(120))
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: stale, sentAt: nil) == .older(week2))
        let early = receipt(week2, decidedAt: nil, reportedAt: t0.addingTimeInterval(-120))
        #expect(WatchPlanStatus.evaluate(plan: week3, decidedAt: t0, watch: early, sentAt: nil) == .sending)
    }

    @Test func receiptSurvivesTheTrip() throws {
        let original = receipt(week3, decidedAt: t0, reportedAt: t0.addingTimeInterval(9))
        let decoded = try JSONDecoder().decode(PlanReceipt.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
