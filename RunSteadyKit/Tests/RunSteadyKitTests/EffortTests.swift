import Foundation
import Testing
@testable import RunSteadyKit

@Suite struct EffortTests {
    @Test func effortMapsToFeeling() {
        for score in 1...4 { #expect(Feeling(effort: score) == .great) }
        for score in 5...7 { #expect(Feeling(effort: score) == .okay) }
        for score in 8...10 { #expect(Feeling(effort: score) == .tough) }
    }

    @Test func outOfRangeScoresAreClamped() {
        #expect(Feeling(effort: 0) == .great)
        #expect(Feeling(effort: 14) == .tough)
    }

    @Test func sliderStartsAtFive() {
        #expect(Effort.initial == 5)
        #expect(Effort.range == 1...10)
    }

    @Test func effortIsStoredOnTheCheckIn() throws {
        var checkIn = CheckIn(feeling: .okay, comfortable: true, knee: .none)
        checkIn.effort = 6
        let decoded = try JSONDecoder().decode(CheckIn.self, from: JSONEncoder().encode(checkIn))
        #expect(decoded.effort == 6)
    }

    /// Check-ins stored before the effort score existed still load.
    @Test func olderCheckInsDecodeWithoutEffort() throws {
        let old = #"{"feeling":"great","comfortable":true,"knee":"none","date":0}"#
        let decoded = try JSONDecoder().decode(CheckIn.self, from: Data(old.utf8))
        #expect(decoded.effort == nil)
        #expect(decoded.feeling == .great)
    }

    @Test func effortLabels() {
        #expect(Effort.label(1) == "Very easy")
        #expect(Effort.label(5) == "Moderate")
        #expect(Effort.label(10) == "All out")
    }
}
