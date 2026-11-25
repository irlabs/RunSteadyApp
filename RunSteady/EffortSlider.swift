import RunSteadyKit
import SwiftUI

/// G5: how hard did it feel, 1–10. Starts empty: only a drag sets a value (a tap alone does nothing),
/// the number and label follow the finger, and "Next" appears once it has been moved.
struct EffortPicker: View {
    @Binding var effort: Int?
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let score = effort {
                    Text("\(score)").font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Self.color(score))
                        .contentTransition(.numericText())
                    Text(Effort.label(score)).font(.headline).foregroundStyle(.secondary)
                } else {
                    Label("Slide to rate your effort", systemImage: "hand.point.up.left.fill")
                        .font(.headline).foregroundStyle(.secondary)
                        .frame(height: 41)
                }
                Spacer()
            }
            .animation(.snappy, value: effort)
            EffortTrack(value: $effort)
            if effort != nil {
                Button("Next", action: onDone)
                    .buttonStyle(ReplyStyle(color: .brand))
                    .accessibilityIdentifier("effortDone")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy, value: effort == nil)
    }

    static func color(_ score: Int) -> Color {
        switch Feeling(effort: score) {
        case .great: .brand
        case .okay: .warmColor
        case .tough: .heart
        }
    }
}

/// The track: ten tick marks, a fill and a thumb once there is a value, a dashed ghost thumb before.
private struct EffortTrack: View {
    @Binding var value: Int?
    private let thumb: CGFloat = 28
    private let range = Effort.range

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill)).frame(height: 8)
                    .padding(.horizontal, thumb / 2)
                HStack(spacing: 0) {
                    ForEach(range, id: \.self) { tick in
                        Circle().fill(Color.secondary.opacity(0.35)).frame(width: 4, height: 4)
                        if tick < range.upperBound { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, thumb / 2 - 2)
                if let value {
                    let x = position(of: value, usable: usable)
                    Capsule().fill(EffortPicker.color(value))
                        .frame(width: x + thumb / 2, height: 8)
                    Circle().fill(.white)
                        .overlay(Circle().strokeBorder(EffortPicker.color(value), lineWidth: 3))
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .offset(x: x)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: thumb, height: thumb)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary))
                        .offset(x: usable / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // A minimum distance, so a tap alone sets nothing.
            .gesture(DragGesture(minimumDistance: 6).onChanged { drag in
                value = score(at: drag.location.x - thumb / 2, usable: usable)
            })
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("Effort")
        .accessibilityValue(value.map { "\($0), \(Effort.label($0))" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            let current = value ?? (range.lowerBound + range.upperBound) / 2
            switch direction {
            case .increment: value = min(range.upperBound, current + 1)
            case .decrement: value = max(range.lowerBound, current - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("effortSlider")
    }

    private func position(of score: Int, usable: CGFloat) -> CGFloat {
        usable * CGFloat(score - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }

    private func score(at x: CGFloat, usable: CGFloat) -> Int {
        let fraction = min(1, max(0, x / usable))
        return range.lowerBound + Int((fraction * CGFloat(range.upperBound - range.lowerBound)).rounded())
    }
}
