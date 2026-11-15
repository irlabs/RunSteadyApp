import Foundation
import RunSteadyKit
import SwiftData

/// Sample history for Simulator demos and UI tests (launch argument `-demoSeed YES`).
enum DemoData {
    @MainActor
    static func seed(into context: ModelContext) {
        let now = Date()
        func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        let entries: [(Date, Int, Int, CheckIn?, Int)] = [
            (ago(days: 13.1), 0, 1, CheckIn(feeling: .okay, comfortable: true, knee: .none), 0),
            (ago(days: 11.0), 0, 2, CheckIn(feeling: .okay, comfortable: true, knee: .mild, note: "Left knee a bit stiff afterwards."), 0),
            (ago(days: 9.2), 0, 2, CheckIn(feeling: .okay, comfortable: true, knee: .none), 0),
            (ago(days: 7.0), 0, 3, CheckIn(feeling: .great, comfortable: true, knee: .none), 0),
            (ago(days: 5.1), 1, 1, CheckIn(feeling: .okay, comfortable: true, knee: .none), 0),
            (ago(days: 2.2), 1, 2, CheckIn(feeling: .great, comfortable: true, knee: .none), 0),
            (ago(days: 0.03), 1, 3, nil, 1),
        ]
        for (index, entry) in entries.enumerated() {
            let (date, stage, session, checkIn, extra) = entry
            let record = makeRecord(date: date, stage: stage, session: session, extraRounds: extra, seed: index)
            var dated = checkIn
            dated?.date = date.addingTimeInterval(3600)
            context.insert(StoredSession(record, checkIn: dated))
        }
        context.insert(StoredPlan(ActivePlan(schedule: ProgressionPlan.fiveK[1].schedule, stageIndex: 1, sessionInStage: 3)))
        try? context.save()
    }

    static func makeRecord(date: Date, stage: Int, session: Int, extraRounds: Int, seed: Int) -> SessionRecord {
        let schedule = ProgressionPlan.fiveK[stage].schedule
        var segments: [SegmentRecord] = []
        var distance = 0.0
        var n = seed * 7 + 3
        func jitter(_ range: Int) -> Int { n = (n * 31 + 17) % 97; return n % 3 == 0 ? n % range : 0 }
        func add(_ kind: SegmentKind, _ round: Int, _ target: Int, speed: Double) {
            let actual = target + jitter(kind == .walk ? 40 : 22)
            segments.append(SegmentRecord(kind: kind, round: round, target: target, actual: actual))
            distance += Double(actual) * speed
        }
        add(.warmUp, 0, schedule.warmUp, speed: 1.45)
        for round in 1...(schedule.rounds + extraRounds) {
            add(.run, round, schedule.run, speed: 2.35)
            add(.walk, round, schedule.walk, speed: 1.55)
        }
        add(.coolDown, 0, schedule.coolDown, speed: 1.35)
        return SessionRecord(startedAt: date, schedule: schedule, stageIndex: stage, sessionInStage: session,
                             segments: segments, distanceMeters: distance, averageHeartRate: Double(124 + (seed * 5) % 11))
    }
}
