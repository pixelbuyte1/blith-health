import BlithCore
import Charts
import SwiftUI

/// Maps a structured assistant block to a trusted native component. The model can only pick
/// from these; it never produces UI. Every block is tappable and opens the matching screen.
struct ChatBlockView: View {
    let block: AssistantBlock
    let open: (DeepLink) -> Void
    @Environment(AppModel.self) private var app

    var units: UnitSystem { app.profile.units }

    @ViewBuilder
    var body: some View {
        if case .bodyNoteProposal(let note) = block {
            BodyNoteProposalCard(proposal: note, open: open)
        } else {
            linkedCard
        }
    }

    var linkedCard: some View {
        Button {
            if let link = block.link { open(link) }
        } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                content
                if block.link != nil {
                    HStack(spacing: Space.xs) {
                        Text(openLabel).font(Typo.geist(12, .semibold, relativeTo: .caption))
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(tint)
                }
            }
            .card(padding: Space.l, tone: .tinted(tint))
        }
        .buttonStyle(.plain)
        .accessibilityHint(openLabel)
    }

    var openLabel: String {
        switch block.link {
        case .walk?: "Open in Walk"
        case .walkDay?: "Open this day"
        case .sleep?: "Open sleep"
        case .weight?: "Open weight"
        case .insight?: "See why"
        case .sources?: "Open sources"
        case .body?: "Open on the body map"
        case .readiness?: "Open readiness"
        case .today?, nil: "Open"
        }
    }

    var tint: Color {
        switch block {
        case .sleepTimeline: Palette.sleep
        case .weightChart: Palette.weight
        case .bodyNote: Palette.note
        case .insight(let i): i.tint
        case .scores(let b): b.band == nil ? Palette.cobalt : Palette.band(b.band)
        default: Palette.cobalt
        }
    }

    @ViewBuilder
    var content: some View {
        switch block {
        case .stepChart(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Steps · \(b.title)", symbol: "bl.walk")
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.int(b.average ?? 0)).font(Typo.number(28)).monospacedDigit()
                    Text(b.period == .day ? "so far" : "avg / day").foregroundStyle(Palette.secondaryInk)
                    Spacer()
                    if let c = b.change { DeltaBadge(change: c) }
                }
                StepHistoryChart(buckets: b.buckets, unit: b.bucketUnit, average: b.period == .day ? nil : b.average, height: 150, interactive: false)
                if b.bucketUnit == .day && b.buckets.count <= 7 {
                    HStack(spacing: 0) {
                        ForEach(b.buckets) { bucket in
                            VStack(spacing: 2) {
                                Text(Fmt.weekdayShort[bucket.start.weekday - 1]).font(Typo.geist(11, relativeTo: .caption2)).foregroundStyle(Palette.secondaryInk)
                                Text(bucket.value.map { Fmt.decimal($0 / 1000) + "k" } ?? "—").font(Typo.geist(12, .semibold, relativeTo: .caption)).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        case .walkingSummary(let b):
            VStack(alignment: .leading, spacing: Space.m) {
                header("Walking", symbol: "bl.walk")
                HStack {
                    StatTile(title: "Today", value: b.todaySteps.map(Fmt.int) ?? "—", caption: b.usualByNow.map { "usual by now \(Fmt.int($0))" })
                    StatTile(title: "7-day avg", value: b.average7.map(Fmt.int) ?? "—", caption: b.changeVsBaseline.map { "\(Fmt.signedPercent($0)) vs 4-wk" })
                    StatTile(title: "30-day avg", value: b.average30.map(Fmt.int) ?? "—")
                }
                Chart {
                    ForEach(b.last7, id: \.date) { d in
                        BarMark(x: .value("Day", Fmt.weekdayShort[d.date.weekday - 1]), y: .value("Steps", d.value))
                            .foregroundStyle(Palette.signal)
                            .cornerRadius(4)
                    }
                    if let base = b.baseline28 {
                        RuleMark(y: .value("Baseline", base))
                            .foregroundStyle(Palette.baseline)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
            }
        case .weightChart(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Weight", symbol: "bl.weight", color: Palette.weight)
                HStack {
                    StatTile(title: "Latest", value: Fmt.weight(b.latest, units: units))
                    StatTile(title: "Trend", value: Fmt.weight(b.trend, units: units))
                    StatTile(title: "30 days", value: b.change30.map { Fmt.weightChange($0, units: units) } ?? "—")
                }
                WeightTrendChart(points: b.points, goalKg: b.goalKg, units: units, height: 140, interactive: false)
            }
        case .sleepTimeline(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Sleep · \(Fmt.dayLabel(b.night.date))", symbol: "bl.sleep", color: Palette.sleep)
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.duration(b.asleep)).font(Typo.number(28)).monospacedDigit()
                    if let d = b.differenceFromAverage {
                        Text("\(Fmt.duration(abs(d))) \(d >= 0 ? "more" : "less") than usual").font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                    }
                }
                SleepTimelineView(night: b.night, height: 90)
            }
        case .workouts(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Workouts", symbol: "figure.mixed.cardio")
                WorkoutList(workouts: b.workouts, units: units)
            }
        case .comparison(let b):
            VStack(alignment: .leading, spacing: Space.m) {
                header("\(b.metric.displayName) · daily average", symbol: "arrow.left.arrow.right")
                HStack(alignment: .bottom, spacing: Space.l) {
                    comparisonColumn(b.labelA, b.valueA, b.metric, max(b.valueA, b.valueB), highlight: true)
                    comparisonColumn(b.labelB, b.valueB, b.metric, max(b.valueA, b.valueB), highlight: false)
                }
                if let c = b.change { DeltaBadge(change: c, caption: "vs \(b.labelB)") }
            }
        case .metricCard(let b):
            VStack(alignment: .leading, spacing: Space.xs) {
                header(b.title, symbol: "number")
                Text(Fmt.value(b.value, metric: b.metric, units: units)).font(Typo.number(28)).monospacedDigit()
                Text(b.caption).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
            }
        case .insight(let i):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Insight", symbol: "bl.sparkle", color: i.tint)
                Text(i.headline).font(Typo.cardTitle)
                if let e = i.emphasis {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(e).font(Typo.number(24))
                        if let c = i.emphasisCaption { Text(c).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk) }
                    }
                }
                Text(i.explanation).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
            }
        case .daySteps(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header(Fmt.dayLabel(b.date), symbol: "bl.calendar")
                if let steps = b.steps {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(Fmt.int(steps)).font(Typo.number(30)).monospacedDigit()
                        Text("steps").foregroundStyle(Palette.secondaryInk)
                    }
                    if let usual = b.usual {
                        comparisonBars(day: steps, usual: usual, weekday: Fmt.weekday(b.date), n: b.usualObservations)
                    }
                } else {
                    Text("No steps recorded that day").font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                }
                if let hourly = b.hourly, hourly.reduce(0, +) > 0 {
                    Chart(Array(hourly.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("Hour", item.offset), y: .value("Steps", item.element))
                            .foregroundStyle(Palette.cobalt.opacity(0.7))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 44)
                }
            }
        case .scores(let b):
            VStack(alignment: .leading, spacing: Space.m) {
                header("Scores · \(Fmt.dayLabel(b.date))", symbol: "bl.readiness", color: Palette.band(b.band))
                HStack(spacing: 0) {
                    ScoreDial(fraction: b.sleep.map { Double($0) / 100 }, valueText: b.sleep.map(String.init) ?? "–", unit: b.sleep == nil ? nil : "%",
                              label: "Sleep", color: Palette.sleep, size: 76)
                        .frame(maxWidth: .infinity)
                    ScoreDial(fraction: b.readiness.map { Double($0) / 100 }, valueText: b.readiness.map(String.init) ?? "\(b.calibrationDays)",
                              unit: b.readiness == nil ? "/\(ScoreEngine.calibrationDays)" : "%", label: b.readiness == nil ? "Calibrating" : "Readiness",
                              color: b.readiness == nil ? Palette.secondaryInk : Palette.band(b.band), size: 104)
                    ScoreDial(fraction: b.load.map { $0 / LoadResult.maximum }, valueText: b.load.map { Fmt.decimal($0) } ?? "–",
                              label: "Load", color: Palette.cyan, size: 76,
                              usual: b.loadUsual.flatMap { $0.count == 2 ? ($0[0] / LoadResult.maximum)...($0[1] / LoadResult.maximum) : nil })
                        .frame(maxWidth: .infinity)
                }
                ForEach(b.factors.prefix(3)) { FactorRow(factor: $0, color: Palette.band(b.band)) }
            }
        case .bodyNote(let n):
            VStack(alignment: .leading, spacing: Space.xs) {
                header("Body note · \(n.bodyRegion?.displayName ?? "General")", symbol: "bl.bodynote", color: Palette.note)
                Text(n.title).font(Typo.geist(17, .semibold, relativeTo: .headline))
                if let text = n.note, !text.isEmpty { Text(text).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk) }
                Text("Happened \(Fmt.dayLabel(n.date)) · written \(n.createdAt.formatted(date: .abbreviated, time: .omitted))\(n.resolvedDate.map { " · resolved \(Fmt.shortDate($0))" } ?? "")")
                    .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
            }
        case .bodyNoteProposal:
            EmptyView()
        case .sources(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Sources · \(b.metric.displayName)", symbol: "square.stack.3d.up")
                let total = b.sources.reduce(0) { $0 + $1.value }
                ForEach(b.sources) { s in
                    HStack {
                        Text(s.source.name).font(Typo.geist(15, relativeTo: .subheadline))
                        Spacer()
                        Text(total > 0 ? Fmt.percent(s.value / total) : "—").font(Typo.geist(15, .semibold, relativeTo: .subheadline)).monospacedDigit()
                    }
                }
            }
        }
    }

    func header(_ title: String, symbol: String, color: Color = Palette.accent) -> some View {
        Eyebrow(text: title, icon: symbol.hasPrefix("bl.") ? symbol : nil, color: color)
    }

    func comparisonBars(day: Double, usual: Double, weekday: String, n: Int) -> some View {
        let maxV = max(day, usual, 1)
        return VStack(alignment: .leading, spacing: 6) {
            bar("That day", day, maxV, Palette.cobalt)
            bar("Usual \(weekday) (\(n))", usual, maxV, Palette.baseline)
        }
    }

    func bar(_ label: String, _ v: Double, _ maxV: Double, _ color: Color) -> some View {
        HStack(spacing: Space.s) {
            Text(label).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk).frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(color.gradient).frame(width: max(6, geo.size.width * v / maxV))
            }
            .frame(height: 10)
            Text(Fmt.int(v)).font(Typo.geist(12, .semibold, relativeTo: .caption)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }

    func comparisonColumn(_ label: String, _ value: Double, _ metric: HealthMetric, _ maxValue: Double, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlight ? AnyShapeStyle(Palette.signalBright) : AnyShapeStyle(Palette.quiet))
                .frame(height: max(8, 80 * (maxValue > 0 ? value / maxValue : 0)))
            Text(Fmt.value(value, metric: metric, units: units)).font(Typo.geist(17, .semibold, relativeTo: .headline)).monospacedDigit()
            Text(label).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A body note Ask prepared from what the person said. Nothing is saved until they tap Add note;
/// Edit opens the same editor as the Body tab. Once saved (same id) the card says so and links to the body map.
struct BodyNoteProposalCard: View {
    let proposal: HealthEvent
    let open: (DeepLink) -> Void
    @Environment(AppModel.self) private var app
    @State private var editing: HealthEvent?
    @State private var saving = false

    var saved: HealthEvent? { app.history?.events.first { $0.id == proposal.id } }

    var body: some View {
        let note = saved ?? proposal
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: saved == nil ? "Add a body note?" : "Body note added", icon: "bl.bodynote", color: Palette.note)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(note.title)
                    .font(Typo.geist(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                if let text = note.note, !text.isEmpty {
                    Text(text).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                }
                Text(details(note))
                    .font(Typo.geist(12, relativeTo: .caption))
                    .foregroundStyle(Palette.secondaryInk)
            }
            if saved == nil {
                Text("Blith can't assess injuries or pain. If it gets worse or doesn't ease, see a clinician.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.m) {
                    Button("Edit") { editing = proposal }
                        .buttonStyle(.bordered)
                    Button("Add note") { add(proposal) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.note)
                        .disabled(saving)
                }
            } else {
                Button { open(.body(proposal.id)) } label: {
                    HStack(spacing: Space.xs) {
                        Text("Open on the body map").font(Typo.geist(12, .semibold, relativeTo: .caption))
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Palette.note)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: Space.l, tone: .tinted(Palette.note))
        .sheet(item: $editing) { draft in
            BodyNoteEditor(note: draft, isNew: true) { edited in
                add(edited)
            } onDelete: { _ in }
        }
    }

    func details(_ note: HealthEvent) -> String {
        var parts = [note.bodyRegion?.displayName ?? "General", note.kindLabel, "Happened \(Fmt.dayLabel(note.date))"]
        if let resolved = note.resolvedDate { parts.append("resolved \(Fmt.shortDate(resolved))") }
        return parts.joined(separator: " · ")
    }

    func add(_ note: HealthEvent) {
        guard !saving, saved == nil else { return }
        saving = true
        var n = note
        n.createdAt = AppClock.now()
        let toSave = n
        Task {
            await app.saveNote(toSave)
            saving = false
        }
    }
}
