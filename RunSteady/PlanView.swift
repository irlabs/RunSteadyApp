import RunSteadyKit
import SwiftData
import SwiftUI

/// The default eight-week progression, with the user's position on it.
struct PlanView: View {
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]
    @Query private var plans: [StoredPlan]
    @Query(filter: #Predicate<CoachNote> { $0.isOpen }) private var openNotes: [CoachNote]

    var body: some View {
        let suggestion = sessions.suggestion(structuralDeclinedAt: plans.first?.structuralDeclinedAt,
                                             hasOpenInjury: openNotes.contains { $0.kind == .injury }).position
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The plan").font(.largeTitle.weight(.heavy))
                    Text("Eight gentle weeks to 30 minutes of running. Three sessions a week, rest days in between.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 8).padding(.bottom, 18)

                if let manual = plans.first?.plan, manual.isManual {
                    Card(color: Color.coolColor.opacity(0.14)) {
                        HStack {
                            Eyebrow(text: "Your own schedule", color: .coolColor)
                            Spacer()
                            Chip(text: "Manual", symbol: "hand.raised.fill", color: .coolColor)
                        }
                        ScheduleSummary(schedule: manual.schedule)
                        Text("Your next run uses this instead of the plan. The plan stays at week \(suggestion.stageIndex + 1), "
                             + "session \(suggestion.sessionInStage) until you switch back.")
                            .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("manualScheduleCard")
                    .padding(.bottom, 18)
                }

                ForEach(Array(ProgressionPlan.fiveK.enumerated()), id: \.offset) { index, stage in
                    StageRow(stage: stage, state: state(index, suggestion.stageIndex),
                             session: suggestion.sessionInStage, isLast: index == ProgressionPlan.fiveK.count - 1)
                }

                Card(color: Color.coolColor.opacity(0.14)) {
                    Label("Later: a 10K phase", systemImage: "mountain.2.fill")
                        .font(.headline).foregroundStyle(Color.coolColor)
                    Text("Only once 5K feels easy. No rush.").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Color.pageBackground)
    }

    private func state(_ index: Int, _ current: Int) -> StageRow.State {
        index < current ? .done : index == current ? .current : .upcoming
    }
}

private struct StageRow: View {
    enum State { case done, current, upcoming }
    let stage: Stage
    let state: State
    let session: Int
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(state == .upcoming ? Color.secondary.opacity(0.18) : Color.brand)
                    if state == .done {
                        Image(systemName: "checkmark").font(.footnote.weight(.heavy)).foregroundStyle(.white)
                    } else {
                        Text("\(stage.week)").font(.subheadline.weight(.heavy))
                            .foregroundStyle(state == .current ? .white : .secondary)
                    }
                }
                .frame(width: 34, height: 34)
                if !isLast {
                    Rectangle().fill(state == .done ? Color.brand : Color.secondary.opacity(0.18)).frame(width: 4)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(stage.focus).font(.headline)
                    Spacer()
                    if state == .current {
                        Chip(text: "Session \(session) of 3", symbol: "location.fill")
                    }
                }
                Text(stage.schedule.summary).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                SegmentTimeline(schedule: stage.schedule, height: 10)
            }
            .padding(14)
            .background(state == .current ? Color.brand.opacity(0.13) : Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(state == .upcoming ? 0.85 : 1)
            .padding(.bottom, 10)
        }
    }
}
