import SwiftUI

/// First-visit hints on the 3D stage: how to turn, zoom and pick a muscle. Thin strokes, no glow,
/// and it steps aside as soon as the person touches the figure. Only the card takes touches, so
/// the figure can be turned straight through the hint.
struct BodyCoachOverlay: View {
    /// Where the chest appears on the stage, for the tap hint; nil until the figure is laid out.
    var point: CGPoint?
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var sway = false

    init(point: CGPoint?, onDone: @escaping () -> Void) {
        self.point = point
        self.onDone = onDone
    }

    var body: some View {
        GeometryReader { geo in
            let p = point ?? CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.34)
            ZStack {
                tapHint
                    .position(p)
                    .allowsHitTesting(false)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassSurface(Capsule())
                    .offset(x: sway ? 16 : -16)
                    .position(x: geo.size.width / 2, y: min(geo.size.height * 0.52, p.y + 120))
                    .allowsHitTesting(false)
                VStack {
                    Spacer()
                    card
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, 62)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { sway = true }
        }
        .accessibilityElement(children: .contain)
    }

    var tapHint: some View {
        ZStack {
            Circle()
                .stroke(Palette.ink.opacity(0.55), lineWidth: 1.5)
                .frame(width: 34, height: 34)
                .scaleEffect(pulse ? 1.7 : 0.8)
                .opacity(pulse ? 0 : 0.9)
            Circle().fill(Palette.ink.opacity(0.85)).frame(width: 9, height: 9)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 22))
                .foregroundStyle(Palette.ink.opacity(0.9))
                .offset(x: 15, y: 21)
        }
        .accessibilityHidden(true)
    }

    var card: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Your body map").font(Typo.cardTitle).foregroundStyle(Palette.ink)
            row("hand.draw", "Drag sideways to turn the figure")
            row("hand.pinch", "Pinch to zoom in on any part")
            row("hand.tap", "Tap a muscle to see what it does")
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Got it").font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                }
                .glassButton(prominent: true)
            }
            .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.anatomy)
                .frame(width: 22)
            Text(text).font(Typo.geist(14, relativeTo: .footnote)).foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}
