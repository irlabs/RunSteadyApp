import Foundation

/// The effort slider in the check-in: how hard the run felt, 1–10 (Apple's workout effort scale).
public enum Effort {
    public static let range = 1...10
    public static let initial = 5

    public static func label(_ score: Int) -> String {
        switch min(max(score, range.lowerBound), range.upperBound) {
        case 1...2: "Very easy"
        case 3...4: "Easy"
        case 5...6: "Moderate"
        case 7...8: "Hard"
        case 9: "Very hard"
        default: "All out"
        }
    }
}

extension Feeling {
    /// The rule layer still works with Great / Okay / Tough: 1–4 Great, 5–7 Okay, 8–10 Tough.
    public init(effort score: Int) {
        switch score {
        case ...4: self = .great
        case 5...7: self = .okay
        default: self = .tough
        }
    }
}
