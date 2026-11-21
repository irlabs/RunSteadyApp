import Foundation
import HealthKit
import RunSteadyKit

/// F11: writes the check-in's effort score (1–10) to Apple Health as the effort of the watch's
/// workout. Only the phone can: the watch's watchOS 10 has no effort score type.
/// The workout may not have synced from the watch yet, so scores wait in a small queue and are
/// retried on launch and whenever the HealthKit observer sees a new workout.
final class EffortWriter: @unchecked Sendable {
    static let shared = EffortWriter()

    struct Pending: Codable, Hashable {
        var sessionID: UUID
        var score: Int
        var start: Date
        var end: Date
        var added: Date
    }

    /// Give up on a score after this long without a matching workout (e.g. a Simulator run).
    static let giveUpAfter: TimeInterval = 7 * 86_400

    private let store = HKHealthStore()
    private let key = "pendingEffortScores"
    private let lock = NSLock()
    private var writing = false

    func save(score: Int, for record: SessionRecord) {
        let item = Pending(sessionID: record.id, score: score, start: record.startedAt,
                           end: record.startedAt.addingTimeInterval(TimeInterval(record.duration)), added: .now)
        update { queue in
            queue.removeAll { $0.sessionID == item.sessionID }
            queue.append(item)
        }
        Diag.log("Effort", "Score \(score) for \(record.shortID) queued")
        Task { await writePending() }
    }

    /// Tries every queued score once. Overlapping calls are skipped: the running one covers them.
    func writePending() async {
        guard HKHealthStore.isHealthDataAvailable(), !queue.isEmpty else { return }
        let start = lock.withLock { () -> Bool in
            defer { writing = true }
            return !writing
        }
        guard start else { return }
        defer { lock.withLock { writing = false } }

        for item in queue {
            if Date().timeIntervalSince(item.added) > Self.giveUpAfter {
                Diag.log("Effort", "Score for \(item.sessionID.short) dropped: no workout found in a week")
                remove(item)
                continue
            }
            guard let workout = await workout(for: item) else {
                Diag.log("Effort", "Workout for \(item.sessionID.short) not in Health yet; will retry")
                continue
            }
            do {
                let sample = HKQuantitySample(type: HKQuantityType(.workoutEffortScore),
                                              quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(item.score)),
                                              start: workout.startDate, end: workout.endDate)
                try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
                Diag.log("Effort", "Score \(item.score) written to workout \(workout.uuid.short)")
                remove(item)
            } catch {
                Diag.log("Effort", "Writing score for \(item.sessionID.short) failed: \(error.localizedDescription)")
            }
        }
    }

    /// The running workout closest to the run's start, within a quarter of an hour either side.
    private func workout(for item: Pending) async -> HKWorkout? {
        let margin: TimeInterval = 15 * 60
        let predicate = HKQuery.predicateForSamples(withStart: item.start.addingTimeInterval(-margin),
                                                    end: item.end.addingTimeInterval(margin), options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)], limit: 20)
        do {
            let workouts = try await descriptor.result(for: store)
            return workouts
                .filter { $0.workoutActivityType == .running && $0.metadata?[HealthObserver.testKey] == nil }
                .min { abs($0.startDate.timeIntervalSince(item.start)) < abs($1.startDate.timeIntervalSince(item.start)) }
        } catch {
            Diag.log("Effort", "Workout query failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Queue (UserDefaults)

    private var queue: [Pending] {
        lock.withLock {
            UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Pending].self, from: $0) } ?? []
        }
    }

    private func update(_ change: (inout [Pending]) -> Void) {
        var items = queue
        change(&items)
        lock.withLock { UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key) }
    }

    private func remove(_ item: Pending) {
        update { $0.removeAll { $0.sessionID == item.sessionID } }
    }
}
