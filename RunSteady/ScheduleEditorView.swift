import RunSteadyKit
import SwiftUI

/// Full manual control. Saving here creates a manual schedule, which overrides the automatic plan.
struct ScheduleEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let plan: ActivePlan
    let suggestion: Suggestion
    @State private var schedule: Schedule

    init(plan: ActivePlan, suggestion: Suggestion) {
        self.plan = plan
        self.suggestion = suggestion
        _schedule = State(initialValue: plan.schedule)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        Eyebrow(text: "Preview")
                        ScheduleSummary(schedule: schedule)
                            .animation(.snappy, value: schedule)
                    }

                    VStack(spacing: 2) {
                        StepRow(kind: .warmUp, title: "Warm-up", value: Format.minutes(schedule.warmUp), id: "warmUp",
                                onMinus: { schedule.warmUp = max(0, schedule.warmUp - 60) },
                                onPlus: { schedule.warmUp = min(900, schedule.warmUp + 60) })
                        StepRow(kind: .run, title: "Run", value: Format.minutes(schedule.run), id: "run",
                                onMinus: { schedule.run = max(30, schedule.run - 30) },
                                onPlus: { schedule.run = min(3600, schedule.run + 30) })
                        StepRow(kind: .walk, title: "Walk", value: schedule.walk == 0 ? "None" : Format.minutes(schedule.walk), id: "walk",
                                onMinus: { schedule.walk = max(0, schedule.walk - 30) },
                                onPlus: { schedule.walk = min(600, schedule.walk + 30) })
                        StepRow(kind: nil, title: "Rounds", value: "\(schedule.rounds) ×", id: "rounds",
                                onMinus: { schedule.rounds = max(1, schedule.rounds - 1) },
                                onPlus: { schedule.rounds = min(15, schedule.rounds + 1) })
                        StepRow(kind: .coolDown, title: "Cool-down", value: Format.minutes(schedule.coolDown), id: "coolDown",
                                onMinus: { schedule.coolDown = max(0, schedule.coolDown - 60) },
                                onPlus: { schedule.coolDown = min(900, schedule.coolDown + 60) })
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                    Label("Your own schedule always overrides the automatic plan.", systemImage: "hand.raised.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)

                    Button("Save as my schedule") {
                        var mine = schedule
                        mine.name = "My schedule"
                        model.apply(ActivePlan(schedule: mine))
                        dismiss()
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(schedule == plan.schedule)
                    .opacity(schedule == plan.schedule ? 0.45 : 1)
                    .accessibilityIdentifier("saveScheduleButton")

                    if plan.isManual {
                        Button("Back to the automatic plan") {
                            model.apply(ActivePlan(suggestion))
                            dismiss()
                        }
                        .buttonStyle(PillButtonStyle(color: .coolColor, filled: false))
                        .accessibilityIdentifier("backToPlanButton")
                    }
                }
                .padding(16)
            }
            .background(Color.pageBackground)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .fontDesign(.rounded)
    }
}

private struct StepRow: View {
    let kind: SegmentKind?
    let title: String
    let value: String
    let id: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    private var color: Color { kind?.color ?? .brand }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind?.symbol ?? "repeat")
                .font(.headline).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.bold)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            stepButton("minus", action: onMinus).accessibilityIdentifier(id + "Minus")
            stepButton("plus", action: onPlus).accessibilityIdentifier(id + "Plus")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.cardBackground)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol).font(.headline.weight(.bold)).foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: value)
    }
}
