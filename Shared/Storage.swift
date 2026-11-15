import Foundation
import RunSteadyKit
import SwiftData

/// A finished session. The full record is kept as JSON so the same value type
/// travels unchanged between watch, phone and the rule layer.
@Model
final class StoredSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var payload: Data
    var checkInPayload: Data?

    init(_ record: SessionRecord, checkIn: CheckIn? = nil) {
        id = record.id
        startedAt = record.startedAt
        payload = (try? JSONEncoder().encode(record)) ?? Data()
        checkInPayload = checkIn.flatMap { try? JSONEncoder().encode($0) }
    }

    var record: SessionRecord? {
        try? JSONDecoder().decode(SessionRecord.self, from: payload)
    }

    var checkIn: CheckIn? {
        get { checkInPayload.flatMap { try? JSONDecoder().decode(CheckIn.self, from: $0) } }
        set { checkInPayload = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

/// The single active plan (what the watch runs next).
@Model
final class StoredPlan {
    var payload: Data
    var updatedAt: Date
    /// Key of a suggestion the user chose to ignore, so it is not offered again.
    var dismissedSuggestion: String?

    init(_ plan: ActivePlan) {
        payload = (try? JSONEncoder().encode(plan)) ?? Data()
        updatedAt = .now
    }

    var plan: ActivePlan {
        get { (try? JSONDecoder().decode(ActivePlan.self, from: payload)) ?? .initial }
        set {
            payload = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = .now
        }
    }
}

enum Store {
    static func container(inMemory: Bool) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: StoredSession.self, StoredPlan.self, configurations: config)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    @MainActor
    static func storedPlan(in context: ModelContext) -> StoredPlan {
        if let existing = try? context.fetch(FetchDescriptor<StoredPlan>()).first { return existing }
        let created = StoredPlan(.initial)
        context.insert(created)
        return created
    }

    @MainActor
    static func upsert(_ record: SessionRecord, in context: ModelContext) {
        let id = record.id
        let existing = try? context.fetch(FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })).first
        if existing == nil { context.insert(StoredSession(record)) }
        try? context.save()
    }
}

extension Suggestion {
    /// Stable key used to remember "keep mine" decisions.
    var key: String { "\(stageIndex)-\(sessionInStage)-\(decision.rawValue)" }
}

extension Array where Element == StoredSession {
    func suggestion(now: Date = .now) -> Suggestion {
        let outcomes = compactMap { stored in stored.record.map { SessionOutcome($0, checkIn: stored.checkIn) } }
        return ProgressionRules.suggestion(history: outcomes, now: now)
    }
}
