import Foundation

/// What a coach note is about. Only `injury` ever touches the plan, and only to make it more careful.
public enum CoachNoteKind: String, Codable, Sendable, CaseIterable {
    case injury, life, goal, preference, other

    public var title: String {
        switch self {
        case .injury: "Injury"
        case .life: "Life"
        case .goal: "Goal"
        case .preference: "Preference"
        case .other: "Note"
        }
    }
}

/// What the note extractor returns for one chat message (see `CoachNotes.apply`).
public struct NoteExtraction: Codable, Hashable, Sendable {
    public struct NewNote: Codable, Hashable, Sendable {
        public var text: String
        public var kind: CoachNoteKind
        /// The coach should ask about it once in a later check-in.
        public var followUp: Bool

        public init(text: String, kind: CoachNoteKind, followUp: Bool) {
            self.text = text
            self.kind = kind
            self.followUp = followUp
        }

        enum CodingKeys: String, CodingKey {
            case text, kind
            case followUp = "follow_up"
        }
    }

    public var newNotes: [NewNote]
    public var resolveIds: [String]
    public var mentionedIds: [String]

    public init(newNotes: [NewNote] = [], resolveIds: [String] = [], mentionedIds: [String] = []) {
        self.newNotes = newNotes
        self.resolveIds = resolveIds
        self.mentionedIds = mentionedIds
    }

    enum CodingKeys: String, CodingKey {
        case newNotes = "new_notes"
        case resolveIds = "resolve_ids"
        case mentionedIds = "mentioned_ids"
    }
}

/// The deterministic side of coach notes: when they open, age out, and what the model may change.
public enum CoachNotes {
    /// Notes resolve after about three weeks without a mention.
    public static let resolveAfterDays = 21

    public static func isStale(lastMentioned: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastMentioned) >= Double(resolveAfterDays) * 86_400
    }

    /// The injury note a check-in knee answer opens, if any.
    public static func injuryText(for knee: PainLevel) -> String? {
        switch knee {
        case .none: nil
        case .mild: "A little sore in the knees or muscles after a run."
        case .painful: "Pain in the knees or muscles after a run."
        }
    }

    /// The changes to make for an extraction, given the open notes (id → kind).
    /// Unknown ids are dropped. The model may not resolve an injury note: that would make the plan less
    /// careful, so it counts as a mention instead and the note ages out on its own.
    public static func apply(_ extraction: NoteExtraction, openNotes: [String: CoachNoteKind])
        -> (new: [NoteExtraction.NewNote], resolve: Set<String>, mention: Set<String>) {
        let known = extraction.resolveIds.filter { openNotes[$0] != nil }
        let resolve = Set(known.filter { openNotes[$0] != .injury })
        let mention = Set(extraction.mentionedIds.filter { openNotes[$0] != nil } + known.filter { openNotes[$0] == .injury })
            .subtracting(resolve)
        let new = extraction.newNotes
            .map { NoteExtraction.NewNote(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                          kind: $0.kind, followUp: $0.followUp) }
            .filter { !$0.text.isEmpty }
        return (new, resolve, mention)
    }
}
