import Foundation
import Testing
@testable import RunSteadyKit

@Suite struct SessionRecordTests {
    private let schedule = Schedule(name: "Spike", warmUp: 20, run: 20, walk: 10, rounds: 1, coolDown: 10)

    @Test func realRunsAreNotTests() {
        let record = SessionRecord(startedAt: .now, schedule: schedule, stageIndex: nil, sessionInStage: nil,
                                   segments: [], distanceMeters: 0, averageHeartRate: nil)
        #expect(!record.isTestRun)
    }

    @Test func testFlagSurvivesTheTrip() throws {
        let record = SessionRecord(startedAt: .now, schedule: schedule, stageIndex: nil, sessionInStage: nil,
                                   segments: [], distanceMeters: 0, averageHeartRate: nil, isTest: true)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded.isTestRun)
    }

    /// Records sent by an older watch build have no `isTest` key at all.
    @Test func recordsWithoutTheFlagStillDecode() throws {
        let record = SessionRecord(startedAt: .now, schedule: schedule, stageIndex: 0, sessionInStage: 1,
                                   segments: [], distanceMeters: 0, averageHeartRate: nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        json.removeValue(forKey: "isTest")
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!decoded.isTestRun)
        #expect(decoded.id == record.id)
    }
}
