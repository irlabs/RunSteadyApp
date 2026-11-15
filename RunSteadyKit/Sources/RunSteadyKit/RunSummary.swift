import Foundation

/// Short, code-written facts about runs for the coach prompt. The model talks about these; it never computes them.
public enum RunSummary {
    /// e.g. "2 days ago: week 2 session 3, 6 of 6 rounds, 3.21 km, Great, comfortable, No issues.
    /// Walk breaks ran long (+1:10): Needed the rest."
    public static func line(_ record: SessionRecord, checkIn: CheckIn?, now: Date) -> String {
        let days = max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: record.startedAt, to: now).day ?? 0)
        let when = days == 0 ? "Today" : days == 1 ? "Yesterday" : "\(days) days ago"
        let plan = record.stageIndex.map { "week \($0 + 1) session \(record.sessionInStage ?? 1)" } ?? "own schedule"
        var text = "\(when): \(plan), \(record.roundsDone) of \(record.schedule.rounds) rounds, "
            + "\(Format.km(meters: record.distanceMeters)) km"
        if let checkIn {
            text += ", \(checkIn.feeling.title), \(checkIn.comfortable ? "comfortable" : "not comfortable"), \(checkIn.knee.title)."
        } else {
            text += ", no check-in."
        }
        for deviation in RunAnalysis.deviations(in: record) {
            text += " " + describe(deviation, reason: checkIn?.reasons?[deviation.id])
        }
        return text
    }

    /// One deviation with its tapped reason, e.g. "Runs went past target (+0:40): Felt good."
    public static func describe(_ deviation: Deviation, reason: DeviationReason?) -> String {
        let time = Format.clock(deviation.seconds)
        let what = switch deviation.kind {
        case .walkExtended: "Walk breaks ran long (+\(time))"
        case .runExtended: "Runs went past target (+\(time))"
        case .extraRounds: "Extra rounds (+\(time))"
        case .stoppedEarly: "Stopped early (\(time) of running left)"
        case .easierThanPlan: "Easier than the plan (\(time) less running)"
        }
        return what + ": " + (reason?.title ?? "no reason given") + "."
    }

    /// The most recent `limit` runs, newest first, one per line.
    public static func recent(_ runs: [(SessionRecord, CheckIn?)], now: Date, limit: Int = 5) -> String {
        runs.sorted { $0.0.startedAt > $1.0.startedAt }.prefix(limit)
            .map { "- " + line($0.0, checkIn: $0.1, now: now) }
            .joined(separator: "\n")
    }
}
