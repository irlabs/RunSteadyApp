import Foundation
import Testing
@testable import RunSteadyKit

@Suite struct HeartRateZonesTests {
    @Test func maxHeartRateIs220MinusAge() {
        #expect(HeartRateZones(age: 50).maxHeartRate == 170)
        #expect(HeartRateZones(age: 30).maxHeartRate == 190)
    }

    /// Five zones at 50/60/70/80/90 % of max, rounded to whole beats.
    @Test func lowerBoundsArePercentagesOfMax() {
        #expect(HeartRateZones(age: 50).lowerBounds == [85, 102, 119, 136, 153])
    }

    @Test func zoneForHeartRate() {
        let zones = HeartRateZones(age: 50)
        #expect(zones.zone(for: 70) == nil)   // below zone 1: resting
        #expect(zones.zone(for: 85) == 1)
        #expect(zones.zone(for: 101.6) == 1)
        #expect(zones.zone(for: 102) == 2)
        #expect(zones.zone(for: 125) == 3)
        #expect(zones.zone(for: 140) == 4)
        #expect(zones.zone(for: 153) == 5)
        #expect(zones.zone(for: 190) == 5)    // above max still zone 5
    }

    @Test func ageFromBirthDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        let before = DateComponents(year: 1976, month: 11, day: 21)
        let after = DateComponents(year: 1976, month: 11, day: 22)
        #expect(HeartRateZones.age(birth: before, now: now, calendar: cal) == 50)
        #expect(HeartRateZones.age(birth: after, now: now, calendar: cal) == 49)
        #expect(HeartRateZones.age(birth: DateComponents(month: 3, day: 1), now: now, calendar: cal) == nil)
    }

    @Test func zonesFromBirthDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        let zones = HeartRateZones(birth: DateComponents(year: 1976, month: 5, day: 1), now: now, calendar: cal)
        #expect(zones?.maxHeartRate == 170)
        #expect(HeartRateZones(birth: DateComponents(), now: now, calendar: cal) == nil)
    }

    @Test func roundTripsAsJSON() throws {
        let zones = HeartRateZones(age: 50)
        let decoded = try JSONDecoder().decode(HeartRateZones.self, from: JSONEncoder().encode(zones))
        #expect(decoded == zones)
    }
}
