import Foundation

/// Five heart rate zones as a share of maximum heart rate (220 − age): 50, 60, 70, 80 and 90 %.
/// The phone works them out and sends them to the watch with the plan; stored as plain bounds
/// so they can be edited later without changing the format.
public struct HeartRateZones: Codable, Hashable, Sendable {
    public static let shares = [0.5, 0.6, 0.7, 0.8, 0.9]

    public var maxHeartRate: Int
    /// Lowest bpm of zones 1…5.
    public var lowerBounds: [Int]

    public init(maxHeartRate: Int) {
        self.maxHeartRate = maxHeartRate
        lowerBounds = Self.shares.map { Int((Double(maxHeartRate) * $0).rounded()) }
    }

    public init(age: Int) {
        self.init(maxHeartRate: 220 - age)
    }

    /// nil when the birth date has no year.
    public init?(birth: DateComponents, now: Date = .now, calendar: Calendar = .current) {
        guard let age = Self.age(birth: birth, now: now, calendar: calendar) else { return nil }
        self.init(age: age)
    }

    /// Zone 1…5, or nil below zone 1 (resting).
    public func zone(for bpm: Double) -> Int? {
        guard let index = lowerBounds.lastIndex(where: { Double($0) <= bpm.rounded(.down) }) else { return nil }
        return index + 1
    }

    /// Whole years between the birth date and `now`; nil without a year.
    public static func age(birth: DateComponents, now: Date, calendar: Calendar = .current) -> Int? {
        guard let year = birth.year else { return nil }
        var components = DateComponents(year: year, month: birth.month ?? 1, day: birth.day ?? 1)
        components.calendar = calendar
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.dateComponents([.year], from: date, to: now).year
    }
}
