import RunSteadyKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    static let brand = Color(hex: 0x17A866)
    static let brandDeep = Color(hex: 0x0B6B42)
    static let brandSoft = Color(hex: 0x8FE3B4)
    static let runColor = Color(hex: 0xFF6A45)
    static let walkColor = Color(hex: 0x1FB3D6)
    static let warmColor = Color(hex: 0xFFAE1A)
    static let coolColor = Color(hex: 0x7B6CFF)
    static let ink = Color(hex: 0x10231A)

    /// Heart rate zone 1–5: easy blues and greens up to warm orange and red.
    static func zone(_ zone: Int) -> Color {
        switch zone {
        case ...1: Color(hex: 0x9AA8B8)
        case 2: .walkColor
        case 3: .brand
        case 4: .warmColor
        default: Color(hex: 0xFF4D6A)
        }
    }
}

extension SegmentKind {
    var color: Color {
        switch self {
        case .warmUp: .warmColor
        case .run: .runColor
        case .walk: .walkColor
        case .coolDown: .coolColor
        }
    }

    var symbol: String {
        switch self {
        case .warmUp: "flame.fill"
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .coolDown: "snowflake"
        }
    }
}

/// Proportional strip of coloured blocks, one per segment.
struct SegmentTimeline: View {
    struct Block: Identifiable {
        let id: Int
        let kind: SegmentKind
        let seconds: Int
    }

    let blocks: [Block]
    var height: CGFloat = 14
    var spacing: CGFloat = 2

    init(schedule: Schedule, height: CGFloat = 14) {
        blocks = schedule.plannedSegments.enumerated().map { Block(id: $0.offset, kind: $0.element.kind, seconds: $0.element.target) }
        self.height = height
    }

    init(records: [SegmentRecord], height: CGFloat = 14) {
        blocks = records.enumerated().map { Block(id: $0.offset, kind: $0.element.kind, seconds: $0.element.actual) }
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(1, blocks.reduce(0) { $0 + $1.seconds }))
            let usable = max(0, geo.size.width - spacing * CGFloat(max(0, blocks.count - 1)))
            HStack(spacing: spacing) {
                ForEach(blocks) { block in
                    RoundedRectangle(cornerRadius: height / 3.5, style: .continuous)
                        .fill(block.kind.color)
                        .frame(width: max(1.5, usable * CGFloat(block.seconds) / total))
                }
            }
        }
        .frame(height: height)
    }
}

/// Small coloured legend dot + label.
struct LegendDot: View {
    let kind: SegmentKind
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(kind.color).frame(width: 8, height: 8)
            Text(kind.title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
