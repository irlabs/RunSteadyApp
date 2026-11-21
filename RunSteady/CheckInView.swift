import RunSteadyKit
import SwiftData
import SwiftUI

/// Post-run check-in as a short chat. The structured answers (effort slider, two fixed questions,
/// reasons for deviations, one-off or not) feed the rule layer; the coach (language model or
/// scripted fallback) only words the wrap-up and answers follow-ups. A typed answer instead of a
/// button counts as no tap for the rules; it goes to the coach and the note extractor (F12).
struct CheckInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]
    @Query private var plans: [StoredPlan]
    let session: StoredSession

    private enum Step: Equatable { case effort, comfort, knee, reason(Deviation), easier, wrapUp, chat }
    /// A free-text answer to one of the questions, with the question it answered.
    private struct TypedAnswer { let question: String; let text: String }
    @State private var step = Step.effort
    @State private var messages: [ChatMessage] = []
    @State private var effort = Double(Effort.initial)
    @State private var feeling = Feeling.okay
    @State private var comfortable = true
    @State private var knee = PainLevel.none
    /// Today's notable deviations, and those still to ask about.
    @State private var deviations: [Deviation] = []
    @State private var questions: [Deviation] = []
    @State private var reasons: [Deviation.ID: DeviationReason] = [:]
    @State private var askEasier = false
    @State private var keepEasier: Bool?
    @State private var thinking = false
    @State private var draft = ""
    @State private var typedAnswer = ""
    @State private var typedAnswers: [TypedAnswer] = []
    @State private var coachContext: CoachContext?
    @State private var offer: Suggestion?
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(messages) { Bubble(message: $0) }
                            if thinking { TypingBubble() }
                            if let offer {
                                SuggestionCard(suggestion: offer) { withAnimation { self.offer = nil } }
                                    .padding(.top, 4)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { scroll(proxy) }
                    .onChange(of: thinking) { scroll(proxy) }
                    .onChange(of: offer?.key) { scroll(proxy) }
                }
                inputBar
            }
            .background(Color.pageBackground)
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold).accessibilityIdentifier("checkInDone")
                }
            }
        }
        .fontDesign(.rounded)
        .onAppear(perform: begin)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: Conversation

    private func begin() {
        guard messages.isEmpty, let record = session.record else { return }
        Store.resolveStaleNotes(in: context)
        var intro = "Welcome back! \(record.roundsDone) rounds, \(Format.km(meters: record.distanceMeters)) km in \(Format.clock(record.duration))."
        if record.extraRounds > 0 { intro += " That's \(record.extraRounds) more than planned." }
        say(intro)
        say("How hard did it feel? 1 is very easy, 10 is all out.")
    }

    private func say(_ text: String) {
        withAnimation(.snappy) { messages.append(ChatMessage(role: .coach, text: text)) }
    }

    private func answer(_ text: String) {
        withAnimation(.snappy) { messages.append(ChatMessage(role: .user, text: text)) }
    }

    /// F11: the slider's score sets Great / Okay / Tough for the rules.
    private func chooseEffort() {
        let score = Int(effort)
        feeling = Feeling(effort: score)
        answer("\(score) · \(Effort.label(score))")
        say("Was the pace comfortable? Could you have kept chatting?")
        step = .comfort
    }

    private func choose(comfortable value: Bool, typed: Bool = false) {
        comfortable = value
        if !typed { answer(value ? "Yes, comfortable" : "Not really") }
        say("Any trouble with knees or muscles?")
        step = .knee
    }

    private func choose(knee value: PainLevel, typed: Bool = false) {
        knee = value
        if !typed { answer(value.title) }
        guard let record = session.record else { return }
        // A manual run is compared with what the plan would have run, to spot an easier one.
        let planned = record.stageIndex == nil ? others.suggestion(structuralDeclinedAt: declinedAt).schedule : nil
        deviations = RunAnalysis.deviations(in: record, plannedSchedule: planned)
        questions = CheckInQuestions.select(deviations)
        askEasier = CheckInQuestions.asksEasier(deviations)
        askNext()
    }

    private func choose(reason: DeviationReason?, for deviation: Deviation, typed: Bool = false) {
        if !typed { answer(reason?.title ?? "Skip") }
        reasons[deviation.id] = reason
        askNext()
    }

    private func choose(keepEasier value: Bool?, typed: Bool = false) {
        if !typed, let value { answer(value ? "Keep it easier" : "One-off") }
        keepEasier = value
        askNext()
    }

    /// F12: a typed answer moves on as if nothing was tapped (comfortable, no issues, no reason,
    /// back to the plan), so it never changes the schedule. The coach reads it, and the note
    /// extractor may turn it into a note (an injury note only makes the plan more careful).
    private func sendTypedAnswer() {
        let text = typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedAnswer = ""
        typing = false
        typedAnswers.append(TypedAnswer(question: messages.last(where: { $0.role == .coach })?.text ?? "", text: text))
        answer(text)
        switch step {
        case .comfort: choose(comfortable: true, typed: true)
        case .knee: choose(knee: .none, typed: true)
        case .reason(let deviation): choose(reason: nil, for: deviation, typed: true)
        case .easier: choose(keepEasier: nil, typed: true)
        case .effort, .wrapUp, .chat: break
        }
    }

    /// At most two reason questions, then "One-off or keep it easier?" after an easier manual run.
    private func askNext() {
        if !questions.isEmpty {
            let next = questions.removeFirst()
            say(CheckInQuestions.prompt(for: next))
            step = .reason(next)
        } else if askEasier, let easier = deviations.first(where: { $0.kind == .easierThanPlan }) {
            askEasier = false
            say(CheckInQuestions.prompt(for: easier))
            step = .easier
        } else {
            finish()
        }
    }

    private func finish() {
        guard let record = session.record else { return }
        let score = Int(effort)
        var checkIn = CheckIn(feeling: feeling, comfortable: comfortable, knee: knee)
        checkIn.reasons = reasons.isEmpty ? nil : reasons
        checkIn.effort = score
        let typed = typedAnswers
        if !typed.isEmpty { checkIn.note = typed.map(\.text).joined(separator: " ") }
        session.checkIn = checkIn
        try? context.save()
        Store.noteKnee(knee, sessionID: session.id, in: context)
        EffortWriter.shared.save(score: score, for: record)
        step = .wrapUp
        Task {
            // Typed answers first: a note they open (an injury) can still make the plan more careful.
            if !typed.isEmpty {
                thinking = true
                for answer in typed { await extractNotes(from: answer.text, previous: answer.question) }
            }
            wrapUp(record: record, checkIn: checkIn)
        }
    }

    private func extractNotes(from text: String, previous: String?) async {
        let open = Store.openNotes(in: context).map { brief($0, askNow: false) }
        guard let extraction = await model.coach.extractNotes(from: text, previous: previous, openNotes: open) else { return }
        Store.apply(extraction, sessionID: session.id, in: context)
    }

    private func wrapUp(record: SessionRecord, checkIn: CheckIn) {
        // The rule layer decides; the coach explains.
        let suggestion = currentSuggestion()
        switch keepEasier {
        case true?: model.keepCurrent(insteadOf: suggestion, staying: true)
        case false?: model.apply(ActivePlan(suggestion))
        case nil: break
        }
        let notes = Store.openNotes(in: context)
        let asking = notes.filter { $0.followUp && $0.sessionID != session.id }
        let coachContext = CoachContext(
            record: record, checkIn: checkIn, suggestion: suggestion, deviations: deviations,
            notes: notes.map { brief($0, askNow: asking.contains($0)) },
            recentRuns: RunSummary.recent(others.compactMap { s in s.record.map { ($0, s.checkIn) } }, now: .now),
            keepEasier: keepEasier)
        Task {
            await coachReply(coachContext)
            // Follow-up notes are asked about once.
            for note in asking { note.followUp = false }
            try? context.save()
            if keepEasier == nil, model.followSilently(suggestion) {
                withAnimation(.snappy) { offer = suggestion }
            }
            var chat = coachContext
            chat.isWrapUp = false
            self.coachContext = chat
            step = .chat
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let coachContext else { return }
        let previous = messages.last(where: { $0.role == .coach })?.text
        draft = ""
        answer(text)
        if var checkIn = session.checkIn {
            checkIn.note = [checkIn.note, text].compactMap { $0 }.joined(separator: " ")
            session.checkIn = checkIn
            try? context.save()
        }
        Task { await coachReply(coachContext) }
        // A second, separate call: what's worth remembering from this message.
        Task {
            await extractNotes(from: text, previous: previous)
            refreshSuggestion()
        }
    }

    /// A newly noted injury can withdraw an early step-up that's on the table.
    private func refreshSuggestion() {
        guard var coachContext, keepEasier == nil else { return }
        let updated = currentSuggestion()
        guard updated.key != coachContext.suggestion.key else { return }
        coachContext.suggestion = updated
        self.coachContext = coachContext
        guard offer != nil else { return }
        let needsDecision = model.followSilently(updated)
        withAnimation(.snappy) { offer = needsDecision ? updated : nil }
    }

    private func coachReply(_ coachContext: CoachContext) async {
        thinking = true
        let reply = await model.coach.reply(context: coachContext, transcript: messages)
        thinking = false
        say(reply)
    }

    // MARK: Helpers

    /// All sessions except this one.
    private var others: [StoredSession] { sessions.filter { $0.id != session.id } }
    private var declinedAt: Date? { plans.first?.structuralDeclinedAt }

    private func currentSuggestion() -> Suggestion {
        let injury = Store.openNotes(in: context).contains { $0.kind == .injury }
        return sessions.suggestion(structuralDeclinedAt: declinedAt, hasOpenInjury: injury)
    }

    private func brief(_ note: CoachNote, askNow: Bool) -> NoteBrief {
        let days = Calendar.current.dateComponents([.day], from: note.createdAt, to: .now).day ?? 0
        return NoteBrief(id: note.shortID, kind: note.kind, text: note.text, ageDays: max(0, days), askNow: askNow)
    }

    // MARK: Input

    @ViewBuilder private var inputBar: some View {
        VStack(spacing: 10) {
            switch step {
            case .effort:
                EffortPicker(effort: $effort, onDone: chooseEffort)
            case .comfort:
                HStack(spacing: 8) {
                    Button("Yes, comfortable") { choose(comfortable: true) }
                        .buttonStyle(ReplyStyle(color: .brand)).accessibilityIdentifier("comfort-yes")
                    Button("Not really") { choose(comfortable: false) }
                        .buttonStyle(ReplyStyle(color: .warmColor)).accessibilityIdentifier("comfort-no")
                }
            case .knee:
                HStack(spacing: 8) {
                    ForEach(PainLevel.allCases, id: \.self) { value in
                        Button(value.title) { choose(knee: value) }
                            .buttonStyle(ReplyStyle(color: value.color))
                            .accessibilityIdentifier("knee-\(value.rawValue)")
                    }
                }
            case .reason(let deviation):
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(CheckInQuestions.reasons(for: deviation.kind), id: \.self) { reason in
                        Button(reason.title) { choose(reason: reason, for: deviation) }
                            .buttonStyle(ReplyStyle(color: reason.isPhysical ? .warmColor : .brand))
                            .accessibilityIdentifier("reason-\(reason.rawValue)")
                    }
                    Button("Skip") { choose(reason: nil, for: deviation) }
                        .buttonStyle(ReplyStyle(color: .secondary))
                        .accessibilityIdentifier("reason-skip")
                }
            case .easier:
                HStack(spacing: 8) {
                    Button("One-off") { choose(keepEasier: false) }
                        .buttonStyle(ReplyStyle(color: .brand)).accessibilityIdentifier("easier-oneoff")
                    Button("Keep it easier") { choose(keepEasier: true) }
                        .buttonStyle(ReplyStyle(color: .coolColor)).accessibilityIdentifier("easier-keep")
                }
            case .wrapUp:
                EmptyView()
            case .chat:
                HStack(spacing: 8) {
                    TextField("Anything to add or ask?", text: $draft, axis: .vertical)
                        .focused($typing)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityIdentifier("chatField")
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.headline.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Color.brand, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                    .accessibilityIdentifier("chatSend")
                }
            }
            switch step {
            case .comfort, .knee, .reason, .easier: typedAnswerRow
            case .effort, .wrapUp, .chat: EmptyView()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.pageBackground)
        .animation(.snappy, value: step)
    }

    /// F12: next to the answer buttons, room to say it in your own words.
    @ViewBuilder private var typedAnswerRow: some View {
        HStack(spacing: 8) {
            TextField("Or type your answer", text: $typedAnswer)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(sendTypedAnswer)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("typedAnswerField")
            if !typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendTypedAnswer) {
                    Image(systemName: "arrow.up").font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(Color.brand, in: Circle())
                }
                .accessibilityIdentifier("typedAnswerSend")
            }
        }
    }
}

/// F11: how hard did it feel, 1–10, starting at 5.
private struct EffortPicker: View {
    @Binding var effort: Double
    var onDone: () -> Void

    var body: some View {
        let score = Int(effort)
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(score)").font(.system(size: 34, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(color(score))
                    .contentTransition(.numericText())
                Text(Effort.label(score)).font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
            .animation(.snappy, value: score)
            Slider(value: $effort, in: Double(Effort.range.lowerBound)...Double(Effort.range.upperBound), step: 1) {
                Text("Effort")
            } minimumValueLabel: {
                Text("1").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("10").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .tint(color(score))
            .accessibilityIdentifier("effortSlider")
            Button("That's it", action: onDone)
                .buttonStyle(ReplyStyle(color: .brand))
                .accessibilityIdentifier("effortDone")
        }
    }

    private func color(_ score: Int) -> Color {
        switch Feeling(effort: score) {
        case .great: .brand
        case .okay: .warmColor
        case .tough: .heart
        }
    }
}

private struct ReplyStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 6)
            .background(color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .coach {
                TortoiseView().frame(width: 34).padding(.bottom, 2)
            } else {
                Spacer(minLength: 50)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(message.role == .user ? Color.brand : Color.cardBackground,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if message.role == .coach { Spacer(minLength: 30) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct TypingBubble: View {
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TortoiseView().frame(width: 34).padding(.bottom, 2)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(Color.secondary.opacity(0.6)).frame(width: 8, height: 8)
                        .offset(y: phase ? -3 : 3)
                        .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer()
        }
        .onAppear { phase = true }
    }
}
