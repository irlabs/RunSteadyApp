import RunSteadyKit
import SwiftData
import SwiftUI

/// Post-run check-in as a short chat. The three structured answers feed the rule layer;
/// the coach (language model or scripted fallback) only words the wrap-up and answers follow-ups.
struct CheckInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]
    @Query private var plans: [StoredPlan]
    let session: StoredSession

    private enum Step { case feeling, comfort, knee, wrapUp, chat }
    @State private var step = Step.feeling
    @State private var messages: [ChatMessage] = []
    @State private var feeling = Feeling.okay
    @State private var comfortable = true
    @State private var thinking = false
    @State private var draft = ""
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
        var intro = "Welcome back! \(record.roundsDone) rounds, \(Format.km(meters: record.distanceMeters)) km in \(Format.clock(record.duration))."
        if record.extraRounds > 0 { intro += " That's \(record.extraRounds) more than planned." }
        say(intro)
        say("How did it go overall?")
    }

    private func say(_ text: String) {
        withAnimation(.snappy) { messages.append(ChatMessage(role: .coach, text: text)) }
    }

    private func answer(_ text: String) {
        withAnimation(.snappy) { messages.append(ChatMessage(role: .user, text: text)) }
    }

    private func choose(feeling value: Feeling) {
        feeling = value
        answer(value.title)
        say("Was the pace comfortable? Could you have kept chatting?")
        step = .comfort
    }

    private func choose(comfortable value: Bool) {
        comfortable = value
        answer(value ? "Yes, comfortable" : "Not really")
        say("Any trouble with knees or muscles?")
        step = .knee
    }

    private func choose(knee: PainLevel) {
        answer(knee.title)
        guard let record = session.record else { return }
        let checkIn = CheckIn(feeling: feeling, comfortable: comfortable, knee: knee)
        session.checkIn = checkIn
        try? context.save()

        // The rule layer decides; the coach explains.
        let suggestion = sessions.suggestion()
        let coachContext = CoachContext(record: record, checkIn: checkIn, suggestion: suggestion)
        self.coachContext = coachContext
        step = .wrapUp
        Task {
            await coachReply(coachContext)
            let current = plans.first?.plan ?? .initial
            if ActivePlan(suggestion) != current {
                if !current.isManual, suggestion.schedule == current.schedule {
                    model.apply(ActivePlan(suggestion))
                } else {
                    withAnimation(.snappy) { offer = suggestion }
                }
            }
            step = .chat
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let coachContext else { return }
        draft = ""
        answer(text)
        if var checkIn = session.checkIn {
            checkIn.note = [checkIn.note, text].compactMap { $0 }.joined(separator: " ")
            session.checkIn = checkIn
            try? context.save()
        }
        Task { await coachReply(coachContext) }
    }

    private func coachReply(_ coachContext: CoachContext) async {
        thinking = true
        let reply = await model.coach.reply(context: coachContext, transcript: messages)
        thinking = false
        say(reply)
    }

    // MARK: Input

    @ViewBuilder private var inputBar: some View {
        VStack(spacing: 10) {
            switch step {
            case .feeling:
                HStack(spacing: 8) {
                    ForEach(Feeling.allCases, id: \.self) { value in
                        Button { choose(feeling: value) } label: { Label(value.title, systemImage: value.symbol) }
                            .buttonStyle(ReplyStyle(color: value == .tough ? .warmColor : .brand))
                            .accessibilityIdentifier("feeling-\(value.rawValue)")
                    }
                }
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
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.pageBackground)
        .animation(.snappy, value: step)
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
