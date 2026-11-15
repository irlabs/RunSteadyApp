import Foundation

/// Which deviations the check-in asks about, and with which reason buttons.
public enum CheckInQuestions {
    public static let maximum = 2

    /// Most rule-relevant first: walk breaks feed the structural rule, longer runs the early step-up.
    static let priority: [Deviation.Kind] = [.walkExtended, .runExtended, .stoppedEarly, .extraRounds]

    /// At most `maximum` deviations worth a reason question. `easierThanPlan` gets its own question.
    public static func select(_ deviations: [Deviation]) -> [Deviation] {
        let byKind = Dictionary(deviations.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        return Array(priority.compactMap { byKind[$0] }.prefix(maximum))
    }

    /// An easier manual run gets "One-off or keep it easier?".
    public static func asksEasier(_ deviations: [Deviation]) -> Bool {
        deviations.contains { $0.kind == .easierThanPlan }
    }

    /// The reason buttons for a deviation, most likely first. Only reasons that make sense for it.
    public static func reasons(for kind: Deviation.Kind) -> [DeviationReason] {
        switch kind {
        case .walkExtended: [.neededRest, .discomfort, .traffic, .terrain, .withSomeone]
        case .runExtended: [.feltGood, .withSomeone, .terrain, .traffic]
        case .extraRounds: [.feltGood, .withSomeone]
        case .stoppedEarly: [.discomfort, .neededRest, .traffic, .terrain, .withSomeone]
        case .easierThanPlan: []
        }
    }

    public static func prompt(for deviation: Deviation) -> String {
        let time = Format.clock(deviation.seconds)
        switch deviation.kind {
        case .walkExtended:
            return "Your walk breaks ran long\(rounds(deviation.rounds)) (+\(time) in total). What was behind that?"
        case .runExtended:
            return "You ran past the target\(rounds(deviation.rounds)) (+\(time)). What kept you going?"
        case .extraRounds:
            let n = deviation.rounds.count
            return "You added \(n) extra round\(n == 1 ? "" : "s"). What made you go on?"
        case .stoppedEarly:
            return "You stopped a little before the plan was done. What happened?"
        case .easierThanPlan:
            return "That was easier than your plan. Just a one-off, or keep it easier for now?"
        }
    }

    /// " in round 2", " in rounds 2 and 3", " in rounds 1, 2 and 4"; empty when unknown.
    static func rounds(_ rounds: [Int]) -> String {
        guard let last = rounds.last else { return "" }
        if rounds.count == 1 { return " in round \(last)" }
        return " in rounds " + rounds.dropLast().map(String.init).joined(separator: ", ") + " and \(last)"
    }
}
