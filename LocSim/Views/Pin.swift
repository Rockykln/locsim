import SwiftUI

/// Teardrop of the app icon, drawn in a 34 × 46 box with the tip at the bottom.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 34 * rect.width, y: rect.minY + y / 46 * rect.height)
        }
        // Circle of radius 14 around (17, 17) for the head; k approximates a quarter arc.
        let k: CGFloat = 7.73
        var path = Path()
        path.move(to: p(17, 44))
        path.addCurve(to: p(3, 17), control1: p(12, 36), control2: p(3, 28))
        path.addCurve(to: p(17, 3), control1: p(3, 17 - k), control2: p(17 - k, 3))
        path.addCurve(to: p(31, 17), control1: p(17 + k, 3), control2: p(31, 17 - k))
        path.addCurve(to: p(17, 44), control1: p(31, 28), control2: p(22, 36))
        path.closeSubpath()
        return path
    }
}

/// Map pin with a white outline and a soft drop shadow.
struct MapPin: View {
    var width: CGFloat = 34

    var body: some View {
        let s = width / 34
        ZStack(alignment: .top) {
            PinShape()
                .fill(Color.red)
                .overlay(PinShape().stroke(.white, lineWidth: 2.5 * s))
                .frame(width: 34 * s, height: 46 * s)
                .shadow(color: .black.opacity(0.35), radius: 1.5 * s, y: 1.5 * s)
            Circle()
                .fill(.white)
                .frame(width: 11 * s, height: 11 * s)
                .offset(y: 11.5 * s)
        }
        .frame(width: 34 * s, height: 46 * s, alignment: .top)
    }

    /// Where the tip sits, for `Annotation(anchor:)`.
    static let anchor = UnitPoint(x: 0.5, y: 44.0 / 46.0)
}

/// Small pin without outline or shadow, for buttons and lists.
struct PinGlyph: View {
    var height: CGFloat = 22
    var color: Color = .red

    var body: some View {
        let s = height / 46
        ZStack(alignment: .top) {
            PinShape()
                .fill(color)
            Circle()
                .fill(.white)
                .frame(width: 11 * s, height: 11 * s)
                .offset(y: 11.5 * s)
        }
        .frame(width: 34 * s, height: height, alignment: .top)
        .accessibilityHidden(true)
    }
}
