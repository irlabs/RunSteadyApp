import SwiftUI

/// Steady, the mascot: a flat tortoise with a coral sweatband. Drawn in a 100 × 78 design space.
struct TortoiseView: View {
    var shell: Color = .brand
    var shellDark: Color = .brandDeep
    var skin: Color = Color(hex: 0xB9E86B)
    var skinDark: Color = Color(hex: 0x8CCB45)
    var band: Color = .runColor

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 100, size.height / 78)
            ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 78 * s) / 2)
            ctx.scaleBy(x: s, y: s)

            // Tail
            var tail = Path()
            tail.move(to: CGPoint(x: 10, y: 52))
            tail.addLine(to: CGPoint(x: 1, y: 58))
            tail.addLine(to: CGPoint(x: 12, y: 60))
            tail.closeSubpath()
            ctx.fill(tail, with: .color(skinDark))

            // Legs
            for x in [18.0, 52.0] {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: 54, width: 15, height: 22), cornerRadius: 6), with: .color(skinDark))
            }

            // Neck + head
            ctx.fill(Path(roundedRect: CGRect(x: 64, y: 34, width: 22, height: 18), cornerRadius: 8), with: .color(skin))
            ctx.fill(Path(ellipseIn: CGRect(x: 72, y: 18, width: 27, height: 25)), with: .color(skin))

            // Sweatband
            var bandPath = Path()
            bandPath.move(to: CGPoint(x: 73.5, y: 25))
            bandPath.addQuadCurve(to: CGPoint(x: 97.5, y: 24), control: CGPoint(x: 85, y: 15))
            ctx.stroke(bandPath, with: .color(band), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

            // Eye + smile
            ctx.fill(Path(ellipseIn: CGRect(x: 86, y: 26.5, width: 6.5, height: 6.5)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 88.4, y: 28.4, width: 3.3, height: 3.3)), with: .color(.ink))
            var smile = Path()
            smile.move(to: CGPoint(x: 88, y: 37.5))
            smile.addQuadCurve(to: CGPoint(x: 95.5, y: 35.5), control: CGPoint(x: 92.5, y: 40))
            ctx.stroke(smile, with: .color(shellDark), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            // Shell dome
            var dome = Path()
            dome.move(to: CGPoint(x: 6, y: 58))
            dome.addCurve(to: CGPoint(x: 40, y: 8), control1: CGPoint(x: 6, y: 30), control2: CGPoint(x: 20, y: 8))
            dome.addCurve(to: CGPoint(x: 76, y: 58), control1: CGPoint(x: 62, y: 8), control2: CGPoint(x: 76, y: 30))
            dome.closeSubpath()
            ctx.fill(dome, with: .color(shell))

            // Shell plates
            ctx.drawLayer { layer in
                layer.clip(to: dome)
                let plate = GraphicsContext.Shading.color(.white.opacity(0.22))
                layer.fill(Path(roundedRect: CGRect(x: 30, y: 16, width: 21, height: 17), cornerRadius: 6), with: plate)
                layer.fill(Path(roundedRect: CGRect(x: 13, y: 34, width: 19, height: 16), cornerRadius: 6), with: plate)
                layer.fill(Path(roundedRect: CGRect(x: 36, y: 37, width: 19, height: 14), cornerRadius: 6), with: plate)
                layer.fill(Path(roundedRect: CGRect(x: 58, y: 34, width: 14, height: 16), cornerRadius: 6), with: plate)
            }

            // Shell rim
            ctx.fill(Path(roundedRect: CGRect(x: 3, y: 52, width: 77, height: 11), cornerRadius: 5.5), with: .color(shellDark))
        }
        .aspectRatio(100 / 78, contentMode: .fit)
        .accessibilityLabel("Steady the tortoise")
    }
}
