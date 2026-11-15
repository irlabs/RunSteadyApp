import Foundation
import RunSteadyKit

struct ChatMessage: Identifiable, Hashable {
    enum Role { case coach, user }
    let id = UUID()
    let role: Role
    var text: String
}

/// Everything the coach may talk about. The suggestion is already decided by the rule layer.
struct CoachContext {
    let record: SessionRecord
    let checkIn: CheckIn
    let suggestion: Suggestion
}

/// The coach only talks and explains. It never decides a schedule.
protocol Coach {
    func reply(context: CoachContext, transcript: [ChatMessage]) async -> String
}

/// Offline fallback used when no API key is configured or the request fails.
struct ScriptedCoach: Coach {
    func reply(context: CoachContext, transcript: [ChatMessage]) async -> String {
        try? await Task.sleep(for: .milliseconds(900))
        let suggestion = context.suggestion
        let isWrapUp = transcript.filter { $0.role == .user }.count <= 3
        if isWrapUp {
            let opening: String
            switch context.checkIn.knee {
            case .painful: opening = "Thanks for being honest about the pain. That matters more than any plan."
            case .mild: opening = "Noted the soreness. Easy does it."
            case .none: opening = context.checkIn.feeling == .tough ? "Tough ones count too. Well done for getting out." : "Lovely. That's all logged."
            }
            return "\(opening) \(suggestion.reason) Next up: \(suggestion.schedule.summary), week \(suggestion.stageIndex + 1) of the plan. Take a rest day first."
        }
        return "I've added that to today's notes. The plan stays the same: \(suggestion.schedule.summary). Slow and steady."
    }
}

/// Talks to Claude through the Messages API.
/// Note: a key bundled in the app is fine for personal use only; a shipped app should call its own backend.
struct ClaudeCoach: Coach {
    let apiKey: String
    private let fallback = ScriptedCoach()

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
        """
    }

    private func request(context: CoachContext, transcript: [ChatMessage]) async throws -> String {
        var messages: [[String: String]] = [["role": "user", "content": "I'm back from my run."]]
        messages += transcript.map { ["role": $0.role == .coach ? "assistant" : "user", "content": $0.text] }

        let body: [String: Any] = [
            "model": "claude-haiku-5-5",
            "max_tokens": 4000,
            "fallbacks": "default",
            "system": systemPrompt(context),
            "messages": messages,
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CoachError.http((response as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        guard decoded.stop_reason != "refusal" else { throw CoachError.refused }
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
        case empty
    }
}
