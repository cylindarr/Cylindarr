import CylindarrClientKit
import SwiftUI

/// The brand's colours (brand-spec.md), light and dark as the pages have
/// them: indigo for the accent, amber only in the mark.
public extension Color {
    static let cylindarrAccent = Color(light: 0x3d4a8f, dark: 0x9ea9ec)
    static let cylindarrIndigo = Color(hex: 0x3d4a8f)
    static let cylindarrAmber = Color(hex: 0xf0b04a)

    static func cylindarr(_ state: Grab.State) -> Color {
        switch state {
        case .placed: Color(light: 0x2f6f45, dark: 0x7cc79a)
        case .wanted, .resolving, .fetching: .cylindarrAccent
        case .deferred: Color(light: 0x5b6478, dark: 0xa7afc2)
        case .failed: Color(light: 0xc0263b, dark: 0xff8f9b)
        case .skipped, .retired: Color(light: 0x6b7079, dark: 0x8e94a0)
        }
    }

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Color(hex: dark)) : NSColor(Color(hex: light))
        })
        #endif
    }
}

/// The mark, drawn from the same geometry as `cylindarr-mark.svg` on its
/// 64-unit grid: a tube seen end on, its bore off-centre, and the amber
/// play triangle as the light at the far end.
public struct CylindarrMark: View {
    var tube: Color

    public init(tube: Color = .cylindarrAccent) {
        self.tube = tube
    }

    public var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 64
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var face = Path()
            face.addEllipse(in: CGRect(x: 6 * s, y: 6 * s, width: 52 * s, height: 52 * s))
            face.addEllipse(in: CGRect(x: 20.5 * s, y: 20.5 * s, width: 32 * s, height: 32 * s))
            context.fill(face, with: .color(tube), style: FillStyle(eoFill: true))
            var light = Path()
            light.move(to: p(32.40, 30.25))
            light.addLine(to: p(42.65, 36.50))
            light.addLine(to: p(32.40, 42.75))
            light.closeSubpath()
            context.fill(light, with: .color(.cylindarrAmber))
            context.stroke(light, with: .color(.cylindarrAmber), style: StrokeStyle(lineWidth: 3 * s, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A grab's state as the pages show it: a colour, a glyph and words, so it
/// never rests on colour alone.
public struct StateBadge: View {
    let state: Grab.State

    public init(_ state: Grab.State) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.symbol).imageScale(.small)
            Text(state.label).lineLimit(1)
        }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.cylindarr(state))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.cylindarr(state).opacity(0.13), in: Capsule())
            .fixedSize()
    }
}
