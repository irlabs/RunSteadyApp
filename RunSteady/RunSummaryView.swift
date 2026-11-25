import RunSteadyKit
import SwiftData
import SwiftUI

/// G4: opened full screen by tapping the check-in notification, over whatever tab was open.
/// A summary of that run, then the check-in in the same cover (closing it closes both).
struct RunSummaryCover: View {
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [StoredSession]
    @State private var checkingIn = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
        _sessions = Query(filter: #Predicate<StoredSession> { $0.id == sessionID })
    }

    var body: some View {
        if checkingIn, let session = sessions.first {
            CheckInView(session: session)
        } else {
            NavigationStack {
                ScrollView {
                    if let session = sessions.first, let record = session.record {
                        summary(session, record)
                    } else {
                        ContentUnavailableView("Run not found", systemImage: "figure.run",
                                               description: Text("It may not have reached this phone yet."))
                            .padding(.top, 80)
                    }
                }
                .background(Color.pageBackground)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.heavy)).foregroundStyle(.primary)
                                .frame(width: 34, height: 34)
                                .background(Color(.tertiarySystemFill), in: Circle())
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("summaryClose")
                    }
                }
            }
            .fontDesign(.rounded)
        }
    }

    private func summary(_ session: StoredSession, _ record: SessionRecord) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                TortoiseView().frame(width: 92)
                Text("Steady does it!").font(.largeTitle.weight(.heavy))
                Text("\(record.startedAt.formatted(.dateTime.weekday(.wide).hour().minute())) · \(record.title)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Card {
                Eyebrow(text: record.schedule.summary)
                SegmentTimeline(records: record.segments, height: 16)
                TimelineLegend()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                StatTile(title: "Time", value: Format.clock(record.duration), symbol: "stopwatch.fill", color: .brand)
                StatTile(title: "Distance", value: Format.km(meters: record.distanceMeters), unit: "km",
                         symbol: "map.fill", color: .walkColor)
                StatTile(title: "Pace", value: Format.pace(secondsPerKm: record.paceSecondsPerKm), unit: "/km",
                         symbol: "speedometer", color: .runColor)
                StatTile(title: "Avg heart rate", value: record.averageHeartRate.map { "\(Int($0))" } ?? "––",
                         unit: "bpm", symbol: "heart.fill", color: .heart)
                StatTile(title: record.extraRounds > 0 ? "Rounds (+\(record.extraRounds) extra)" : "Rounds",
                         value: "\(record.roundsDone)", unit: "of \(record.schedule.rounds)", symbol: "repeat", color: .warmColor)
                StatTile(title: "Running", value: "\(record.runSeconds / 60)", unit: "min", symbol: "figure.run",
                         color: .coolColor)
            }

            if session.checkIn == nil {
                Button("Start check-in") { checkingIn = true }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("startCheckInButton")
                Text("Three quick questions, then your next step.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Open the check-in") { checkingIn = true }
                    .buttonStyle(PillButtonStyle.secondary)
                    .accessibilityIdentifier("startCheckInButton")
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 24)
    }
}
