import Foundation
import Testing
@testable import RunSteadyKit

@Suite struct DeviationReasonTests {
    @Test func incidentalReasonsNeverCount() {
        for reason in [DeviationReason.traffic, .terrain, .withSomeone, .feltGood] {
            #expect(reason.category == .incidental)
            #expect(!reason.isPhysical)
        }
    }

    @Test func physicalReasonsCount() {
        for reason in [DeviationReason.neededRest, .discomfort] {
            #expect(reason.category == .physical)
            #expect(reason.isPhysical)
        }
    }

    @Test func everyReasonHasATitle() {
        #expect(DeviationReason.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func checkInStoredBeforeReasonsExistedStillLoads() throws {
        let old = #"{"feeling":"okay","comfortable":true,"knee":"none","date":800000000}"#
        let checkIn = try JSONDecoder().decode(CheckIn.self, from: Data(old.utf8))
        #expect(checkIn.reasons == nil)
        #expect(checkIn.knee == .none)
    }

    @Test func reasonsRoundTripKeyedByDeviationId() throws {
        var checkIn = CheckIn(feeling: .okay, comfortable: true, knee: .none)
        checkIn.reasons = [Deviation.Kind.walkExtended.rawValue: .neededRest, Deviation.Kind.runExtended.rawValue: .feltGood]
        let decoded = try JSONDecoder().decode(CheckIn.self, from: JSONEncoder().encode(checkIn))
        #expect(decoded.reasons?["walkExtended"] == .neededRest)
        #expect(decoded.reasons?["runExtended"] == .feltGood)
        #expect(decoded == checkIn)
    }
}
