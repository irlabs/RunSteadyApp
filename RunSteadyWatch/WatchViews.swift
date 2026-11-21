import RunSteadyKit
import SwiftUI

// MARK: - Start

struct StartView: View {
    @EnvironmentObject private var manager: WorkoutManager
    @AppStorage("announceKm") private var announceKm = true
    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TortoiseView().frame(width: 46)
                        .contentShape(Rectangle())
                        // Hidden diagnostics for device checks.
                        .onLongPressGesture { showDiagnostics = true }
                        .accessibilityIdentifier("tortoise")
                        .accessibilityAddTraits(.isButton)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Run Steady").font(.headline)
                        Text(manager.plan.title).font(.caption2).foregroundStyle(Color.brandSoft)
                    }
                }

                if let back = manager.welcomeBack {
                    // F15: the watch stepped back on its own after a break.
                    Text("Welcome back, it's been \(GapRule.describe(days: back.gapDays)) → Week \((back.plan.stageIndex ?? 0) + 1)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.warmColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("welcomeBack")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.plan.schedule.summary)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    SegmentTimeline(schedule: manager.plan.schedule, height: 10)
                    Text("≈ \(manager.plan.schedule.totalSeconds / 60) min")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("startDuration")
                }
                .padding(10)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button { manager.start() } label: {
                    Label("Start", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(color: .brand))
                .accessibilityIdentifier("startButton")

                Toggle(isOn: $announceKm) {
                    Label("Km voice", systemImage: "speaker.wave.2.fill").font(.footnote)
                }
                .tint(.brand)
                .padding(.top, 2)

                Text(Connectivity.ownVersion.label)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("watchVersion")
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack { WatchDiagnosticsView() }
        }
    }
}

// MARK: - Workout

struct WorkoutView: View {
    @EnvironmentObject private var manager: WorkoutManager
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            ControlsPage(page: $page).tag(0)
            TimerPage().tag(1)
        }
        .tabViewStyle(.page)
    }
}

private struct TimerPage: View {
    @EnvironmentObject private var manager: WorkoutManager

    var body: some View {
        if let engine = manager.engine {
            let segment = engine.current
            let color = segment.kind.color
            VStack(spacing: 3) {
                HStack {
                    Label(segment.kind.title.uppercased(), systemImage: segment.kind.symbol)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color, in: Capsule())
                    Spacer()
                    Text(roundText(engine))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(engine.extraRounds > 0 ? Color.warmColor : .secondary)
                        .accessibilityIdentifier("roundLabel")
                }

                // F2: counts down to 0:00, then up from +0:01 in the segment colour.
                Text(Format.segmentClock(target: segment.target, elapsed: segment.elapsed))
                    .font(.system(size: 50, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                    .foregroundStyle(segment.isOverTarget ? color : .white)
                    .opacity(engine.isPaused ? 0.4 : 1)
                    .frame(height: 50)
                    .accessibilityIdentifier("segmentClock")

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(color).frame(width: max(5, geo.size.width * segment.progress))
                    }
                }
                .frame(height: 5)

                Text(statusText(engine))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(segment.isOverTarget ? color : .secondary)
                    .accessibilityIdentifier("statusLabel")

                // F8: total time · heart rate (with zone) · pace while running, distance while walking.
                HStack(spacing: 0) {
                    Metric(value: Format.clock(engine.totalElapsed), unit: "total")
                    Metric(value: manager.heartRate.map { "\(Int($0))" } ?? "––",
                           unit: manager.heartRateZone.map { "bpm · Z\($0)" } ?? "bpm",
                           dot: manager.heartRateZone.map(Color.zone))
                        .accessibilityIdentifier("heartRateMetric")
                    switch segment.kind {
                    case .run, .warmUp: Metric(value: Format.pace(secondsPerKm: manager.pace), unit: "min/km")
                    case .walk, .coolDown: Metric(value: Format.km(meters: manager.distance), unit: "km")
                    }
                }
                .padding(.top, 1)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    if engine.isInFinalPlannedRoundOrBeyond {
                        Button { manager.beginCoolDown() } label: {
                            Image(systemName: SegmentKind.coolDown.symbol).font(.headline)
                        }
                        .buttonStyle(FlatButtonStyle(color: .coolColor))
                        .frame(width: 48)
                        .accessibilityIdentifier("coolDownButton")
                        .accessibilityLabel("Cool-down")
                    }
                    Button { manager.next() } label: {
                        HStack(spacing: 4) {
                            Text(nextTitle(engine))
                            Image(systemName: "chevron.right.2").font(.caption.bold())
                        }
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FlatButtonStyle(color: nextColor(engine)))
                    .accessibilityIdentifier("nextButton")
                }
            }
            .padding(.horizontal, 2)
            .background(
                color.opacity(segment.isOverTarget ? 0.2 : 0)
                    .animation(.easeInOut(duration: 0.3), value: segment.isOverTarget)
                    .ignoresSafeArea()
            )
        }
    }

    private func roundText(_ engine: WorkoutEngine) -> String {
        let round = engine.current.round
        guard round > 0 else { return engine.current.kind == .warmUp ? "Get ready" : "Almost done" }
        return engine.extraRounds > 0
            ? "Round \(round) · +\(engine.extraRounds) extra"
            : "Round \(round) of \(engine.schedule.rounds)"
    }

    private func statusText(_ engine: WorkoutEngine) -> String {
        if engine.isPaused { return "Paused" }
        let segment = engine.current
        return segment.isOverTarget ? "Over target · tap next" : "target \(Format.clock(segment.target))"
    }

    private func nextKind(_ engine: WorkoutEngine) -> SegmentKind? {
        switch engine.current.kind {
        case .warmUp, .walk: .run
        case .run: engine.schedule.walk > 0 ? .walk : .run
        case .coolDown: nil
        }
    }

    private func nextTitle(_ engine: WorkoutEngine) -> String {
        if engine.current.kind == .warmUp { return "Start Run" }
        return nextKind(engine)?.title ?? "Finish"
    }

    private func nextColor(_ engine: WorkoutEngine) -> Color {
        nextKind(engine)?.color ?? .brand
    }
}

private struct Metric: View {
    let value: String
    let unit: String
    /// F9: heart rate zone colour.
    var dot: Color?

    var body: some View {
        VStack(spacing: -1) {
            HStack(spacing: 3) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(unit).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ControlsPage: View {
    @EnvironmentObject private var manager: WorkoutManager
    @AppStorage("announceKm") private var announceKm = true
    @Binding var page: Int

    var body: some View {
        let paused = manager.engine?.isPaused ?? false
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    manager.togglePause()
                    page = 1
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: paused ? "play.fill" : "pause.fill").font(.title3)
                        Text(paused ? "Resume" : "Pause").font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(color: .warmColor, height: 58))
                .accessibilityIdentifier("pauseButton")

                Button { manager.finish() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "flag.checkered").font(.title3)
                        Text("Finish").font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(color: Color(hex: 0xFF4D6A), height: 58))
                .accessibilityIdentifier("finishButton")
            }

            Toggle(isOn: $announceKm) {
                Label("Km voice", systemImage: "speaker.wave.2.fill").font(.footnote)
            }
            .tint(.brand)
            .padding(.horizontal, 4)

            Text("Total \(Format.clock(manager.engine?.totalElapsed ?? 0))")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

// MARK: - Summary

struct SummaryView: View {
    @EnvironmentObject private var manager: WorkoutManager

    var body: some View {
        ScrollView {
            if let record = manager.lastRecord {
                VStack(spacing: 8) {
                    TortoiseView().frame(width: 64)
                    Text("Steady does it!").font(.headline)
                    SegmentTimeline(records: record.segments, height: 10)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
                        SummaryTile(title: "Time", value: Format.clock(record.duration), color: .brand)
                        SummaryTile(title: "Distance", value: Format.km(meters: record.distanceMeters) + " km", color: .walkColor)
                        SummaryTile(title: "Pace /km", value: Format.pace(secondsPerKm: record.paceSecondsPerKm), color: .runColor)
                        SummaryTile(title: "Avg heart", value: record.averageHeartRate.map { "\(Int($0))" } ?? "––", color: Color(hex: 0xFF4D6A))
                        SummaryTile(title: "Rounds", value: record.extraRounds > 0 ? "\(record.roundsDone) (+\(record.extraRounds))" : "\(record.roundsDone)", color: .warmColor)
                        SummaryTile(title: "Overrun", value: "+" + Format.clock(record.totalOverrun), color: .coolColor)
                    }

                    Label(manager.savedToHealth ? "Saved to Apple Health" : "Simulated run · not saved to Health",
                          systemImage: manager.savedToHealth ? "heart.fill" : "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)

                    Text("Check in on your iPhone when you're home.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    Button { manager.dismissSummary() } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FlatButtonStyle(color: .brand))
                    .accessibilityIdentifier("doneButton")
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 17, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Flat button

struct FlatButtonStyle: ButtonStyle {
    let color: Color
    var height: CGFloat = 42

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
