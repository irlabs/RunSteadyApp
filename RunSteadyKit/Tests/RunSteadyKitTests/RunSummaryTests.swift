import Foundation
import Testing
@testable import RunSteadyKit

@Suite struct RunSummaryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(daysAgo: Double, walkOverrun: Int = 0, stage: Int? = 1) -> SessionRecord {
        let schedule = ProgressionPlan.fiveK[1].schedule // 6 × 2 min / 2 min
        var segments = [SegmentRecord(kind: .warmUp, round: 0, target: 300, actual: 300)]
        for round in 1...schedule.rounds {
            segments.append(SegmentRecord(kind: .run, round: round, target: 120, actual: 120))
            if round < schedule.rounds {
                segments.append(SegmentRecord(kind: .walk, round: round, target: 120, actual: 120 + walkOverrun))
            }
        }
        segments.append(SegmentRecord(kind: .coolDown, round: 0, target: 300, actual: 300))
        return SessionRecord(startedAt: t0.addingTimeInterval(-daysAgo * 86_400), schedule: schedule,
                             stageIndex: stage, sessionInStage: stage == nil ? nil : 3, segments: segments,
                             distanceMeters: 3210, averageHeartRate: nil)
    }

    @Test func lineStatesFactsAndReasons() {
        var checkIn = CheckIn(feeling: .great, comfortable: true, knee: .none)
        checkIn.reasons = [Deviation.Kind.walkExtended.rawValue: .neededRest]
        let line = RunSummary.line(record(daysAgo: 2, walkOverrun: 30), checkIn: checkIn, now: t0)
        #expect(line == "2 days ago: week 2 session 3, 6 of 6 rounds, 3.21 km, Great, comfortable, No issues. "
                + "Walk breaks ran long (+2:30): Needed the rest.")
    }

    @Test func manualRunsWithoutCheckIn() {
        let line = RunSummary.line(record(daysAgo: 0, stage: nil), checkIn: nil, now: t0)
        #expect(line == "Today: own schedule, 6 of 6 rounds, 3.21 km, no check-in.")
    }

    @Test func recentIsNewestFirstAndLimited() {
        let runs = (1...7).map { (record(daysAgo: Double($0)), CheckIn?.none) }
        let text = RunSummary.recent(runs, now: t0, limit: 3)
        #expect(text.split(separator: "\n").count == 3)
        #expect(text.hasPrefix("- Yesterday:"))
    }
}
