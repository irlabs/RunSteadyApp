import RunSteadyKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if sessions.isEmpty {
                        ContentUnavailableView("No runs yet", systemImage: "figure.run",
                                               description: Text("Finish a session on your watch and it shows up here."))
                            .padding(.top, 80)
                    }
                    ForEach(sessions) { session in
                        if let record = session.record {
                            NavigationLink(value: session.id) {
                                SessionRow(record: record, checkIn: session.checkIn)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sessionRow")
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color.pageBackground)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CoachNotesView() } label: { Label("Coach notes", systemImage: "note.text") }
                        .accessibilityIdentifier("coachNotesButton")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let session = sessions.first(where: { $0.id == id }) {
                    SessionDetailView(session: session)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let record: SessionRecord
    let checkIn: CheckIn?

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.startedAt.formatted(.dateTime.weekday(.wide).day().month())).font(.headline)
                    Text(record.title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer()
                if let checkIn {
                    Chip(text: checkIn.feeling.title, symbol: checkIn.feeling.symbol,
                         color: checkIn.knee == .none ? .brand : checkIn.knee.color)
                } else {
                    Chip(text: "Check in", symbol: "bubble.left.fill", color: .runColor)
                }
            }
            SegmentTimeline(records: record.segments, height: 12)
            HStack(spacing: 18) {
                metric(Format.km(meters: record.distanceMeters), "km")
                metric(Format.pace(secondsPerKm: record.paceSecondsPerKm), "min/km")
                metric(Format.clock(record.duration), "time")
                Spacer()
                if record.totalOverrun > 0 {
                    Text("+\(Format.clock(record.totalOverrun))").font(.footnote.weight(.bold)).foregroundStyle(Color.runColor)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
    }

    private func metric(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline).monospacedDigit()
            Text(unit).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

struct SessionDetailView: View {
    let session: StoredSession
    @State private var checkingIn = false

    var body: some View {
        ScrollView {
            if let record = session.record {
                VStack(spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        StatTile(title: "Time", value: Format.clock(record.duration), symbol: "stopwatch.fill", color: .brand)
                        StatTile(title: "Distance", value: Format.km(meters: record.distanceMeters), unit: "km", symbol: "map.fill", color: .walkColor)
                        StatTile(title: "Pace", value: Format.pace(secondsPerKm: record.paceSecondsPerKm), unit: "/km", symbol: "speedometer", color: .runColor)
                        StatTile(title: "Avg heart rate", value: record.averageHeartRate.map { "\(Int($0))" } ?? "––", unit: "bpm", symbol: "heart.fill", color: .heart)
                        StatTile(title: record.extraRounds > 0 ? "Rounds (+\(record.extraRounds) extra)" : "Rounds", value: "\(record.roundsDone)", unit: "of \(record.schedule.rounds)", symbol: "repeat", color: .warmColor)
                        StatTile(title: "Over target", value: "+" + Format.clock(record.totalOverrun), symbol: "timer", color: .coolColor)
                    }

                    Card {
                        Eyebrow(text: "Segments · actual vs target")
                        let longest = max(1, record.segments.map { max($0.actual, $0.target) }.max() ?? 1)
                        VStack(spacing: 9) {
                            ForEach(record.segments) { segment in
                                SegmentBar(segment: segment, longest: longest, extra: segment.round > record.schedule.rounds)
                            }
                        }
                    }

                    checkInCard
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Color.pageBackground)
        .navigationTitle(session.record?.startedAt.formatted(.dateTime.weekday(.wide).day().month()) ?? "Run")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $checkingIn) { CheckInView(session: session) }
    }

    @ViewBuilder private var checkInCard: some View {
        if let checkIn = session.checkIn {
            Card {
                Eyebrow(text: "Check-in")
                HStack(spacing: 8) {
                    Chip(text: checkIn.feeling.title, symbol: checkIn.feeling.symbol)
                    Chip(text: checkIn.comfortable ? "Comfortable" : "Not comfortable", symbol: "lungs.fill",
                         color: checkIn.comfortable ? .walkColor : .warmColor)
                    Chip(text: checkIn.knee.title, symbol: "figure.walk", color: checkIn.knee.color)
                }
                if let note = checkIn.note, !note.isEmpty {
                    Text("“\(note)”").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } else {
            Card(color: .runColor) {
                Text("No check-in yet").font(.headline).foregroundStyle(.white)
                Button("Check in with Steady") { checkingIn = true }
                    .buttonStyle(WhiteButtonStyle(textColor: .runColor))
            }
        }
    }
}

/// One row: pale bar = target, solid bar = actual; anything past the target is drawn striped-dark.
private struct SegmentBar: View {
    let segment: SegmentRecord
    let longest: Int
    let extra: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: segment.kind.symbol)
                .font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(segment.kind.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(label).font(.footnote.weight(.semibold)).frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                let unit = geo.size.width / CGFloat(longest)
                ZStack(alignment: .leading) {
                    Capsule().fill(segment.kind.color.opacity(0.22)).frame(width: unit * CGFloat(segment.target))
                    Capsule().fill(segment.kind.color).frame(width: max(4, unit * CGFloat(min(segment.actual, segment.target))))
                    if segment.overrun > 0 {
                        Capsule().fill(Color.ink.opacity(0.75))
                            .frame(width: max(4, unit * CGFloat(segment.overrun)))
                            .offset(x: unit * CGFloat(segment.target) + 2)
                    }
                }
            }
            .frame(height: 10)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.clock(segment.actual)).font(.footnote.weight(.bold)).monospacedDigit()
                if segment.overrun > 0 {
                    Text("+\(Format.clock(segment.overrun))").font(.caption2.weight(.bold)).foregroundStyle(Color.runColor).monospacedDigit()
                }
            }
            .frame(width: 44, alignment: .trailing)
        }
    }

    private var label: String {
        segment.round > 0 ? "\(segment.kind.title) \(segment.round)\(extra ? "+" : "")" : segment.kind.title
    }
}
