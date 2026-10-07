import BlithCore
import SwiftUI

/// Which story leads Today: exactly one.
enum TodayHero: Equatable {
    /// Readiness has a score today.
    case readiness(score: Int, band: ScoreBand)
    /// Overnight heart data is arriving and readiness is still learning the usual.
    case calibrating(nights: Int)
    /// No overnight heart data (usually no Apple Watch, or none last night), so movement leads.
    case movement

    init(_ s: HealthSnapshot) {
        let r = s.readiness
        if let score = r.score, let band = r.band {
            self = .readiness(score: score, band: band)
        } else if r.isCalibrating, s.hasOvernightHeart {
            self = .calibrating(nights: r.calibrationDays)
        } else {
            self = .movement
        }
    }
}

/// Today tells one story. The hero is readiness on the horizon against the person's usual, how far
/// calibration has got, or, without overnight heart data, movement against the usual by now. Under it:
/// sleep and load, the live heart, what's worth a look, the overnight readings, and everything else as rows.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollTarget: String?

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    if let s = app.snapshot {
                        let hero = TodayHero(s)
                        heroCard(hero, s).id(hero == .movement ? "movement" : "scores")
                        if hero == .movement { readinessNote(s) }
                        scoreTiles(s)
                        LiveHeartCard(live: app.liveHeart, isDemo: app.isDemo).id("live")
                        if hero != .movement { movementCard(s).id("movement") }
                        worthALook(s).id("insight")
                        overnight(s).id("monitor")
                        more(s)
                        if let history = app.history {
                            SyncStatusLine(history: history, isSyncing: app.isSyncing).padding(.top, Space.s)
                        }
                    } else {
                        EmptyStateView(symbol: "bl.today", title: "Connect Apple Health",
                                       message: "Connect Apple Health to start building your personal baseline.",
                                       actionTitle: "Open settings", action: { router.sheet = .profile })
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollTarget, anchor: .top)
            .task { await LaunchOptions.scroll { scrollTarget = $0 } }
            .onAppear { startLive() }
            .onDisappear { app.liveHeart.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, router.tab == .today { startLive() } else if phase != .active { app.liveHeart.stop() }
            }
            .onChange(of: restingBaseline) { _, value in app.liveHeart.resting = value }
            .scrollIndicators(.hidden)
            .blithBackground(wash: Palette.signal.opacity(0.16))
            .refreshable { await app.refresh(force: true) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $router.showAchievements) { AchievementsView() }
        }
    }

    /// The person's usual resting heart rate, used to place the live rate in a zone.
    var restingBaseline: Double? {
        guard let v = app.snapshot?.monitor.vitals.first(where: { $0.metric == .restingHeartRate }) else { return nil }
        return v.mean ?? v.value
    }

    func startLive() {
        guard app.phase == .ready else { return }
        app.liveHeart.resting = restingBaseline
        app.liveHeart.start(simulated: app.isDemo)
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: AppClock.now())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = app.profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: AppClock.now().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    if app.isDemo { SampleDataBanner() }
                }
                Text(greeting)
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            HStack(spacing: Space.s) {
                StreakChip(days: app.streak.current, checkedIn: app.streak.checkedInToday) { router.showAchievements = true }
                AvatarButton(name: app.profile.name) { router.sheet = .profile }
            }
        }
        .padding(.top, Space.s)
    }

    // MARK: Hero

    @ViewBuilder
    func heroCard(_ hero: TodayHero, _ s: HealthSnapshot) -> some View {
        switch hero {
        case .readiness(let score, let band):
            ReadinessHorizonCard(score: score, band: band,
                                 usual: Stats.usualRange(s.scoreHistory.compactMap(\.readiness).map(Double.init)),
                                 summary: s.readiness.summary) { router.sheet = .readiness(nil) }
        case .calibrating(let nights):
            CalibrationCard(nights: nights)
        case .movement:
            MovementHeroCard(steps: stepsSoFar(s), pace: s.pace, time: timeNow, dayName: dayName(s)) {
                router.open(.walk(.day), snapshot: s)
            }
        }
    }

    /// Under the movement hero: why there's no readiness. Without overnight heart data it says what an
    /// Apple Watch adds; with it, BlithCore's own sentence about the missing night.
    func readinessNote(_ s: HealthSnapshot) -> some View {
        let needsWatch = !s.hasRecordedOvernightHeart
        let title = needsWatch && s.sleepScore == nil ? "Readiness and sleep" : "Readiness"
        let text: String
        if !needsWatch {
            text = s.readiness.summary
        } else if s.sleepScore == nil {
            text = "Readiness and sleep need heart rate and HRV that an Apple Watch measures overnight. Everything else works from your iPhone."
        } else {
            text = "Readiness needs heart rate and HRV that an Apple Watch measures overnight. Everything else works from your iPhone."
        }
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow(text: title)
                Spacer(minLength: Space.s)
                Image(systemName: "applewatch")
                    .font(.subheadline)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(text)")
    }

    // MARK: Sleep and load

    @ViewBuilder
    func scoreTiles(_ s: HealthSnapshot) -> some View {
        if s.sleepScore != nil || s.load != nil {
            HStack(alignment: .top, spacing: Space.m) {
                if let p = s.sleepScore { sleepTile(p, s) }
                if let l = s.load { loadTile(l, s) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func sleepTile(_ p: SleepPerformance, _ s: HealthSnapshot) -> ScoreTile {
        let usual = Stats.usualRange(s.scoreHistory.compactMap(\.sleep).map(Double.init))
        let caption = "\(Fmt.duration(p.asleep)) asleep, need \(Fmt.duration(p.need))"
        let usualWords = usual.map { "Your usual is \(Fmt.int($0.lowerBound)) to \(Fmt.int($0.upperBound))" }
        let spoken: [String?] = ["Sleep \(p.score)", usualWords, caption]
        return ScoreTile(title: "Sleep", value: "\(p.score)", fraction: Double(p.score) / 100,
                         usual: usual.map { ($0.lowerBound / 100)...($0.upperBound / 100) },
                         caption: caption, summary: spoken.compactMap { $0 }.joined(separator: ". "),
                         hint: "Opens sleep") {
            router.open(.sleep(nil), snapshot: s)
        }
    }

    func loadTile(_ l: LoadResult, _ s: HealthSnapshot) -> ScoreTile {
        let caption = l.usualRange.map { "Usual \(Fmt.decimal($0.lowerBound))–\(Fmt.decimal($0.upperBound)) by tonight" } ?? "Learning your usual"
        return ScoreTile(title: "Load", value: Fmt.decimal(l.value), fraction: l.value / LoadResult.maximum,
                         usual: l.usualRange.map { ($0.lowerBound / LoadResult.maximum)...($0.upperBound / LoadResult.maximum) },
                         caption: caption, summary: "Load \(Fmt.decimal(l.value)) of 10. \(caption)",
                         hint: "Opens activity") {
            router.open(.walk(.day), snapshot: s)
        }
    }

    // MARK: Movement

    var timeNow: String { AppClock.now().formatted(date: .omitted, time: .shortened) }

    func dayName(_ s: HealthSnapshot) -> String {
        s.pace?.basis == .sameWeekday ? Fmt.weekday(s.ctx.today) : "typical day"
    }

    /// Steps so far today, or nil when nothing has been recorded yet: never a bare "0 steps".
    func stepsSoFar(_ s: HealthSnapshot) -> Double? {
        guard let steps = s.todaySteps ?? s.pace?.stepsSoFar, steps > 0 else { return nil }
        return steps
    }

    /// Compact movement when the hero isn't already movement: steps by now, the usual by now, status.
    func movementCard(_ s: HealthSnapshot) -> some View {
        let steps = stepsSoFar(s)
        let usual = s.pace?.usualByNow
        let status = PaceStatus(s.pace)
        let time = timeNow
        let spoken: [String?] = ["Movement by \(time)", steps.map { "\(Fmt.int($0)) steps" } ?? "No steps yet today",
                                 usual.map { "Usually \(Fmt.int($0)) by now" }, status?.text]
        return Button { router.open(.walk(.day), snapshot: s) } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Eyebrow(text: "Movement by \(time)")
                    Spacer(minLength: Space.s)
                    if let status {
                        StatusLabel(symbol: status.symbol, text: status.text, color: status.color)
                    }
                }
                if let steps {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(Fmt.int(steps))
                            .font(Typo.score(34))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text("steps")
                            .font(Typo.geist(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("No steps yet today")
                        .font(Typo.cardTitle)
                        .foregroundStyle(Palette.ink)
                }
                if let usual {
                    Text("Usually \(Fmt.int(usual)) by now")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .card(padding: Space.l)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken.compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint("Opens today's activity")
    }

    // MARK: Lists

    var rowDivider: some View { Rectangle().fill(Palette.separator).frame(height: 1) }

    func sectionLabel(_ text: String) -> some View {
        Eyebrow(text: text).accessibilityAddTraits(.isHeader)
    }

    /// Rows separated by hairlines.
    func rowList(_ rows: [TodayRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { rowDivider }
                row
            }
        }
    }

    // MARK: Worth a look

    /// Overnight readings outside the usual (the only rust on Today) and the featured insight.
    @ViewBuilder
    func worthALook(_ s: HealthSnapshot) -> some View {
        let rows = worthALookRows(s)
        let nothingOutside = s.monitor.measured > 0 && !s.monitor.vitals.contains(where: { $0.status == .above || $0.status == .below })
        if nothingOutside || !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                sectionLabel("Worth a look")
                if nothingOutside {
                    Text("Nothing outside your usual today.")
                        .font(Typo.geist(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.vertical, Space.s)
                    if !rows.isEmpty { rowDivider }
                }
                rowList(rows)
            }
            .card(padding: Space.l)
        }
    }

    func worthALookRows(_ s: HealthSnapshot) -> [TodayRow] {
        var rows = s.monitor.vitals.filter { $0.status == .above || $0.status == .below }.map { outsideRow($0) }
        rows += s.feed.map { insightRow($0) }
        return rows
    }

    func outsideRow(_ v: VitalReading) -> TodayRow {
        let value = v.value.map { v.metric.format($0) }
        let detail = v.range.map { "\(v.status.text) (\(v.metric.formatRange($0)))" } ?? v.status.text
        return TodayRow(title: v.metric.shortName, detail: detail, value: value, ring: Palette.note,
                        hint: "Opens this reading over time") {
            router.sheet = .vital(v.metric)
        }
    }

    func insightRow(_ insight: Insight) -> TodayRow {
        TodayRow(title: insight.headline, detail: insight.explanation, ring: Palette.tertiaryInk,
                 hint: "Shows why you're seeing this") {
            router.sheet = .insight(insight)
        }
    }

    // MARK: Overnight readings

    /// Every overnight reading Blith has seen lately; metrics never recorded (no sensor) stay hidden.
    @ViewBuilder
    func overnight(_ s: HealthSnapshot) -> some View {
        let readings = s.monitor.vitals.filter { $0.value != nil || !$0.recent.isEmpty }
        if !readings.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                sectionLabel("Overnight readings")
                rowList(readings.map { readingRow($0) })
                Text("Your usual for each reading comes from your own last 30 nights. A reading outside it isn't a diagnosis.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xs)
            }
            .card(padding: Space.l)
        }
    }

    func readingRow(_ v: VitalReading) -> TodayRow {
        TodayRow(title: v.metric.shortName,
                 status: StatusLabel(symbol: v.status.symbol, text: v.status.text, color: v.status.color),
                 value: v.value.map { v.metric.format($0) },
                 hint: "Opens this reading over time") {
            router.sheet = .vital(v.metric)
        }
    }

    // MARK: More

    /// Everything that left the top of Today, one row each, only when there's data behind it.
    @ViewBuilder
    func more(_ s: HealthSnapshot) -> some View {
        let rows = moreRows(s)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                sectionLabel("More")
                rowList(rows)
            }
            .card(padding: Space.l)
        }
    }

    func moreRows(_ s: HealthSnapshot) -> [TodayRow] {
        var rows: [TodayRow] = []
        let week = s.scoreHistory.suffix(7).compactMap(\.readiness)
        if let average = Stats.mean(week.map(Double.init)) {
            rows.append(TodayRow(title: "Your week", detail: "Readiness averaged \(Fmt.int(average)) over the last 7 days",
                                 hint: "Opens readiness") {
                router.sheet = .readiness(nil)
            })
        }
        if !app.achievements.isEmpty {
            let earned = app.achievements.filter(\.isUnlocked).count
            rows.append(TodayRow(title: "Milestones", detail: "\(earned) of \(app.achievements.count) earned from your own records",
                                 hint: "Opens milestones") {
                router.showAchievements = true
            })
        }
        if let w = s.weight {
            let units = s.ctx.units
            let trend = "Trend \(Fmt.weight(w.trendNow, units: units))"
            let detail = w.change30Days.map { "\(trend), \(Fmt.weightChange($0, units: units)) in 30 days" } ?? trend
            rows.append(TodayRow(title: "Weight", detail: detail, hint: "Opens your weight trend") {
                router.sheet = .weight
            })
        }
        if let vo2 = s.ctx.history.values(.vo2Max, in: s.ctx.trailing(180)).max(by: { $0.key < $1.key }) {
            rows.append(TodayRow(title: "Cardio fitness", detail: "VO₂ max \(Fmt.decimal(vo2.value)), estimated \(Fmt.shortDate(vo2.key))",
                                 hint: "Opens cardio fitness over time") {
                router.sheet = .vital(.vo2Max)
            })
        }
        let notes = s.ctx.history.bodyNotes
        if let note = notes.first(where: { $0.isActive(on: s.ctx.today) }) ?? notes.first {
            let state = note.isActive(on: s.ctx.today) ? "open" : "resolved"
            rows.append(TodayRow(title: "Body notes", detail: "\(note.title) · \(state)", hint: "Opens the note on the body map") {
                router.open(.body(note.id), snapshot: s)
            })
        }
        return rows
    }
}

extension HealthSnapshot {
    /// Whether overnight heart data (HRV or resting heart rate, which an Apple Watch records) is
    /// arriving recently enough that Health doesn't count it as stale.
    var hasOvernightHeart: Bool {
        [HealthMetric.hrv, .restingHeartRate].contains(where: { availability[$0] == .available })
    }

    /// Whether HRV or resting heart rate has ever been recorded, even if the newest value is old (an
    /// Apple Watch owner who skipped wearing it overnight). Only without this does Today suggest a Watch.
    var hasRecordedOvernightHeart: Bool {
        [HealthMetric.hrv, .restingHeartRate].contains(where: { availability[$0] == .available || availability[$0] == .stale })
    }
}

extension VitalReading.Status {
    /// The status in words; always shown with `symbol`.
    var text: String {
        switch self {
        case .within: "Within your usual"
        case .above: "Above your usual"
        case .below: "Below your usual"
        case .learning: "Learning your usual"
        case .noData: "No reading last night"
        }
    }

    var symbol: String {
        switch self {
        case .within: "checkmark"
        case .above: "arrow.up"
        case .below: "arrow.down"
        case .learning: "ellipsis"
        case .noData: "minus"
        }
    }

    /// Rust only for a reading outside the usual.
    var color: Color {
        switch self {
        case .within: Palette.secondaryInk
        case .above, .below: Palette.note
        case .learning, .noData: Palette.tertiaryInk
        }
    }
}

extension HealthMetric {
    var shortName: String {
        switch self {
        case .restingHeartRate: "Resting heart rate"
        case .hrv: "HRV"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Blood oxygen"
        case .wristTemperature: "Wrist temperature"
        case .vo2Max: "Cardio fitness"
        default: displayName
        }
    }

    var icon: String {
        switch self {
        case .restingHeartRate, .walkingHeartRate: "bl.rhr"
        case .hrv: "bl.hrv"
        case .respiratoryRate: "bl.resp"
        case .oxygenSaturation: "bl.spo2"
        case .wristTemperature: "bl.temp"
        case .vo2Max: "bl.vo2"
        case .steps: "bl.steps"
        case .activeEnergy: "bl.energy"
        case .flightsClimbed: "bl.stairs"
        case .distanceWalkingRunning: "bl.distance"
        case .sleepDuration: "bl.sleep"
        case .weight, .bodyFat: "bl.weight"
        default: "bl.trend"
        }
    }

    var tint: Color {
        switch self {
        case .restingHeartRate, .walkingHeartRate, .vo2Max: Palette.heart
        case .hrv: Palette.recovery
        case .respiratoryRate: Palette.cyan
        case .oxygenSaturation: Palette.signal
        case .wristTemperature: Palette.sleep
        case .sleepDuration: Palette.sleep
        case .weight, .bodyFat: Palette.weight
        default: Palette.cobalt
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .restingHeartRate, .walkingHeartRate: "\(Fmt.int(v)) bpm"
        case .hrv: "\(Fmt.int(v)) ms"
        case .respiratoryRate: "\(Fmt.decimal(v)) /min"
        case .oxygenSaturation: "\(Fmt.decimal(v * 100))%"
        case .wristTemperature: "\(Fmt.decimal(v, digits: 2))°"
        case .vo2Max: Fmt.decimal(v)
        default: Fmt.value(v, metric: self, units: .metric)
        }
    }

    /// A usual range with the unit written once: "58–62 bpm".
    func formatRange(_ r: ClosedRange<Double>) -> String {
        switch self {
        case .restingHeartRate, .walkingHeartRate: "\(Fmt.int(r.lowerBound))–\(Fmt.int(r.upperBound)) bpm"
        case .hrv: "\(Fmt.int(r.lowerBound))–\(Fmt.int(r.upperBound)) ms"
        case .respiratoryRate: "\(Fmt.decimal(r.lowerBound))–\(Fmt.decimal(r.upperBound)) /min"
        case .oxygenSaturation: "\(Fmt.decimal(r.lowerBound * 100))–\(Fmt.decimal(r.upperBound * 100))%"
        case .wristTemperature: "\(Fmt.decimal(r.lowerBound, digits: 2))–\(Fmt.decimal(r.upperBound, digits: 2))°"
        default: "\(format(r.lowerBound))–\(format(r.upperBound))"
        }
    }
}

/// All milestones, earned and in progress.
struct AchievementsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "\(app.achievements.filter(\.isUnlocked).count) of \(app.achievements.count) earned", icon: "bl.medal", color: Palette.signal)
                        Text("Milestones").font(Typo.pageTitle).foregroundStyle(Palette.ink)
                        Text("Each one is a fact from your own records, with the day it became true. Nothing expires and nothing resets.")
                            .font(Typo.body).foregroundStyle(Palette.secondaryInk)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.l)], spacing: Space.xl) {
                        ForEach(app.achievements) { AchievementBadge(achievement: $0, size: 72) }
                    }
                    .card(padding: Space.xl)
                }
                .padding(Space.page)
            }
            .blithBackground(wash: Palette.signal.opacity(0.14))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The check-in streak, small: a flame and the day count. Opens the milestones.
struct StreakChip: View {
    let days: Int
    let checkedIn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                BLIcon(name: "bl.streak", size: 14)
                Text("\(days)").font(Typo.number(16)).monospacedDigit()
            }
            .foregroundStyle(checkedIn ? Palette.mint : Palette.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Palette.raised))
            .overlay(Capsule().strokeBorder((checkedIn ? Palette.mint : Palette.hairline).opacity(checkedIn ? 0.45 : 1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(days) day check-in streak")
        .accessibilityHint("Opens milestones")
    }
}
