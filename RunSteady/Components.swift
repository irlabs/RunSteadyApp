import RunSteadyKit
import SwiftUI

extension Color {
    static let pageBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let heart = Color(hex: 0xFF4D6A)
}

/// Flat rounded card: no shadows, no borders.
struct Card<Content: View>: View {
    var color: Color = .cardBackground
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.heavy)).kerning(0.8).foregroundStyle(color)
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var color: Color = .brand

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
    }
}

struct PillButtonStyle: ButtonStyle {
    var color: Color = .brand
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(filled ? .white : color)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(filled ? color : color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.subheadline.weight(.bold)).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.bold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TimelineLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(SegmentKind.allCases, id: \.self) { LegendDot(kind: $0) }
        }
    }
}

/// Schedule summary used on Today, in suggestions and in the chat.
struct ScheduleSummary: View {
    let schedule: Schedule
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(schedule.summary).font(.title3.weight(.bold))
            SegmentTimeline(schedule: schedule, height: 18)
            HStack {
                TimelineLegend()
                Spacer()
                Label("\(schedule.totalSeconds / 60) min", systemImage: "clock.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
        }
    }
}

extension Decision {
    var color: Color {
        switch self {
        case .start, .proceed, .advance, .maintain: .brand
        case .repeatSession, .repeatAfterGap: .warmColor
        case .stepBack, .stepBackAfterGap, .stepBackStructural: .coolColor
        }
    }

    var symbol: String {
        switch self {
        case .start: "play.fill"
        case .proceed: "checkmark"
        case .advance: "arrow.up.right"
        case .maintain: "equal"
        case .repeatSession, .repeatAfterGap: "arrow.triangle.2.circlepath"
        case .stepBack, .stepBackAfterGap, .stepBackStructural: "arrow.down.right"
        }
    }
}

extension Feeling {
    var symbol: String {
        switch self {
        case .great: "sun.max.fill"
        case .okay: "cloud.sun.fill"
        case .tough: "cloud.rain.fill"
        }
    }
}

extension PainLevel {
    var color: Color {
        switch self {
        case .none: .brand
        case .mild: .warmColor
        case .painful: .heart
        }
    }
}

extension SessionRecord {
    var title: String {
        guard let stageIndex, let sessionInStage else { return "My schedule" }
        return "Week \(stageIndex + 1) · Session \(sessionInStage)"
    }
}
