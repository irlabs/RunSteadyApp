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
    /// The check-in conversation from the answers on (phone only, G11), so it can be reopened at its end.
    /// Optional, so stores from before it still open.
    var chatPayload: Data?
    /// Key of the suggestion this check-in left to choose (G11). Cleared by any choice of the next session.
    var openChoice: String?

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
    /// When the runner last declined a structural step-back ("Settle in"); restarts that rule's window.
    var structuralDeclinedAt: Date?

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

/// Something the runner told the coach, kept so the coach can remember and ask about it later.
@Model
final class CoachNote {
    @Attribute(.unique) var id: UUID
    var text: String
    var kindRaw: String
    var isOpen: Bool
    /// The coach should ask about it once; cleared after it asked.
    var followUp: Bool
    var createdAt: Date
    var lastMentionedAt: Date
    /// The session whose check-in produced the note.
    var sessionID: UUID?

    init(text: String, kind: CoachNoteKind, followUp: Bool, sessionID: UUID?, date: Date = .now) {
        id = UUID()
        self.text = text
        kindRaw = kind.rawValue
        isOpen = true
        self.followUp = followUp
        createdAt = date
        lastMentionedAt = date
        self.sessionID = sessionID
    }

    var kind: CoachNoteKind {
        get { CoachNoteKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// Short id the language model sees and refers back to.
    var shortID: String { String(id.uuidString.prefix(8)).lowercased() }
}

enum Store {
    static func container(inMemory: Bool) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: StoredSession.self, StoredPlan.self, CoachNote.self, configurations: config)
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
    static func openNotes(in context: ModelContext) -> [CoachNote] {
        let descriptor = FetchDescriptor<CoachNote>(predicate: #Predicate { $0.isOpen },
                                                    sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Notes resolve after about three weeks without a mention.
    @MainActor
    static func resolveStaleNotes(in context: ModelContext, now: Date = .now) {
        for note in openNotes(in: context) where CoachNotes.isStale(lastMentioned: note.lastMentionedAt, now: now) {
            note.isOpen = false
        }
        try? context.save()
    }

    /// A sore or painful knee answer opens an injury note, or counts as a mention of the open one.
    @MainActor
    static func noteKnee(_ knee: PainLevel, sessionID: UUID, in context: ModelContext, now: Date = .now) {
        guard let text = CoachNotes.injuryText(for: knee) else { return }
        if let open = openNotes(in: context).last(where: { $0.kind == .injury }) {
            open.lastMentionedAt = now
        } else {
            context.insert(CoachNote(text: text, kind: .injury, followUp: true, sessionID: sessionID, date: now))
        }
        try? context.save()
    }

    /// Apply what the note extractor found in a chat message, within the rules in `CoachNotes.apply`.
    @MainActor
    static func apply(_ extraction: NoteExtraction, sessionID: UUID, in context: ModelContext, now: Date = .now) {
        let open = openNotes(in: context)
        let byID = Dictionary(open.map { ($0.shortID, $0) }, uniquingKeysWith: { a, _ in a })
        let changes = CoachNotes.apply(extraction, openNotes: byID.mapValues(\.kind))
        for id in changes.resolve { byID[id]?.isOpen = false }
        for id in changes.mention { byID[id]?.lastMentionedAt = now }
        for note in changes.new {
            context.insert(CoachNote(text: note.text, kind: note.kind, followUp: note.followUp, sessionID: sessionID, date: now))
        }
        try? context.save()
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
    func suggestion(now: Date = .now, structuralDeclinedAt: Date? = nil, hasOpenInjury: Bool = false) -> Suggestion {
        let outcomes = compactMap { stored in stored.record.map { SessionOutcome($0, checkIn: stored.checkIn) } }
        return ProgressionRules.suggestion(history: outcomes, now: now, structuralDeclinedAt: structuralDeclinedAt,
                                           hasOpenInjury: hasOpenInjury)
    }
}

#if os(iOS)
extension StoredSession {
    var chat: [ChatMessage] {
        get { chatPayload.flatMap { try? JSONDecoder().decode([ChatMessage].self, from: $0) } ?? [] }
        set { chatPayload = try? JSONEncoder().encode(newValue) }
    }
}
#endif
