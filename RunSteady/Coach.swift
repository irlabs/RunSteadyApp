import Foundation
import RunSteadyKit

struct ChatMessage: Identifiable, Hashable {
    enum Role { case coach, user }
    let id = UUID()
    let role: Role
    var text: String
}

/// An open coach note as the coach sees it.
struct NoteBrief: Hashable {
    let id: String
    let kind: CoachNoteKind
    let text: String
    let ageDays: Int
    /// Ask about it once, in this wrap-up.
    let askNow: Bool
}

/// Everything the coach may talk about. The suggestion is already decided by the rule layer.
struct CoachContext {
    let record: SessionRecord
    let checkIn: CheckIn
    var suggestion: Suggestion
    /// Today's notable differences from the schedule; reasons are on `checkIn.reasons`.
    var deviations: [Deviation] = []
    var notes: [NoteBrief] = []
    /// Code-written summary of recent runs (`RunSummary.recent`).
    var recentRuns = ""
    /// Answer to "One-off or keep it easier?" after an easier manual run.
    var keepEasier: Bool?
    /// The first reply after the check-in questions, as opposed to answering a chat message.
    var isWrapUp = true
}

/// The coach only talks and explains. It never decides a schedule.
protocol Coach {
    func reply(context: CoachContext, transcript: [ChatMessage]) async -> String
    /// Notes worth remembering from one chat message. nil when there's nothing to go on.
    func extractNotes(from message: String, previous: String?, openNotes: [NoteBrief]) async -> NoteExtraction?
}

/// Offline fallback used when no API key is configured or the request fails.
struct ScriptedCoach: Coach {
    func reply(context: CoachContext, transcript: [ChatMessage]) async -> String {
        try? await Task.sleep(for: .milliseconds(900))
        let suggestion = context.suggestion
        if context.isWrapUp {
            let opening: String
            switch context.checkIn.knee {
            case .painful: opening = "Thanks for being honest about the pain. That matters more than any plan."
            case .mild: opening = "Noted the soreness. Easy does it."
            case .none: opening = context.checkIn.feeling == .tough ? "Tough ones count too. Well done for getting out." : "Lovely. That's all logged."
            }
            var reply = "\(opening) \(suggestion.reason) Next up: \(suggestion.schedule.summary), week \(suggestion.stageIndex + 1) of the plan. Take a rest day first."
            if let note = context.notes.first(where: \.askNow) {
                reply += " Last time you mentioned: \(note.text) How is that now?"
            }
            return reply
        }
        return "I've added that to today's notes. The plan stays the same: \(suggestion.schedule.summary). Slow and steady."
    }

    /// Without a language model there is no reading of free text: no notes beyond the knee answer.
    func extractNotes(from message: String, previous: String?, openNotes: [NoteBrief]) async -> NoteExtraction? { nil }
}

/// Talks to Claude through the Messages API.
/// Note: a key bundled in the app is fine for personal use only; a shipped app should call its own backend.
struct ClaudeCoach: Coach {
    let apiKey: String
    private let fallback = ScriptedCoach()
    private static let model = "claude-haiku-5-5"

    /// Reads `ANTHROPIC_API_KEY` from a gitignored `Secrets.plist` in the app bundle.
    static func fromBundledSecrets() -> ClaudeCoach? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let key = dict["ANTHROPIC_API_KEY"] as? String, !key.isEmpty else { return nil }
        return ClaudeCoach(apiKey: key)
    }

    func reply(context: CoachContext, transcript: [ChatMessage]) async -> String {
        do {
            return try await request(context: context, transcript: transcript)
        } catch {
            print("Coach request failed, using scripted reply: \(error)")
            return await fallback.reply(context: context, transcript: transcript)
        }
    }

    private func systemPrompt(_ context: CoachContext) -> String {
        let record = context.record
        let check = context.checkIn
        let suggestion = context.suggestion
        // With reported pain, never steer the runner toward overriding the easier plan.
        let editorRule = check.knee == .painful
            ? "The runner reported pain, so do not mention the schedule editor or any way to change the plan; encourage rest and the easier session."
            : "If the runner wants something else, tell them they can set their own schedule in the schedule editor, which always overrides the plan."
        return """
        You are Steady, a friendly tortoise coach inside a run-walk app for a 50-year-old beginner building up \
        gently to 5 km. This is the check-in after a run. Reply in plain text, two to four short sentences, warm \
        and calm, no lists, no emoji.

        The next schedule has already been decided by the app's fixed rules. Explain it, but never change it, \
        propose different intervals, or promise a different schedule. \(editorRule) You are not \
        a doctor: for pain that persists or is sharp, suggest rest and seeing a professional.

        Today's run: \(record.schedule.summary). Rounds done: \(record.roundsDone) of \(record.schedule.rounds) planned. \
        Distance \(Format.km(meters: record.distanceMeters)) km, time \(Format.clock(record.duration)), \
        average pace \(Format.pace(secondsPerKm: record.paceSecondsPerKm)) min/km, total overrun past segment targets \
        \(Format.clock(record.totalOverrun)).
        Check-in answers: overall "\(check.feeling.title)", comfortable pace: \(check.comfortable ? "yes" : "no"), \
        knees/muscles: "\(check.knee.title)".
        Decision by the rules: \(suggestion.decision.title). Reason: \(suggestion.reason)
        Next session: week \(suggestion.stageIndex + 1) of 8, session \(suggestion.sessionInStage) of 3: \
        \(suggestion.schedule.summary).
        \(earlyStepUp(context))\(easier(context))

        Today's differences from the schedule, measured by the app, with the runner's tapped reasons:
        \(deviations(context))

        Recent runs (computed by the app, newest first):
        \(context.recentRuns.isEmpty ? "- none" : context.recentRuns)

        What you remember from earlier conversations (open notes, oldest first):
        \(notes(context))

        Never invent progress, numbers or bigger jumps than the decision above. Take the runner's reasons as \
        given. \(followUpRule(context))
        """
    }

    private func earlyStepUp(_ context: CoachContext) -> String {
        guard context.suggestion.decision == .advanceEarly, let stay = context.suggestion.alternative else {
            return "No early step-up is on offer; don't suggest one."
        }
        return "The app offers an early step-up because recent runs went long and felt good. It's the runner's choice: "
            + "Try it (week \(context.suggestion.stageIndex + 1)) or Stay steady (\(stay.title)), and staying steady "
            + "is the default. Don't push either way."
    }

    private func easier(_ context: CoachContext) -> String {
        switch context.keepEasier {
        case true?: " After this easier run of their own, the runner chose to keep it easier for now; their own schedule stays."
        case false?: " This easier run of their own was a one-off; the plan above is back on."
        case nil: ""
        }
    }

    private func deviations(_ context: CoachContext) -> String {
        guard !context.deviations.isEmpty else { return "- none worth mentioning" }
        return context.deviations
            .map { "- " + RunSummary.describe($0, reason: context.checkIn.reasons?[$0.id]) }
            .joined(separator: "\n")
    }

    private func notes(_ context: CoachContext) -> String {
        guard !context.notes.isEmpty else { return "- none" }
        return context.notes.map { note in
            let age = note.ageDays == 0 ? "today" : note.ageDays == 1 ? "1 day ago" : "\(note.ageDays) days ago"
            let ask = context.isWrapUp && note.askNow ? " [ask about this once]" : ""
            return "- \(note.kind.title.lowercased()), \(age): \(note.text)\(ask)"
        }.joined(separator: "\n")
    }

    private func followUpRule(_ context: CoachContext) -> String {
        context.isWrapUp && context.notes.contains(where: \.askNow)
            ? "End with one short question about how the notes marked [ask about this once] are going."
            : "You already asked about the notes earlier in this conversation. Don't ask about them again, even if "
                + "the runner didn't answer; just respond to what they said now."
    }

    private func request(context: CoachContext, transcript: [ChatMessage]) async throws -> String {
        var messages: [[String: String]] = [["role": "user", "content": "I'm back from my run."]]
        messages += transcript.map { ["role": $0.role == .coach ? "assistant" : "user", "content": $0.text] }
        return try await send([
            "model": Self.model,
            "max_tokens": 4000,
            "system": systemPrompt(context),
            "messages": messages,
        ])
    }

    // MARK: Note extraction

    func extractNotes(from message: String, previous: String?, openNotes: [NoteBrief]) async -> NoteExtraction? {
        let notes = openNotes.isEmpty
            ? "(none)"
            : openNotes.map { "[\($0.id)] \($0.kind.rawValue): \($0.text)" }.joined(separator: "\n")
        let content = """
        Open notes:
        \(notes)

        The coach said: \(previous ?? "(nothing)")
        The runner replied: \(message)
        """
        do {
            let text = try await send([
                "model": Self.model,
                "max_tokens": 4000,
                "system": Self.extractorPrompt,
                "messages": [["role": "user", "content": content]],
                "output_config": ["format": ["type": "json_schema", "schema": Self.extractionSchema]],
            ])
            return try JSONDecoder().decode(NoteExtraction.self, from: Data(text.utf8))
        } catch {
            print("Note extraction failed: \(error)")
            return nil
        }
    }

    private static let extractorPrompt = """
    You keep short notes for a running coach app, so the coach can remember what a beginner runner said \
    and ask about it later. Read the runner's reply and return JSON.
    - new_notes: things worth remembering beyond today, said in this reply: aches or injuries (kind "injury"), \
    life events that affect running such as travel, illness or a busy week ("life"), goals ("goal"), likes and \
    dislikes about running ("preference"), anything else important ("other"). Text under 12 words, in the \
    runner's terms, e.g. "Left knee stiff on stairs". Set follow_up to true when it's worth asking about at a \
    later run (an ache, an upcoming event). Most replies need no new note.
    - Never add a note an open note already covers. Put that note's id in mentioned_ids instead.
    - resolve_ids: ids of open notes the runner says are over or no longer true.
    - Only use ids from the open notes list. Leave lists empty when nothing applies.
    """

    private static var extractionSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "new_notes": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "text": ["type": "string"],
                            "kind": ["type": "string", "enum": CoachNoteKind.allCases.map(\.rawValue)],
                            "follow_up": ["type": "boolean"],
                        ],
                        "required": ["text", "kind", "follow_up"],
                        "additionalProperties": false,
                    ] as [String: Any],
                ] as [String: Any],
                "resolve_ids": ["type": "array", "items": ["type": "string"]],
                "mentioned_ids": ["type": "array", "items": ["type": "string"]],
            ] as [String: Any],
            "required": ["new_notes", "resolve_ids", "mentioned_ids"],
            "additionalProperties": false,
        ]
    }

    // MARK: Transport

    /// Sends a Messages API request and returns the text of the reply.
    private func send(_ body: [String: Any]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CoachError.http((response as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        guard decoded.stop_reason != "refusal" else { throw CoachError.refused }
        guard decoded.stop_reason != "max_tokens" else { throw CoachError.truncated }
        let text = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CoachError.empty }
        return text
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    enum CoachError: Error {
        case http(Int, String)
        case refused
        case truncated
        case empty
    }
}
