import BlithCore
import Charts
import SwiftUI

/// Sleep, in detail: performance vs personal need, stages, efficiency, debt, timing and the
/// factors behind the score. One night at a time, with the last 14 nights one tap away.
struct SleepView: View {
    var standalone = false
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var scrollTarget: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    if let s = app.snapshot, !s.ctx.history.sleepNights.isEmpty {
                        SleepContent(snapshot: s)
                    } else {
                        EmptyStateView(symbol: "bl.sleep", title: "No sleep data yet",
                                       message: "Sleep comes from Apple Watch, iPhone Sleep Focus or a sleep app that writes to Apple Health. If you connected Sleep and still see nothing, check Settings › Health › Data Access › Blith.",
                                       actionTitle: "Connected data", action: { router.sheet = .profile })
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollTarget, anchor: .top)
            .task { if !standalone { await LaunchOptions.scroll { scrollTarget = $0 } } }
            .scrollIndicators(.hidden)
            .blithBackground(wash: Palette.sleep.opacity(0.16))
            .toolbar {
                if standalone { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .toolbar(standalone ? .visible : .hidden, for: .navigationBar)
        }
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: "Sleep performance", icon: "bl.sleep", color: Palette.sleep)
                    if app.isDemo { SampleDataBanner() }
                }
                Text("Sleep").font(Typo.pageTitle).foregroundStyle(Palette.ink)
            }
            Spacer()
            if !standalone { AvatarButton(name: app.profile.name) { router.sheet = .profile } }
        }
        .padding(.top, Space.s)
    }
}

private struct SleepContent: View {
    let snapshot: HealthSnapshot
    @Environment(AppRouter.self) private var router
    @State private var heatmapSelection: LocalDate?

    var engine: ScoreEngine { ScoreEngine(snapshot.ctx) }
    var nights: [SleepNight] { snapshot.ctx.history.sleepNights.values.sorted { $0.date < $1.date }.suffix(14) }
    var date: LocalDate { router.sleepDate.flatMap { snapshot.ctx.history.sleepNights[$0] != nil ? $0 : nil } ?? nights.last?.date ?? snapshot.ctx.today }

    var body: some View {
        let perf = engine.sleep(on: date)
        let night = snapshot.ctx.history.sleepNights[date]
        nightPicker
        if let perf, let night {
            hero(perf)
            stages(perf, night: night).id("stages")
            statsGrid(perf).id("stats")
            factors(perf).id("factors")
            planner(perf)
        } else {
            EmptyStateView(symbol: "bl.sleep", title: "Not enough sleep recorded", message: "This night has less than 30 minutes of recorded sleep.")
        }
        timing
        history
        Text("Stage estimates come from your devices and aren't a clinical sleep study. Scores compare you with your own history and aren't medical advice.")
            .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.tertiaryInk)
    }

    // MARK: Night picker

    var nightPicker: some View {
        let need = engine.sleep(on: date)?.need
        // One scale for every bar and the need line, set by the longest night, so a very long
        // night shrinks the others instead of growing out of the card.
        let longest = max(nights.map(\.asleepDuration).max() ?? 0, need ?? 0, 3600)
        let perHour = 72 / CGFloat(longest / 3600)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(nights) { n in
                let isSel = n.date == date
                let score = engine.sleep(on: n.date)?.score
                Button { withAnimation(Motion.standard) { router.sleepDate = n.date } } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSel ? AnyShapeStyle(LinearGradient(colors: [Palette.sleepREM, Palette.sleep], startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Palette.sleep.opacity(0.22 + 0.33 * Double(score ?? 0) / 100)))
                            .frame(height: max(10, CGFloat(n.asleepDuration / 3600) * perHour))
                        Text(String(Fmt.weekdayShort[n.date.weekday - 1].prefix(1))).font(Typo.eyebrow)
                            .foregroundStyle(isSel ? Palette.ink : Palette.tertiaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Fmt.dayLabel(n.date)), \(Fmt.duration(n.asleepDuration))\(score.map { ", score \($0)" } ?? "")")
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
        }
        .frame(height: 100, alignment: .bottom)
        .overlay(alignment: .bottom) {
            // Your personal need, as a dashed line across every night, on the bars' scale.
            if let need {
                ZStack(alignment: .trailing) {
                    Rectangle().fill(.clear).frame(height: 1)
                        .overlay(Line().stroke(Palette.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    Text("NEED \(Fmt.duration(need))").font(Typo.mono(11, .medium)).foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 4).background(Palette.surface).offset(y: -9)
                }
                .padding(.bottom, 17 + CGFloat(need / 3600) * perHour)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .card(padding: Space.m)
    }

    // MARK: Hero

    /// Blith 2.0: one big number with a word and a glyph, then a bar against your need. No dial.
    func hero(_ p: SleepPerformance) -> some View {
        let diff = p.asleep - p.need
        let status = abs(diff) < 15 * 60 ? "■ About your need" : diff > 0 ? "▲ Above your need" : "▼ Below your need"
        return VStack(alignment: .leading, spacing: Space.l) {
            Eyebrow(text: "Night ending \(Fmt.dayLabel(p.date))", color: Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("ASLEEP").font(Typo.eyebrow).tracking(0.8).foregroundStyle(Palette.tertiaryInk)
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Text(Fmt.duration(p.asleep))
                        .font(Typo.score(56, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(status)
                        .font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.sleep)
                }
            }
            HoursVsNeedBar(asleep: p.asleep, need: p.need)
            HStack(alignment: .top, spacing: Space.l) {
                heroStat("Sleep score", "\(p.score)", Palette.sleep)
                heroStat("Personal need", Fmt.duration(p.need), Palette.ink)
                heroStat("7-night debt", p.debt < 600 ? "None" : Fmt.duration(p.debt), p.debt > 3 * 3600 ? Palette.amber : Palette.ink)
            }
            .accessibilityElement(children: .combine)
            Text(sentence(p)).font(Typo.story).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Space.xl, tone: .tinted(Palette.sleep))
    }

    func heroStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(Typo.eyebrow).tracking(0.8).foregroundStyle(Palette.tertiaryInk)
            Text(value).font(Typo.score(24, weight: .regular)).foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func sentence(_ p: SleepPerformance) -> String {
        let diff = p.asleep - p.need
        if abs(diff) < 15 * 60 { return "You slept about as long as your body usually asks for." }
        if diff > 0 { return "You slept \(Fmt.duration(diff)) more than your personal need." }
        return "You slept \(Fmt.duration(-diff)) less than your personal need."
    }

    // MARK: Stages

    func stages(_ p: SleepPerformance, night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Stages", subtitle: night.hasStages ? "From \(night.source.name)" : "This source records time asleep without stages")
            if night.hasStages {
                SleepTimelineView(night: night, height: 120)
                ForEach([(SleepStage.awake, SleepStageStyle.awake), (.rem, .rem), (.core, .core), (.deep, .deep)], id: \.0) { stage, style in
                    let d = p.stages[stage] ?? 0
                    let share = p.inBed > 0 ? d / p.inBed : 0
                    HStack(spacing: Space.m) {
                        Circle().fill(Palette.sleep(style)).frame(width: 8, height: 8)
                        Text(stage == .core ? "Light (core)" : stage.displayName).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            .frame(width: 104, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Palette.raised)
                                .overlay(alignment: .leading) { Capsule().fill(Palette.sleep(style).gradient).frame(width: max(3, g.size.width * share)) }
                        }
                        .frame(height: 6)
                        Text(Fmt.duration(d)).font(Typo.number(15)).foregroundStyle(Palette.ink).monospacedDigit().frame(width: 62, alignment: .trailing)
                        Text("\(Int((share * 100).rounded()))%").font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk).frame(width: 30, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card(padding: Space.l)
    }

    // MARK: Stats

    func statsGrid(_ p: SleepPerformance) -> some View {
        let cols = [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)]
        return LazyVGrid(columns: cols, spacing: Space.m) {
            MetricTile(title: "Time in bed", icon: "bl.sleep", value: Fmt.duration(p.inBed), caption: bedWindow(p), color: Palette.sleep)
            MetricTile(title: "Efficiency", icon: "bl.target", value: "\(Int((p.efficiency * 100).rounded()))", unit: "%", caption: "asleep while in bed", color: Palette.sleep)
            MetricTile(title: "Fell asleep", icon: "bl.stages", value: p.latencyMinutes.map { "\(Int($0.rounded()))" } ?? "–", unit: "min", caption: "after first sample", color: Palette.sleep)
            MetricTile(title: "Wake-ups", icon: "bl.warning", value: "\(p.disturbances)", caption: "awake periods mid-night", color: Palette.sleep)
            MetricTile(title: "Consistency", icon: "bl.calendar", value: p.consistency.map { "\(Int(($0 * 100).rounded()))" } ?? "–", unit: p.consistency == nil ? nil : "%",
                       caption: "bedtime vs last 7 nights", color: Palette.sleep)
            MetricTile(title: "Respiratory", icon: "bl.resp", value: p.respiratoryRate.map { Fmt.decimal($0) } ?? "–", unit: "/min",
                       caption: "breaths per minute asleep", color: Palette.sleep)
        }
    }

    func bedWindow(_ p: SleepPerformance) -> String? {
        guard let b = p.bedtime, let w = p.wake else { return nil }
        return "\(b.formatted(date: .omitted, time: .shortened)) – \(w.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Factors

    func factors(_ p: SleepPerformance) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionHeader(title: "Why this score", subtitle: "Each factor compared with your need and your own recent nights")
            ForEach(p.factors) { FactorRow(factor: $0, color: Palette.sleep) }
        }
        .card(padding: Space.l)
    }

    // MARK: Planner

    @ViewBuilder
    func planner(_ p: SleepPerformance) -> some View {
        let timing = SleepAnalytics.timing(snapshot.ctx, nights: 14)
        if timing.count >= 5, let wake = Stats.median(timing.map(\.wakeMinutes)) {
            let catchUp = min(p.debt / 7, 45 * 60)
            let target = p.need + catchUp
            let bed = wake - (target + 15 * 60) / 60
            VStack(alignment: .leading, spacing: Space.m) {
                Eyebrow(text: "Tonight", icon: "bl.target", color: Palette.sleep)
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(SleepAnalytics.clock(bed)).font(Typo.score(46)).foregroundStyle(Palette.ink)
                    Text("in bed for \(Fmt.duration(target)) asleep by your usual \(SleepAnalytics.clock(wake)) wake-up")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
                Text(catchUp > 60 ? "Includes \(Fmt.duration(catchUp)) toward this week's debt. A suggestion from your own data, not medical advice."
                                  : "Based on your personal need and usual wake time. A suggestion, not medical advice.")
                    .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.tertiaryInk)
            }
            .card(padding: Space.l)
        }
    }

    // MARK: Timing and history

    @ViewBuilder
    var timing: some View {
        let points = SleepAnalytics.timing(snapshot.ctx, nights: 28)
        if points.count >= 5 {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionHeader(title: "When you slept", subtitle: "Last \(points.count) nights, bedtime to wake-up")
                SleepTimingChart(points: points)
                if let bed = Stats.median(points.map(\.bedMinutes)), let wake = Stats.median(points.map(\.wakeMinutes)) {
                    Text("Usually asleep around \(SleepAnalytics.clock(bed)) and up around \(SleepAnalytics.clock(wake)).")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
            .card(padding: Space.l)
        }
    }

    var history: some View {
        let days = snapshot.scoreHistory
        let scored = days.compactMap(\.sleep)
        return VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Last 13 weeks", subtitle: scored.isEmpty ? nil : "Average sleep performance \(Int((Stats.mean(scored.map(Double.init)) ?? 0).rounded()))%")
            ScoreHeatmap(days: days, mode: .sleep, selected: date) { d in
                if snapshot.ctx.history.sleepNights[d] != nil { withAnimation(Motion.standard) { router.sleepDate = d } }
            }
            HStack(spacing: Space.s) {
                Text("LESS").font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
                ForEach([0.2, 0.45, 0.7, 1.0], id: \.self) { o in RoundedRectangle(cornerRadius: 3).fill(Palette.sleep.opacity(o)).frame(width: 14, height: 14) }
                Text("MORE").font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
            }
        }
        .card(padding: Space.l)
    }
}

/// Asleep vs need as a single bar with the need marked.
struct HoursVsNeedBar: View {
    let asleep: TimeInterval
    let need: TimeInterval

    var body: some View {
        GeometryReader { g in
            let maxV = max(asleep, need) * 1.08
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.raised)
                Capsule().fill(LinearGradient(colors: [Palette.sleepDeep, Palette.sleep, Palette.sleepREM], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * asleep / maxV)
                Rectangle().fill(Palette.ink).frame(width: 2, height: 16).offset(x: w * need / maxV - 1)
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Asleep \(Fmt.duration(asleep)) of \(Fmt.duration(need)) need")
    }
}

/// A horizontal line across the full width, for dashed reference marks.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)) }
    }
}
