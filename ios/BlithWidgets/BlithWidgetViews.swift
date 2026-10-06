import BlithCore
import SwiftUI
import WidgetKit

// Widget views. Compiled into the widget extension and into the app (for the in-app gallery),
// so they take the family as a parameter instead of reading the environment.

/// Deep canvas with the faint top glow, as on the Today screen.
struct WidgetBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Palette.surface
            RadialGradient(colors: [Palette.signal.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 220)
        }
    }
}

/// A small version of the Today dial: tick bezel, usual band, thin value arc with a lit tip.
struct WidgetDial: View {
    var fraction: Double?
    var value: String
    var unit: String?
    var color: Color
    var usual: ClosedRange<Double>? = nil
    var size: CGFloat = 92

    private let start = 0.125, span = 0.75

    var body: some View {
        ZStack {
            ForEach(0..<31, id: \.self) { i in
                Capsule()
                    .fill(Palette.quiet.opacity(i % 5 == 0 ? 0.9 : 0.5))
                    .frame(width: 1, height: i % 5 == 0 ? 5 : 3)
                    .offset(y: -size / 2 + 2)
                    .rotationEffect(.degrees(-135 + Double(i) * 9))
            }
            Circle()
                .trim(from: start, to: start + span)
                .stroke(Palette.sunken, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(90))
                .padding(9)
            if let usual {
                Circle()
                    .trim(from: start + span * usual.lowerBound, to: start + span * usual.upperBound)
                    .stroke(Palette.usualBand, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(90))
                    .padding(9)
            }
            if let fraction {
                let f = min(max(fraction, 0), 1)
                Circle()
                    .trim(from: start, to: start + span * f)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(9)
                Circle()
                    .fill(Palette.ink)
                    .frame(width: 6, height: 6)
                    .offset(y: -(size / 2 - 9))
                    .rotationEffect(.degrees(-135 + 270 * f))
            }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(Typo.score(size * 0.34)).foregroundStyle(Palette.ink)
                if let unit { Text(unit).font(Typo.geist(size * 0.12, .medium)).foregroundStyle(Palette.secondaryInk) }
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 14)
        }
        .frame(width: size, height: size)
    }
}

private struct WidgetEyebrow: View {
    let text: String
    var color: Color = Palette.secondaryInk
    var body: some View {
        Text(text.uppercased()).font(Typo.mono(10, .medium)).tracking(0.8).foregroundStyle(color).lineLimit(1)
    }
}

private struct WidgetMessage: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetEyebrow(text: "Blith")
            Spacer(minLength: 0)
            Text(title).font(Typo.geist(15, .semibold)).foregroundStyle(Palette.ink)
            Text(detail).font(Typo.geist(12)).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Readiness

struct ReadinessWidgetView: View {
    let snapshot: WidgetSnapshot?
    let date: Date
    let family: WidgetFamily

    var current: WidgetSnapshot? {
        guard let snapshot, snapshot.isCurrent(at: date, calendar: .current) else { return nil }
        return snapshot
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        default: small
        }
    }

    var bandColor: Color { Palette.band(current?.readinessBand) }

    var dialValue: String {
        guard let s = current else { return "–" }
        return s.readiness.map(String.init) ?? "\(s.calibrationDays)"
    }

    var dialUnit: String? {
        guard let s = current else { return nil }
        return s.readiness == nil ? "/\(s.calibrationTarget)" : nil
    }

    var bandLine: some View {
        HStack(spacing: 4) {
            if let s = current, let b = s.readinessBand {
                Image(systemName: Palette.bandSymbol(b)).font(.system(size: 9, weight: .bold))
                Text("\(b.label) readiness")
            } else if current?.readiness == nil, current != nil {
                Image(systemName: "ellipsis").font(.system(size: 9, weight: .bold))
                Text("Calibrating")
            }
        }
        .font(Typo.mono(10, .medium))
        .foregroundStyle(bandColor)
    }

    @ViewBuilder var small: some View {
        if snapshot == nil {
            WidgetMessage(title: "Readiness", detail: "Open Blith to connect your health data.")
        } else if current == nil {
            WidgetMessage(title: "New day", detail: "Open Blith to update today's readiness.")
        } else if let s = current {
            VStack(spacing: 6) {
                HStack {
                    WidgetEyebrow(text: "Readiness")
                    Spacer()
                    if s.isSample { WidgetEyebrow(text: "Sample", color: Palette.tertiaryInk) }
                }
                WidgetDial(fraction: s.readiness.map { Double($0) / 100 }, value: dialValue, unit: dialUnit, color: bandColor, size: 86)
                bandLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder var medium: some View {
        if snapshot == nil || current == nil {
            WidgetMessage(title: snapshot == nil ? "Readiness, sleep and load" : "New day",
                          detail: snapshot == nil ? "Open Blith to connect your health data." : "Open Blith to update today's scores.")
        } else if let s = current {
            HStack(spacing: 14) {
                VStack(spacing: 6) {
                    WidgetDial(fraction: s.readiness.map { Double($0) / 100 }, value: dialValue, unit: dialUnit, color: bandColor, size: 104)
                    bandLine
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        WidgetEyebrow(text: "Today")
                        Spacer()
                        if s.isSample { WidgetEyebrow(text: "Sample", color: Palette.tertiaryInk) }
                    }
                    metricRow("Sleep", s.sleepScore.map { "\($0)%" } ?? "–", s.asleep.map { Fmt.duration($0) }, Palette.sleep)
                    metricRow("Load", s.load.map { Fmt.decimal($0) } ?? "–",
                              s.loadUsualLow.flatMap { lo in s.loadUsualHigh.map { "usual \(Fmt.decimal(lo))–\(Fmt.decimal($0))" } }, Palette.cyan)
                    weekBars(s)
                    if let name = s.companionName, let last = s.companionLastSync {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .semibold))
                            Text("\(name.replacingOccurrences(of: " Health", with: "")) · \(Fmt.ago(last, now: date))").lineLimit(1)
                        }
                        .font(Typo.mono(9, .medium))
                        .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
        }
    }

    func metricRow(_ label: String, _ value: String, _ detail: String?, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 3, height: 10)
            Text(label).font(Typo.geist(12)).foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 4)
            Text(value).font(Typo.number(15)).foregroundStyle(Palette.ink)
            if let detail { Text(detail).font(Typo.mono(9)).foregroundStyle(Palette.tertiaryInk).lineLimit(1) }
        }
    }

    func weekBars(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(s.readinessWeek.enumerated()), id: \.offset) { i, v in
                let isToday = i == s.readinessWeek.count - 1
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(v == nil ? Palette.sunken : (isToday ? Palette.band(v.map(ScoreBand.readiness)) : Palette.signal.opacity(0.4)))
                    .frame(height: max(3, CGFloat(v ?? 0) / 100 * 20))
            }
        }
        .frame(height: 20, alignment: .bottom)
        .accessibilityLabel("Readiness, last 7 days")
    }

    @ViewBuilder var circular: some View {
        if let s = current, let r = s.readiness {
            Gauge(value: Double(r), in: 0...100) {
                Text("RDY")
            } currentValueLabel: {
                Text("\(r)").font(Typo.geist(17, .medium))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text(current == nil ? "–" : "\(current?.calibrationDays ?? 0)").font(Typo.geist(15, .medium))
            }
        }
    }

    @ViewBuilder var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("READINESS").font(Typo.mono(10, .medium)).widgetAccentable()
            if let s = current {
                Text(s.readiness.map { "\($0) · \(s.readinessBand?.label ?? "")" } ?? "Calibrating \(s.calibrationDays)/\(s.calibrationTarget)")
                    .font(Typo.geist(15, .semibold))
                Text("Sleep \(s.sleepScore.map { "\($0)%" } ?? "–") · Load \(s.load.map { Fmt.decimal($0) } ?? "–")")
                    .font(Typo.geist(12))
            } else {
                Text("Open Blith to update").font(Typo.geist(13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder var inline: some View {
        if let s = current, let r = s.readiness {
            Text("Readiness \(r) · Sleep \(s.sleepScore.map { "\($0)%" } ?? "–")")
        } else {
            Text("Blith · open to update")
        }
    }
}

// MARK: - Movement

struct MovementWidgetView: View {
    let snapshot: WidgetSnapshot?
    let date: Date
    let family: WidgetFamily

    var current: WidgetSnapshot? {
        guard let snapshot, snapshot.isCurrent(at: date, calendar: .current) else { return nil }
        return snapshot
    }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    var paceText: String? {
        guard let change = current?.paceChange else { return nil }
        if abs(change) < 0.05 { return "About usual for this hour" }
        return change > 0 ? "\(Fmt.percent(change)) ahead of a usual day by now" : "\(Fmt.percent(change)) behind a usual day by now"
    }

    @ViewBuilder var small: some View {
        if snapshot == nil {
            WidgetMessage(title: "Steps", detail: "Open Blith to connect your health data.")
        } else if let s = current {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    WidgetEyebrow(text: "Steps today")
                    Spacer()
                    if s.isSample { WidgetEyebrow(text: "Sample", color: Palette.tertiaryInk) }
                }
                Spacer(minLength: 0)
                Text(s.steps.map { Fmt.int($0) } ?? "–")
                    .font(Typo.score(34))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                paceBar(s)
                if let paceText {
                    Text(paceText).font(.system(size: 12, design: .serif)).foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            WidgetMessage(title: "New day", detail: "Open Blith to update today's steps.")
        }
    }

    /// Today's steps on a track scaled to a usual whole day, with a tick at the usual-by-now point.
    func paceBar(_ s: WidgetSnapshot) -> some View {
        let full = max(s.usualStepsDay ?? 0, s.steps ?? 0, 1)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.signal, Palette.signalBright], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, w * CGFloat((s.steps ?? 0) / full)))
                if let usual = s.usualStepsByNow {
                    Rectangle().fill(Palette.ink).frame(width: 2, height: 10)
                        .offset(x: min(w - 2, w * CGFloat(usual / full)))
                }
            }
        }
        .frame(height: 6)
        .padding(.vertical, 2)
    }

    @ViewBuilder var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("STEPS").font(Typo.mono(10, .medium)).widgetAccentable()
            if let s = current {
                Text(s.steps.map { Fmt.int($0) } ?? "–").font(Typo.geist(17, .semibold))
                if let change = s.paceChange {
                    Text(abs(change) < 0.05 ? "About usual by now" : "\(change > 0 ? "+" : "−")\(Fmt.percent(change)) vs usual by now")
                        .font(Typo.geist(12))
                }
            } else {
                Text("Open Blith to update").font(Typo.geist(13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
