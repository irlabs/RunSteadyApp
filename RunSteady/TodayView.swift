import RunSteadyKit
import SwiftData
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]
    @Query private var plans: [StoredPlan]
    @State private var editing = false
    @State private var checkInSession: StoredSession?

    private var plan: ActivePlan { plans.first?.plan ?? .initial }
    private var suggestion: Suggestion { sessions.suggestion() }

    /// Where the user stands. A run that still awaits its check-in does not count yet.
    private var position: Suggestion {
        pending == nil ? suggestion : Array(sessions.dropFirst()).suggestion()
    }

    /// The latest run, if it still needs its check-in.
    private var pending: StoredSession? {
        guard let latest = sessions.first, latest.checkIn == nil,
              latest.startedAt > Date().addingTimeInterval(-3 * 86_400) else { return nil }
        return latest
    }

    /// A suggestion worth showing: differs from the active plan and was not dismissed.
    private var offer: Suggestion? {
        let s = suggestion
        guard pending == nil, ActivePlan(s) != plan, plans.first?.dismissedSuggestion != s.key else { return nil }
        return s
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                HeroCard(suggestion: position)
                if let pending { checkInCard(pending) }
                if let offer { SuggestionCard(suggestion: offer) }
                nextSessionCard
                weekStats
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.snappy, value: offer?.key)
            .animation(.snappy, value: pending?.id)
        }
        .background(Color.pageBackground)
        .sheet(isPresented: $editing) { ScheduleEditorView(plan: plan, suggestion: suggestion) }
        .sheet(item: $checkInSession) { CheckInView(session: $0) }
        .task(id: suggestion.key + "\(pending == nil)") { followPlanSilently() }
    }

    /// On the automatic plan, moving to the next session with identical intervals needs no decision.
    private func followPlanSilently() {
        let next = ActivePlan(suggestion)
        if pending == nil, !plan.isManual, next != plan, next.schedule == plan.schedule {
            model.apply(next)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text("Run Steady").font(.largeTitle.weight(.heavy))
            }
            Spacer()
            TortoiseView().frame(width: 76)
        }
        .padding(.top, 8)
    }

    private func checkInCard(_ session: StoredSession) -> some View {
        Card(color: .runColor) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How was your run?").font(.title3.weight(.bold))
                    Text("Three quick questions, then your next step.").font(.subheadline).opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            Button("Check in with Steady") { checkInSession = session }
                .buttonStyle(WhiteButtonStyle(textColor: .runColor))
                .accessibilityIdentifier("checkInButton")
        }
    }

    private var nextSessionCard: some View {
        Card {
            HStack {
                Eyebrow(text: "Next session")
                Spacer()
                if plan.isManual {
                    Chip(text: "Manual", symbol: "hand.raised.fill", color: .coolColor)
                } else {
                    Chip(text: "Plan", symbol: "sparkles", color: .brand)
                }
            }
            Text(plan.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScheduleSummary(schedule: plan.schedule)
            HStack(spacing: 10) {
                Label("Ready on your watch", systemImage: "applewatch")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    editing = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3").font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.brand.opacity(0.14), in: Capsule())
                }
                .accessibilityIdentifier("editScheduleButton")
            }
        }
    }

    private var weekStats: some View {
        let week = sessions.filter { $0.startedAt > Date().addingTimeInterval(-7 * 86_400) }.compactMap(\.record)
        let km = week.reduce(0) { $0 + $1.distanceMeters } / 1000
        let minutes = week.reduce(0) { $0 + $1.runSeconds } / 60
        return HStack(spacing: 10) {
            StatTile(title: "Runs this week", value: "\(week.count)", symbol: "calendar", color: .brand)
            StatTile(title: "Distance", value: String(format: "%.1f", km), unit: "km", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", color: .walkColor)
            StatTile(title: "Running", value: "\(minutes)", unit: "min", symbol: "figure.run", color: .runColor)
        }
    }
}

struct WhiteButtonStyle: ButtonStyle {
    let textColor: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Green progress card: the tortoise walks along the road to 5K.
struct HeroCard: View {
    let suggestion: Suggestion

    private var progress: Double {
        let total = Double(ProgressionPlan.fiveK.count * ProgressionPlan.sessionsPerStage)
        let done = Double(suggestion.stageIndex * ProgressionPlan.sessionsPerStage + suggestion.sessionInStage - 1)
        return min(1, done / total)
    }

    var body: some View {
        Card(color: .brand) {
            Eyebrow(text: "Your road to 5K", color: .white.opacity(0.8))
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(suggestion.stageIndex + 1)").font(.system(size: 40, weight: .heavy))
                Text("of \(ProgressionPlan.fiveK.count)").font(.title3.weight(.bold)).opacity(0.8)
                Spacer()
                Text("\(Int(progress * 100))%").font(.title3.weight(.heavy))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            .foregroundStyle(.white)
            Text("Session \(suggestion.sessionInStage) of \(ProgressionPlan.sessionsPerStage) · \(suggestion.stage.focus)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))

            GeometryReader { geo in
                let width = geo.size.width - 34
                ZStack(alignment: .bottomLeading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 10)
                    Capsule().fill(.white).frame(width: max(10, width * progress), height: 10)
                    HStack(spacing: 0) {
                        ForEach(1..<ProgressionPlan.fiveK.count, id: \.self) { index in
                            Spacer()
                            Circle().fill(Color.brandDeep.opacity(0.35)).frame(width: 4, height: 4)
                            if index == ProgressionPlan.fiveK.count - 1 { Spacer() }
                        }
                    }
                    .frame(width: width, height: 10)
                    TortoiseView(shell: .brandDeep, shellDark: Color(hex: 0x064A2D))
                        .frame(width: 50)
                        .offset(x: max(0, width * progress - 30), y: -12)
                    Image(systemName: "flag.checkered")
                        .font(.footnote.weight(.bold)).foregroundStyle(Color.brand)
                        .frame(width: 30, height: 30)
                        .background(.white, in: Circle())
                        .offset(x: width + 4, y: 10)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 62)
            .padding(.bottom, 10)
        }
    }
}

/// "After a run, the app suggests the next schedule, which the user can accept or ignore."
struct SuggestionCard: View {
    @EnvironmentObject private var model: AppModel
    let suggestion: Suggestion
    var onDecided: () -> Void = {}

    var body: some View {
        Card {
            HStack {
                Eyebrow(text: "Steady suggests")
                Spacer()
                Chip(text: suggestion.decision.title, symbol: suggestion.decision.symbol, color: suggestion.decision.color)
            }
            Text("Week \(suggestion.stageIndex + 1) · Session \(suggestion.sessionInStage)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScheduleSummary(schedule: suggestion.schedule)
            Text(suggestion.reason).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Keep mine") {
                    model.keepCurrent(insteadOf: suggestion)
                    onDecided()
                }
                .buttonStyle(PillButtonStyle(color: .secondary, filled: false))
                .accessibilityIdentifier("keepMineButton")
                Button("Use this") {
                    model.apply(ActivePlan(suggestion))
                    onDecided()
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("useSuggestionButton")
            }
        }
    }
}
