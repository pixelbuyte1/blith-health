import BlithCore
import SwiftUI

/// Carries the beat phase between frames and eases the rate toward each new reading, so the heart
/// speeds up and slows down smoothly instead of jumping when a new sample arrives.
final class BeatClock {
    private(set) var phase = 0.0
    private(set) var bpm = 70.0
    private var last: Date?

    func advance(to now: Date, target: Double) -> (phase: Double, bpm: Double) {
        guard let last else {
            self.last = now
            bpm = target
            return (phase, bpm)
        }
        let dt = min(0.25, max(0, now.timeIntervalSince(last)))
        self.last = now
        bpm += (target - bpm) * min(1, dt / 0.8)
        phase = (phase + dt * bpm / 60).truncatingRemainder(dividingBy: 1)
        return (phase, bpm)
    }
}

/// Live heart rate: the heart pounds at exactly the measured BPM (a "lub-dub" every 60/BPM seconds)
/// and harder as the rate climbs above the person's resting rate; the ECG strip under it follows the
/// same rate. Honest about freshness: the zone while live (under 90 s), otherwise how long ago.
struct LiveHeartCard: View {
    let live: LiveHeartRate
    var isDemo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = BeatClock()

    /// The monitoring heart sits beside the number, about as tall as the digits.
    private let heartBox: CGFloat = 64
    private let ecgHeight: CGFloat = 64

    var body: some View {
        let summary = live.summary()
        VStack(alignment: .leading, spacing: Space.m) {
            header(summary)
            switch live.status {
            case .ready where summary.latest != nil:
                pounding(summary)
            default:
                emptyState
            }
        }
        .card(padding: Space.l)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    func header(_ s: LiveHeartSummary) -> some View {
        HStack {
            Eyebrow(text: "Live heart rate", icon: "bl.heart", color: Palette.heart)
            Spacer()
            if live.isSimulated { MonoPill(text: "Sample", color: Palette.secondaryInk) }
            if live.status == .ready, s.latest != nil { context }
        }
    }

    /// "Warm · resting 57" while live; "4 min ago · resting 57" once the reading is older.
    /// Re-evaluated every few seconds so it ages without a new reading.
    var context: some View {
        TimelineView(.periodic(from: .now, by: 5)) { tl in
            let s = live.summary(now: tl.date)
            let age = s.age(now: tl.date) ?? 0
            let lead = s.freshness == .live ? s.zone.label : "\(ageText(age)) ago"
            Text(lead + (s.resting.map { " · resting \(Int($0.rounded()))" } ?? ""))
                .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel(s.freshness == .live ? "Live, \(s.zone.label.lowercased()) zone" : "Last reading \(ageText(age)) ago")
        }
    }

    func ageText(_ age: TimeInterval) -> String {
        switch age {
        case ..<90: "\(Int(age)) s"
        case ..<3600: "\(Int((age / 60).rounded())) min"
        case ..<86_400: "\(Int((age / 3600).rounded())) h"
        default: "\(Int((age / 86_400).rounded())) d"
        }
    }

    // MARK: The pounding heart and ECG

    func pounding(_ s: LiveHeartSummary) -> some View {
        let bpm = s.bpm ?? 70
        // Pound while the reading is fresh enough to mean something; hold still once it's old.
        let animating = !reduceMotion && scenePhase == .active && s.freshness != .stale
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { tl in
            let beat = animating ? clock.advance(to: tl.date, target: bpm) : (phase: 0.86, bpm: bpm)
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .center, spacing: Space.m) {
                    heart(phase: beat.phase, intensity: s.intensity, freshness: s.freshness)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(bpm.rounded()))")
                            .font(Typo.score(60, weight: .regular)).foregroundStyle(Palette.ink)
                            .monospacedDigit().contentTransition(.numericText())
                        Text("BPM").font(Typo.eyebrow).tracking(1.2).foregroundStyle(Palette.heart.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                Canvas { ctx, size in
                    drawECG(&ctx, size: size, phase: beat.phase, bpm: beat.bpm, freshness: s.freshness)
                }
                .frame(height: ecgHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate \(Int(bpm.rounded())) beats per minute, \(s.zone.label.lowercased()) zone")
        .accessibilityValue(s.freshness == .live ? "Live" : "Last reading \(ageText(s.age(now: Date()) ?? 0)) ago")
    }

    /// The system heart (SF Symbols `heart.fill`), flat in the heart colour. It swells with each
    /// "lub-dub", harder as intensity rises above the person's resting rate.
    func heart(phase: Double, intensity: Double, freshness: LiveHeartSummary.Freshness) -> some View {
        let thump = HeartWaveform.thump(phase: phase)
        let scale = 1 + (0.09 + 0.15 * intensity) * thump
        let dim = freshness == .live ? 1.0 : (freshness == .recent ? 0.9 : 0.6)
        return Image(systemName: "heart.fill")
            .resizable().scaledToFit()
            .foregroundStyle(Palette.heart.opacity(dim))
            .frame(width: heartBox * 0.78, height: heartBox * 0.78)
            .scaleEffect(scale)
            .frame(width: heartBox, height: heartBox)
            .accessibilityHidden(true)
    }

    /// An ECG strip scrolling right to left: about four seconds of trace, its R spike landing at the
    /// right edge with each "lub", so the spacing follows the measured rate.
    func drawECG(_ ctx: inout GraphicsContext, size: CGSize, phase: Double, bpm: Double, freshness: LiveHeartSummary.Freshness) {
        let seconds = 4.0
        // Spike near the top, the deep dip after it near the bottom.
        let baseline = size.height * 0.6
        let amp = size.height * 0.55
        let steps = max(2, Int(size.width / 1.5))
        var trace = Path()
        for i in 0...steps {
            let x = size.width * CGFloat(i) / CGFloat(steps)
            let back = seconds * Double(1 - x / size.width)
            // The beat phase `back` seconds ago.
            var p = (phase - back * bpm / 60).truncatingRemainder(dividingBy: 1)
            if p < 0 { p += 1 }
            let y = baseline - amp * CGFloat(HeartWaveform.ecg(phase: p))
            if i == 0 { trace.move(to: CGPoint(x: x, y: y)) } else { trace.addLine(to: CGPoint(x: x, y: y)) }
        }
        let dim = freshness == .live ? 1.0 : (freshness == .recent ? 0.75 : 0.45)
        ctx.stroke(trace, with: .color(Palette.heart.opacity(dim)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    // MARK: Empty states

    @ViewBuilder
    var emptyState: some View {
        HStack(alignment: .center, spacing: Space.l) {
            // Nothing is being monitored: the same heart, quieter, with a soft glow behind it.
            ZStack {
                Circle().fill(RadialGradient(colors: [Palette.heart.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 46))
                Image(systemName: "heart.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Palette.heart.opacity(0.6))
                    .frame(width: 56, height: 56)
            }
            .frame(width: 92, height: 92)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s) {
                switch live.status {
                case .needsAccess:
                    Text("See your heart rate live").font(.headline).foregroundStyle(Palette.ink)
                    Text("Allow Blith to read heart rate from Apple Health. It stays on this iPhone.").font(.subheadline).foregroundStyle(Palette.secondaryInk)
                    Button { Task { await live.requestAccess() } } label: {
                        Label("Allow heart rate", systemImage: "heart.fill").font(.subheadline.weight(.semibold))
                    }
                    .glassButton(prominent: true)
                case .unavailable:
                    Text("Heart rate isn't available").font(.headline).foregroundStyle(Palette.ink)
                    Text("Health data isn't available on this device.").font(.subheadline).foregroundStyle(Palette.secondaryInk)
                case .idle:
                    Text("Listening for your heart…").font(.headline).foregroundStyle(Palette.ink)
                default:
                    Text("No heart rate in the last 24 hours").font(.headline).foregroundStyle(Palette.ink)
                    Text("Wear your Apple Watch, or start a Workout on it, and readings appear here as soon as Health receives them. If you've already allowed access, check Settings › Health › Data Access › Blith.")
                        .font(.footnote).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
