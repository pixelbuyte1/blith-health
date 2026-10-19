import BlithCore
import SwiftUI

struct WalkView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52
    @State private var selectedBucket: ChartBucket?

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    if let s = app.snapshot, s.availability[.steps] != .noData || s.todaySteps != nil {
                        PeriodPicker(selection: $router.walkPeriod)
                        story(s, period: router.walkPeriod)
                        chart(s, period: router.walkPeriod)
                        if let d = router.walkSelectedDate {
                            DayPanel(date: d, snapshot: s, onClose: { router.walkSelectedDate = nil })
                        } else if let b = selectedBucket, router.walkPeriod.bucket == .week || router.walkPeriod.bucket == .month {
                            bucketPanel(b, s: s)
                        }
                        measured(s, period: router.walkPeriod)
                        LoadSection(snapshot: s)
                        meaning(s)
                        signature(s)
                        gait(s)
                        sessions(s)
                        Button { router.sheet = .sources } label: {
                            Label("Data sources and coverage", systemImage: "square.stack.3d.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .card()
                    } else {
                        EmptyStateView(symbol: "bl.walk", title: "No steps yet",
                                       message: "Steps come from your iPhone or Apple Watch through Apple Health. If you've limited access, you can change it in Settings › Health › Data Access.",
                                       actionTitle: "Connected data", action: { router.sheet = .profile })
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .blithBackground(wash: Palette.signal.opacity(0.14))
            .refreshable { await app.refresh(force: true) }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: router.walkPeriod) { _, _ in selectedBucket = nil }
        }
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: "Steps · load · gait", icon: "bl.activity", color: Palette.signal)
                    if app.isDemo { SampleDataBanner() }
                }
                Text("Activity").font(Typo.pageTitle).foregroundStyle(Palette.ink)
            }
            Spacer()
            AvatarButton(name: app.profile.name) { router.sheet = .profile }
        }
        .padding(.top, Space.s)
    }

    // MARK: Story for the selected range

    func summary(_ s: HealthSnapshot, _ period: WalkPeriod) -> PeriodSummary {
        s.periods[period] ?? HealthAnalytics(s.ctx).periodSummary(.steps, period: period)
    }

    func rangeLabel(_ p: PeriodSummary) -> String {
        "\(Fmt.shortDate(p.span.start)) – \(Fmt.shortDate(p.span.end))"
    }

    func storyLine(_ s: HealthSnapshot, _ p: PeriodSummary) -> String {
        let weekday = Fmt.weekday(s.ctx.today)
        if p.period == .day {
            guard let pace = s.pace else { return "Today's steps, hour by hour." }
            if (s.todaySteps ?? 0) == 0 {
                if let start = pace.usualCurve.firstIndex(where: { $0 > (pace.usualFullDay ?? 1) * 0.05 }) {
                    return "Quiet so far. You usually get moving around \(Fmt.hour(start))."
                }
                return "Quiet so far today."
            }
            guard let status = PaceStatus(pace) else { return "Today's steps, hour by hour." }
            switch status {
            case .above: return "Ahead of your usual \(weekday) at this hour."
            case .below: return "Behind your usual \(weekday) so far — the day isn't over."
            case .usual: return "Right on your usual \(weekday) pace."
            }
        }
        let n = p.previousSpan.dayCount
        guard let change = p.change else { return p.daysWithData < 3 ? "Still building this range." : "Your walking across this range." }
        if change >= 0.05 { return "You walked more than in the \(n) days before." }
        if change <= -0.05 { return "A quieter stretch than the \(n) days before." }
        return "Steady — about the same as the \(n) days before."
    }

    func story(_ s: HealthSnapshot, period: WalkPeriod) -> some View {
        let p = summary(s, period)
        return VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: period == .day ? "Today so far" : "\(period.title) · \(rangeLabel(p))")
            Text(storyLine(s, p)).font(Typo.story).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(Fmt.int(period == .day ? (s.todaySteps ?? 0) : (p.dailyAverage ?? 0)))
                    .font(Typo.score(period == .day && (s.todaySteps ?? 0) == 0 ? heroSize - 8 : heroSize + 10))
                    .foregroundStyle(period == .day && (s.todaySteps ?? 0) == 0 ? Palette.tertiaryInk : Palette.ink)
                    .contentTransition(.numericText())
                Text(period == .day ? "steps so far" : "steps a day").font(Typo.geist(17, .medium, relativeTo: .headline)).foregroundStyle(Palette.secondaryInk)
            }
            if period == .day {
                if let pace = s.pace, let usual = pace.usualByNow {
                    HStack(spacing: Space.m) {
                        if let status = PaceStatus(pace) { StatusLabel(symbol: status.symbol, text: status.text, color: status.color) }
                        Text("Usually \(Fmt.int(usual)) by now · \(Fmt.int(pace.usualFullDay ?? 0)) by day's end")
                            .font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let c = p.change { DeltaBadge(change: c, caption: "vs the \(p.previousSpan.dayCount) days before") }
                    if let prev = p.previousDailyAverage {
                        Text("Before: \(Fmt.int(prev)) a day (\(Fmt.shortDate(p.previousSpan.start)) – \(Fmt.shortDate(p.previousSpan.end)))")
                            .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                    }
                    Text("Averages use complete days with records (\(p.daysWithData) of \(p.span.dayCount)); today counts once it's over.")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .padding(.horizontal, Space.xs)
    }

    // MARK: Chart

    func chart(_ s: HealthSnapshot, period: WalkPeriod) -> some View {
        let p = summary(s, period)
        let unitLabel: String
        switch p.bucketUnit {
        case .hour: unitLabel = "Steps by hour · dashed line is your usual \(Fmt.weekday(s.ctx.today))"
        case .day: unitLabel = "Steps per day"
        case .week: unitLabel = "Average steps per day, by week"
        case .month: unitLabel = "Average steps per day, by month"
        }
        return VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: unitLabel)
            StepHistoryChart(buckets: p.buckets, unit: p.bucketUnit, average: period == .day ? nil : p.dailyAverage,
                             usualHourly: p.usualHourly, previousAverage: period == .day ? nil : p.previousDailyAverage,
                             pinned: router.walkSelectedDate) { bucket in
                if p.bucketUnit == .day {
                    router.walkSelectedDate = bucket.start
                } else if p.bucketUnit != .hour {
                    router.walkSelectedDate = nil
                    selectedBucket = bucket
                }
            }
            .id(period)
            if period != .day {
                HStack(spacing: Space.m) {
                    legendItem(AnyView(Capsule().fill(Palette.ink.opacity(0.55)).frame(width: 12, height: 1.5)), "avg")
                    legendItem(AnyView(Capsule().fill(Palette.tertiaryInk).frame(width: 12, height: 1.5)), "before")
                    legendItem(AnyView(Circle().strokeBorder(Palette.tertiaryInk, lineWidth: 1.25).frame(width: 7, height: 7)), "no record")
                    legendItem(AnyView(Capsule().fill(Palette.signal).frame(width: 10, height: 3)), "zero")
                }
                Text(p.bucketUnit == .day ? "Tap or drag across the bars to inspect a day." : "Tap a bar to see that \(p.bucketUnit == .week ? "week" : "month").")
                    .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
            }
        }
        .card(padding: Space.l)
    }

    func legendItem(_ mark: AnyView, _ text: String) -> some View {
        HStack(spacing: 4) {
            mark
            Text(text.uppercased()).font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk)
        }
    }

    func bucketPanel(_ b: ChartBucket, s: HealthSnapshot) -> some View {
        let end = b.start.adding(days: max(0, b.dayCount - 1))
        let days = s.ctx.history.values(.steps, in: DateSpan(b.start, end))
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow(text: "\(Fmt.shortDate(b.start)) – \(Fmt.shortDate(end))", icon: "bl.calendar", color: Palette.cobalt)
                Spacer()
                Button { selectedBucket = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.tertiaryInk) }
                    .accessibilityLabel("Close")
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(b.value.map(Fmt.int) ?? "—").font(Typo.number(32)).monospacedDigit().foregroundStyle(Palette.ink)
                Text("steps a day").foregroundStyle(Palette.secondaryInk)
            }
            Text("\(days.count) of \(b.dayCount) days have records · total \(Fmt.int(days.values.reduce(0, +)))")
                .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            if let best = days.max(by: { $0.value < $1.value }) {
                Button { router.walkSelectedDate = best.key; selectedBucket = nil } label: {
                    Text("Biggest day: \(Fmt.dayLabel(best.key)) · \(Fmt.int(best.value))").font(Typo.geist(13, .semibold, relativeTo: .footnote))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.cobalt)
            }
        }
        .card(tone: .tinted(Palette.cobalt))
    }

    // MARK: Facts

    func measured(_ s: HealthSnapshot, period: WalkPeriod) -> some View {
        let p = summary(s, period)
        let columns = [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
        return VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Measured", subtitle: "Facts from your records for \(period == .day ? "today" : period.title.lowercased())")
            VStack(alignment: .leading, spacing: Space.l) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                    StatTile(title: "Total", value: Fmt.int(p.total))
                    StatTile(title: "Median day", value: p.median.map(Fmt.int) ?? "—")
                    StatTile(title: "Days recorded", value: "\(p.daysWithData)", caption: "of \(p.span.dayCount)")
                    StatTile(title: "Highest", value: p.highest.map { Fmt.int($0.value) } ?? "—", caption: p.highest.map { Fmt.dayLabel($0.date) })
                    StatTile(title: "Lowest", value: p.lowest.map { Fmt.int($0.value) } ?? "—", caption: p.lowest.map { Fmt.dayLabel($0.date) })
                    StatTile(title: "Near usual", value: p.activeThreshold == nil ? "—" : "\(p.activeDays)",
                             caption: p.activeThreshold.map { "days ≥ \(Fmt.int($0))" })
                    StatTile(title: "Weekdays", value: p.weekdayAverage.map(Fmt.int) ?? "—", caption: "avg / day")
                    StatTile(title: "Weekends", value: p.weekendAverage.map(Fmt.int) ?? "—", caption: "avg / day")
                    StatTile(title: "Day-to-day", value: p.variability.map { "±\(Fmt.percent($0))" } ?? "—", caption: "variability")
                }
                Divider()
                HStack {
                    StatTile(title: "7-day average", value: s.average7.map { Fmt.int($0.value) } ?? "—")
                    StatTile(title: "30-day average", value: s.average30.map { Fmt.int($0.value) } ?? "—")
                    StatTile(title: "90-day average", value: s.average90.map { Fmt.int($0.value) } ?? "—")
                }
            }
            .card(padding: Space.l)
        }
    }

    // MARK: Interpretation

    static let walkingKinds: Set<InsightKind> = [.baselineChange, .consistency, .momentum, .dayOfWeek, .weekdayDecline,
                                                 .timing, .personalBest, .longTermChange, .pace, .rebound, .noteContext]

    @ViewBuilder
    func meaning(_ s: HealthSnapshot) -> some View {
        let insights = s.allInsights.filter { Self.walkingKinds.contains($0.kind) }.prefix(4)
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "What it means", subtitle: "Interpretations Blith drew from the facts above")
            if insights.isEmpty && s.patterns.isEmpty {
                EmptyStateView(symbol: "bl.calendar", title: "Still learning",
                               message: "Patterns appear after a few weeks of history.")
            }
            ForEach(Array(insights)) { insight in
                InsightCard(insight: insight, onWhy: { router.sheet = .insight(insight) },
                            onOpen: { router.open(insight.link, snapshot: s) })
            }
            if !s.patterns.isEmpty {
                VStack(alignment: .leading, spacing: Space.l) {
                    Eyebrow(text: "How you tend to walk", icon: "bl.steptrail", color: Palette.cobalt)
                    ForEach(s.patterns) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.text).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                            Text(p.detail).font(Typo.caption).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if s.weekdayPattern.medians.compactMap({ $0 }).count >= 5 {
                        Divider()
                        Text("Typical day of the week").font(Typo.cardTitle)
                        WeekdayBars(pattern: s.weekdayPattern, firstWeekday: s.ctx.profile.firstWeekday)
                    }
                    if let tod = s.timeOfDay {
                        Divider()
                        Text("When you move · \(Fmt.percent(tod.shareBefore4PM)) before 4 PM").font(Typo.cardTitle)
                        TimeOfDayBars(profile: tod)
                    }
                }
                .card(padding: Space.xl)
            }
        }
    }

    @ViewBuilder
    func signature(_ s: HealthSnapshot) -> some View {
        if s.ctx.history.hourlySteps.count >= 14 {
            VStack(alignment: .leading, spacing: Space.m) {
                Eyebrow(text: "Your walking signature", icon: "bl.sparkle", color: Palette.cobalt)
                Text("Nobody else walks like this.").font(Typo.storySmall).foregroundStyle(Palette.ink)
                WalkSignatureView(history: s.ctx.history, today: s.ctx.today)
                    .frame(maxWidth: .infinity)
                Text("Each ring is a weekday (Monday innermost), each spoke an hour of the day. Bigger, brighter dots mean more steps in that hour, averaged over the last 8 weeks.")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            }
            .card(padding: Space.xl)
        }
    }

    // MARK: Gait

    @ViewBuilder
    func gait(_ s: HealthSnapshot) -> some View {
        let a = HealthAnalytics(s.ctx)
        let units = s.ctx.units
        let metrics: [HealthMetric] = [.walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport]
        let available = metrics.filter { a.rollingAverage($0, days: 28) != nil }
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "How you walk", subtitle: "Measured by your iPhone while you walk")
            if available.isEmpty {
                EmptyStateView(symbol: "speedometer", title: s.availability[.walkingSpeed] == .unsupported ? "Not recorded on this device" : "No walking metrics yet",
                               message: "Walking speed and step length are measured automatically when you carry your iPhone in a pocket. They'll appear here once recorded.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(available.enumerated()), id: \.offset) { index, metric in
                        let recent = a.rollingAverage(metric, days: 28)!
                        let earlier = a.average(metric, in: s.ctx.trailing(28, endingDaysAgo: 57))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.displayName).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                Text("28-day average").font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.value(recent.value, metric: metric, units: units)).font(Typo.geist(17, .semibold, relativeTo: .headline)).monospacedDigit()
                                if let e = earlier, let c = Stats.percentChange(from: e.value, to: recent.value) {
                                    Text("\(Fmt.signedPercent(c)) vs 2 months ago").font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                                }
                            }
                        }
                        .padding(.vertical, Space.m)
                        .accessibilityElement(children: .combine)
                        if index < available.count - 1 { Divider() }
                    }
                }
                .card(padding: Space.l)
                Text("These describe walking patterns, not a diagnosis.").font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    func sessions(_ s: HealthSnapshot) -> some View {
        let recent = s.ctx.history.workouts.filter { $0.start >= AppClock.now().addingTimeInterval(-30 * 86_400) }.sorted { $0.start > $1.start }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Recorded sessions", subtitle: "\(recent.count) in the last 30 days")
                WorkoutList(workouts: Array(recent.prefix(6)), units: s.ctx.units) { w in
                    router.walkSelectedDate = LocalDate(w.start, calendar: .current)
                }
                .card(padding: Space.l)
            }
        }
    }
}

/// Everything recorded on one day, opened by tapping a bar, a chat card or a note.
struct DayPanel: View {
    let date: LocalDate
    let snapshot: HealthSnapshot
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var body: some View {
        let ctx = snapshot.ctx
        let h = ctx.history
        let steps = h.value(.steps, on: date)
        let usual = HealthAnalytics(ctx).usualBefore(date)
        let workouts = h.workouts.filter { LocalDate($0.start, calendar: ctx.calendar) == date }
        let notes = h.events.filter { $0.date == date || ($0.date < date && $0.isActive(on: date)) }
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Eyebrow(text: date == ctx.today ? "Today" : Fmt.dayLabel(date), icon: "bl.calendar", color: Palette.cobalt)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.tertiaryInk) }
                    .accessibilityLabel("Close day")
            }
            if let steps {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.int(steps)).font(Typo.score(44)).foregroundStyle(Palette.ink)
                    Text(steps == 0 ? "steps recorded" : "steps").foregroundStyle(Palette.secondaryInk)
                }
                if let usual {
                    DeltaBadge(change: Stats.percentChange(from: usual.median, to: steps) ?? 0,
                               caption: "vs your usual \(Fmt.weekday(date)) (\(Fmt.int(usual.median)), median of \(usual.observations))")
                }
            } else {
                Text("No steps recorded").font(Typo.storySmall).foregroundStyle(Palette.ink)
                Text("There's no record for this day, which is different from zero steps. Your phone or watch may not have been with you.")
                    .font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
            }
            HStack {
                StatTile(title: "Distance", value: h.value(.distanceWalkingRunning, on: date).map { Fmt.distance($0, units: ctx.units) } ?? "—")
                StatTile(title: "Exercise", value: h.value(.exerciseMinutes, on: date).map { "\(Fmt.int($0)) min" } ?? "—")
                StatTile(title: "Slept (night before)", value: h.sleepNights[date].map { Fmt.duration($0.asleepDuration) } ?? "—")
            }
            if !workouts.isEmpty {
                Divider()
                WorkoutList(workouts: workouts, units: ctx.units)
            }
            ForEach(notes) { note in
                Button { router.open(.body(note.id), snapshot: snapshot) } label: {
                    HStack(spacing: Space.s) {
                        BLIcon(name: "bl.bodynote", size: 16).foregroundStyle(Palette.note)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.title).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            Text(note.date == date ? "Noted for this day" : "Unresolved since \(Fmt.dayLabel(note.date))")
                                .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(Space.m)
                    .background(Palette.noteSoft, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if !notes.isEmpty {
                Text("Notes are shown beside the data; they don't explain it.").font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
            }
            Button {
                router.tab = .ask
                Task { await app.ask.send("Tell me about my walking on \(Fmt.dayLabel(date))", app: app) }
            } label: {
                Label("Ask about this day", systemImage: "sparkles").font(Typo.geist(15, .semibold, relativeTo: .subheadline))
            }
            .glassButton()
        }
        .card(padding: Space.l, tone: .tinted(Palette.cobalt))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct WorkoutList: View {
    let workouts: [WorkoutRecord]
    let units: UnitSystem
    var onSelect: ((WorkoutRecord) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(workouts.enumerated()), id: \.offset) { index, w in
                Button { onSelect?(w) } label: {
                    HStack(spacing: Space.m) {
                        BLIcon(name: w.isWalking ? "bl.walk" : "bl.heart", size: 18)
                            .foregroundStyle(Palette.cobalt)
                            .frame(width: 34, height: 34)
                            .background(Palette.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.activity).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            Text(w.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.duration(w.duration)).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Palette.ink)
                            if let d = w.distanceMeters, d > 0 {
                                Text(Fmt.distance(d, units: units)).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                    .padding(.vertical, Space.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil)
                .accessibilityElement(children: .combine)
                if index < workouts.count - 1 { Divider() }
            }
        }
    }
}


/// Load: how much the day asked of the body, on a 0–10 logarithmic scale, against the person's
/// usual range, with the inputs behind it.
struct LoadSection: View {
    let snapshot: HealthSnapshot
    @State private var selected: LocalDate?

    var body: some View {
        let engine = ScoreEngine(snapshot.ctx)
        let day = selected ?? snapshot.ctx.today
        let load = engine.load(on: day)
        let usual = load?.usualRange.map { ($0.lowerBound / LoadResult.maximum)...($0.upperBound / LoadResult.maximum) }
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .center, spacing: Space.l) {
                ScoreDial(fraction: load.map { $0.value / LoadResult.maximum }, valueText: load.map { Fmt.decimal($0.value) } ?? "–",
                          label: "Load", color: Palette.cyan, size: 140, usual: usual)
                    .id(day)
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(text: day == snapshot.ctx.today ? "Today so far" : Fmt.dayLabel(day), icon: "bl.load", color: Palette.cyan)
                    Text(sentence(load)).font(Typo.storySmall).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    if let r = load?.usualRange {
                        MonoPill(text: "usual \(Fmt.decimal(r.lowerBound))–\(Fmt.decimal(r.upperBound))", color: Palette.cyan)
                    }
                }
            }
            if let load {
                ForEach(load.factors) { FactorRow(factor: $0, color: Palette.cyan) }
                if !load.workouts.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Workouts")
                        ForEach(load.workouts) { w in
                            HStack {
                                BLIcon(name: w.isWalking ? "bl.steps" : "bl.energy", size: 14).foregroundStyle(Palette.cobalt)
                                Text(w.activity).font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(Fmt.duration(w.duration)) · \(w.energyKcal.map { "\(Fmt.int($0)) kcal" } ?? "")")
                                    .font(Typo.number(14)).foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "Last 13 weeks · tap or drag")
                ScoreHeatmap(days: snapshot.scoreHistory, mode: .load, selected: day) { d in withAnimation(Motion.standard) { selected = d } }
            }
            Text("Load combines active energy and exercise minutes. Each point takes more effort than the one before; it isn't a training prescription.")
                .font(Typo.geist(11, relativeTo: .caption2)).foregroundStyle(Palette.tertiaryInk)
        }
        .card(padding: Space.l)
    }

    func sentence(_ l: LoadResult?) -> String {
        guard let l else { return "No activity recorded for this day." }
        guard let r = l.usualRange else { return "Building your usual range from a few more days." }
        if l.value > r.upperBound { return "A bigger day than usual for you." }
        if l.value < r.lowerBound { return "Lighter than your usual day so far." }
        return "Within your usual range."
    }
}

/// Today's steps against the usual by this time of day: the one rule Activity and Today share.
enum PaceStatus {
    case above, usual, below

    /// `TodayPace` carries no usual band, so within 10% either side of the usual by now counts as usual.
    static let threshold = 0.1

    /// Nil until there's a usual by now to compare with.
    init?(_ pace: TodayPace?) {
        guard let change = pace?.change else { return nil }
        if change >= Self.threshold {
            self = .above
        } else if change <= -Self.threshold {
            self = .below
        } else {
            self = .usual
        }
    }

    var text: String {
        switch self {
        case .above: "Above usual"
        case .usual: "As usual"
        case .below: "Below usual"
        }
    }

    var symbol: String {
        switch self {
        case .above: "arrow.up.right"
        case .usual: "minus"
        case .below: "arrow.down.right"
        }
    }

    /// Below the usual is neutral, never a warning colour.
    var color: Color {
        switch self {
        case .above, .usual: Palette.signal
        case .below: Palette.secondaryInk
        }
    }
}
