import Foundation

public struct ToolDefinition: Sendable, Hashable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    /// OpenAI-compatible function tool JSON.
    public var json: JSONValue {
        ["type": "function", "function": ["name": .string(name), "description": .string(description), "parameters": parameters]]
    }
}

/// Result of running one tool: JSON for the model, plus widgets and evidence for the app.
public struct ToolOutput: Sendable {
    public var result: JSONValue
    public var blocks: [AssistantBlock]
    public var evidence: [EvidenceItem]
    /// A widget the app can show if the model doesn't explicitly ask for one.
    public var suggestedBlock: AssistantBlock?
    /// Shown alongside the suggested block when the model doesn't pick widgets itself.
    public var extraBlocks: [AssistantBlock]

    public init(result: JSONValue, blocks: [AssistantBlock] = [], evidence: [EvidenceItem] = [], suggestedBlock: AssistantBlock? = nil,
                extraBlocks: [AssistantBlock] = []) {
        self.result = result
        self.blocks = blocks
        self.evidence = evidence
        self.suggestedBlock = suggestedBlock
        self.extraBlocks = extraBlocks
    }
}

/// The deterministic query layer the assistant calls. Every number an answer contains comes
/// from here or from `calculate` — the model explains, it never does sums itself.
public struct HealthAssistantTools: Sendable {
    public let snapshot: HealthSnapshot

    public init(snapshot: HealthSnapshot) { self.snapshot = snapshot }

    var ctx: AnalyticsContext { snapshot.ctx }
    var a: HealthAnalytics { HealthAnalytics(ctx) }
    var units: UnitSystem { ctx.units }

    // MARK: Schema

    static let metricEnum: JSONValue = .array(ToolMetric.allCases.map { .string($0.rawValue) })

    static func object(_ props: [String: JSONValue], required: [String] = []) -> JSONValue {
        ["type": "object", "properties": .object(props), "required": .array(required.map(JSONValue.string))]
    }

    static let date: JSONValue = ["type": "string", "description": "YYYY-MM-DD, local date"]

    static let regionEnum: JSONValue = .array(BodyRegion.allCases.map { .string($0.rawValue) })

    public static let definitions: [ToolDefinition] = [
        ToolDefinition(name: "get_today_summary",
                       description: "Today so far: steps vs the user's usual for this weekday at this time, distance, exercise, 7/30-day averages, last night's sleep, weight trend.",
                       parameters: object([:])),
        ToolDefinition(name: "get_walking_summary",
                       description: "Walking/steps statistics for a period: daily average, previous-period average and change, total, highest/lowest day, median, active days, weekday vs weekend.",
                       parameters: object(["period": ["type": "string", "enum": ["day", "week", "month", "6m", "year", "all"]]], required: ["period"])),
        ToolDefinition(name: "get_metric_summary",
                       description: "Summary of any metric between two dates: daily average, total (for cumulative metrics), min and max days, days with data.",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum], "start_date": date, "end_date": date],
                                          required: ["metric", "start_date", "end_date"])),
        ToolDefinition(name: "get_time_series",
                       description: "Values of a metric by day, week or month between two dates (max 120 points).",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum],
                                           "interval": ["type": "string", "enum": ["day", "week", "month"]],
                                           "start_date": date, "end_date": date], required: ["metric", "interval", "start_date", "end_date"])),
        ToolDefinition(name: "compare_periods",
                       description: "Compare a metric's daily average between period A and period B. Returns both averages and the percent change from B to A.",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum],
                                           "a_start": date, "a_end": date, "b_start": date, "b_end": date],
                                          required: ["metric", "a_start", "a_end", "b_start", "b_end"])),
        ToolDefinition(name: "get_personal_baseline",
                       description: "The user's own normal for a metric over a trailing window of complete days (mean and median), plus typical value per weekday for steps.",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum],
                                           "window_days": ["type": "integer", "enum": [7, 28, 90]]], required: ["metric"])),
        ToolDefinition(name: "get_day_detail",
                       description: "Everything about one day: steps and when they happened, comparison with the usual for that weekday, distance, workouts, the night's sleep, weight.",
                       parameters: object(["date": date], required: ["date"])),
        ToolDefinition(name: "get_weight_trend",
                       description: "Weight: latest reading, smoothed trend, 30-day change, weekly rate, this week's reading range, goal distance.",
                       parameters: object([:])),
        ToolDefinition(name: "get_readiness",
                       description: "Blith's daily scores for a day (defaults to today): readiness 0-100 from overnight HRV and resting heart rate vs the user's 30-day baseline plus sleep performance; sleep performance 0-100 vs personal sleep need; load 0-10 from active energy and exercise; and the health monitor (resting HR, HRV, respiratory rate, blood oxygen, wrist temperature vs personal ranges). Scores describe signals relative to the user's usual, never a medical assessment.",
                       parameters: object(["date": date])),
        ToolDefinition(name: "get_sleep_summary",
                       description: "Sleep for a night (defaults to last night): time asleep, stages, bed/wake times, vs the 28-night average.",
                       parameters: object(["date": ["type": "string", "description": "Wake-up date YYYY-MM-DD; omit for last night"]])),
        ToolDefinition(name: "get_workout_history",
                       description: "Recorded workouts between two dates (defaults to the last 30 days).",
                       parameters: object(["start_date": date, "end_date": date])),
        ToolDefinition(name: "find_personal_best",
                       description: "Best (or lowest) day or week for a metric within a range (defaults to all history).",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum],
                                           "unit": ["type": "string", "enum": ["day", "week"]],
                                           "lowest": ["type": "boolean"], "start_date": date, "end_date": date], required: ["metric"])),
        ToolDefinition(name: "find_anomalies",
                       description: "Days where a metric was more than 2 standard deviations from the user's preceding 4-week normal.",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum], "start_date": date, "end_date": date], required: ["metric"])),
        ToolDefinition(name: "find_correlation",
                       description: "Correlation between two metrics (metric_a on a day vs metric_b lag_days later). Correlation is not causation; always say so.",
                       parameters: object(["metric_a": ["type": "string", "enum": metricEnum], "metric_b": ["type": "string", "enum": metricEnum],
                                           "lag_days": ["type": "integer"], "start_date": date, "end_date": date], required: ["metric_a", "metric_b"])),
        ToolDefinition(name: "get_body_notes",
                       description: "The user's own body notes (event date, date entered, region, their words, resolved or not). Notes are the user's descriptions, not diagnoses; an unresolved note is not proof of a current condition.",
                       parameters: object(["start_date": date, "end_date": date])),
        ToolDefinition(name: "propose_body_note",
                       description: "Prepare a body note from something the person says happened to their body (an injury, pain, illness or other note). Nothing is saved: the app shows a card, and the note is saved only if the person taps Add note. title is short and in their own words, never a diagnosis. If the place or the side (left or right) is unclear, ask one short question instead of calling this.",
                       parameters: object(["region": ["type": "string", "enum": regionEnum],
                                           "title": ["type": "string", "description": "Short, in their words, e.g. Rolled right ankle"],
                                           "details": ["type": "string", "description": "Anything else they said about it (optional)"],
                                           "date": date,
                                           "kind": ["type": "string", "enum": ["injury", "pain", "illness", "note"]],
                                           "resolved": ["type": "boolean", "description": "true only if they say it has already cleared up"]],
                                          required: ["region", "title"])),
        ToolDefinition(name: "get_insights",
                       description: "The insights currently generated for the user (id, headline, explanation).",
                       parameters: object([:])),
        ToolDefinition(name: "explain_insight",
                       description: "Evidence behind one insight: comparison windows, values, sample count, source, confidence.",
                       parameters: object(["insight_id": ["type": "string"]], required: ["insight_id"])),
        ToolDefinition(name: "get_data_sources",
                       description: "Which sources/devices recorded a metric and how much each contributed recently.",
                       parameters: object(["metric": ["type": "string", "enum": metricEnum]], required: ["metric"])),
        ToolDefinition(name: "show_widget",
                       description: "Attach a native, tappable widget under your answer. Use it whenever a chart helps (at most 2 per answer). step_chart needs period; sleep_timeline takes an optional date; insight needs insight_id; comparison shows the most recent compare_periods result.",
                       parameters: object(["type": ["type": "string", "enum": ["scores", "step_chart", "day_steps", "walking_summary", "weight_chart", "sleep_timeline", "workouts", "comparison", "insight", "sources", "metric_card", "body_note"]],
                                           "note_id": ["type": "string"],
                                           "period": ["type": "string", "enum": ["day", "week", "month", "6m", "year", "all"]],
                                           "date": date, "insight_id": ["type": "string"],
                                           "metric": ["type": "string", "enum": metricEnum]], required: ["type"])),
        heartRateRangeDefinition,
        calculateDefinition,
    ]

    // MARK: Execution

    /// Stateful per-conversation turn (remembers the last comparison for show_widget).
    public final class Session: @unchecked Sendable {
        public var lastComparison: ComparisonBlock?
        public init() {}
    }

    public func execute(name: String, arguments: JSONValue, session: Session = Session()) -> ToolOutput {
        let args = arguments
        switch name {
        case "get_today_summary": return todaySummary()
        case "get_walking_summary": return walkingSummary(period: WalkPeriod(token: args["period"]?.stringValue ?? "week") ?? .week)
        case "get_metric_summary":
            guard let m = metric(args["metric"]), let span = span(args["start_date"], args["end_date"]) else { return invalid("metric, start_date and end_date are required") }
            return metricSummary(m, span)
        case "get_time_series":
            guard let m = metric(args["metric"]), let span = span(args["start_date"], args["end_date"]) else { return invalid("metric, start_date and end_date are required") }
            return timeSeries(m, span, interval: args["interval"]?.stringValue ?? "day")
        case "compare_periods":
            guard let m = metric(args["metric"]), let sa = span(args["a_start"], args["a_end"]), let sb = span(args["b_start"], args["b_end"]) else {
                return invalid("metric and both periods are required")
            }
            let out = compare(m, sa, sb)
            if case .comparison(let c)? = out.suggestedBlock { session.lastComparison = c }
            return out
        case "get_personal_baseline":
            guard let m = metric(args["metric"]) else { return invalid("metric is required") }
            return baseline(m, window: Int(args["window_days"]?.doubleValue ?? 28))
        case "get_day_detail":
            guard let d = args["date"]?.stringValue.flatMap(LocalDate.init(string:)) else { return invalid("date is required") }
            return dayDetail(d)
        case "get_weight_trend": return weightTrend()
        case "get_readiness": return readiness(args["date"]?.stringValue.flatMap(LocalDate.init(string:)) ?? ctx.today)
        case "get_sleep_summary": return sleep(args["date"]?.stringValue.flatMap(LocalDate.init(string:)))
        case "get_workout_history":
            return workouts(span(args["start_date"], args["end_date"]) ?? ctx.trailing(30, endingDaysAgo: 0))
        case "find_personal_best":
            guard let m = metric(args["metric"]) else { return invalid("metric is required") }
            return personalBest(m, unit: args["unit"]?.stringValue ?? "day", lowest: args["lowest"] == .bool(true),
                                span: span(args["start_date"], args["end_date"]))
        case "find_anomalies":
            guard let m = metric(args["metric"]) else { return invalid("metric is required") }
            return anomalies(m, span(args["start_date"], args["end_date"]) ?? ctx.trailing(90, endingDaysAgo: 0))
        case "find_correlation":
            guard let ma = metric(args["metric_a"]), let mb = metric(args["metric_b"]) else { return invalid("metric_a and metric_b are required") }
            return correlation(ma, mb, lag: Int(args["lag_days"]?.doubleValue ?? 0), span: span(args["start_date"], args["end_date"]) ?? ctx.trailing(90))
        case "get_body_notes": return bodyNotes(span(args["start_date"], args["end_date"]))
        case "propose_body_note": return proposeBodyNote(args)
        case "get_insights": return insights()
        case "explain_insight": return explain(args["insight_id"]?.stringValue ?? "")
        case "get_data_sources":
            guard let m = metric(args["metric"]) else { return invalid("metric is required") }
            return sources(m)
        case "show_widget": return showWidget(args, session: session)
        case "get_heart_rate_range": return heartRateRange(span(args["start_date"], args["end_date"]))
        case "calculate":
            guard let expression = args["expression"]?.stringValue else { return invalid("expression is required") }
            return calculate(expression)
        default: return invalid("Unknown tool \(name)")
        }
    }

    func invalid(_ message: String) -> ToolOutput { ToolOutput(result: ["error": .string(message)]) }

    func metric(_ v: JSONValue?) -> HealthMetric? { v?.stringValue.flatMap(ToolMetric.init(rawValue:))?.metric }

    func span(_ a: JSONValue?, _ b: JSONValue?) -> DateSpan? {
        guard let s = a?.stringValue.flatMap(LocalDate.init(string:)) else { return nil }
        let e = b?.stringValue.flatMap(LocalDate.init(string:)) ?? ctx.today
        return DateSpan(s, min(e, ctx.today))
    }

    func fmt(_ v: Double?, _ m: HealthMetric) -> JSONValue { v.map { .string(Fmt.value($0, metric: m, units: units)) } ?? .null }

    func availabilityNote(_ m: HealthMetric) -> JSONValue {
        switch snapshot.availability[m] ?? .noData {
        case .available: .null
        case .noData: "No data recorded for this metric. The user may need to allow access in Settings › Health › Data Access, or use a device that records it."
        case .notAuthorized: "The user hasn't connected this category. It can be connected from Profile › Connected data."
        case .unsupported: "This device or source doesn't record this metric."
        case .stale: "The most recent data is old; the source may have stopped syncing."
        }
    }

    // MARK: Tools

    func todaySummary() -> ToolOutput {
        let s = snapshot
        let pace = s.pace
        var obj: [String: JSONValue] = [
            "date": .string(ctx.today.description), "weekday": .string(Fmt.weekday(ctx.today)),
            "local_time": .string(Fmt.hour(Int(ctx.hourNow))),
            "steps_so_far": .num(s.todaySteps),
            "usual_steps_by_this_time": .num(pace?.usualByNow),
            "usual_full_day_steps": .num(pace?.usualFullDay),
            "change_vs_usual_by_now_pct": .num(pace?.change.map { $0 * 100 }),
            "usual_based_on": .str(pace.map { $0.basis == .sameWeekday ? "median of the last \($0.observations) \(Fmt.weekday(ctx.today))s" : "median of the last \($0.observations) days" }),
            "distance_today": fmt(s.todayDistance, .distanceWalkingRunning),
            "exercise_minutes_today": .num(s.todayExercise),
            "steps_7_day_avg": .num(s.average7?.value), "steps_30_day_avg": .num(s.average30?.value),
            "headline": .string(s.headline),
        ]
        if let n = s.sleep.lastNightAsleep { obj["last_night_sleep"] = .string(Fmt.duration(n)) }
        if let w = s.weight { obj["weight_trend"] = .string(Fmt.weight(w.trendNow, units: units)) }
        if let c = s.consistency { obj["days_near_usual_this_week"] = .number(Double(c.metCount)) }
        let block = AssistantBlock.walkingSummary(walkingBlock())
        return ToolOutput(result: .object(obj), evidence: [EvidenceItem(label: "Today vs usual", detail: pace.map { $0.basis == .sameWeekday ? "Median of your last \($0.observations) \(Fmt.weekday(ctx.today))s at this time" : "Median of your last \($0.observations) days at this time" } ?? "Not enough history yet")],
                          suggestedBlock: block)
    }

    func walkingBlock() -> WalkingSummaryBlock {
        let s = snapshot
        let base = a.baseline(.steps, window: 28, endingDaysAgo: 8)
        let last7 = ctx.trailing(7, endingDaysAgo: 0).days.map { DayValue(date: $0, value: ctx.history.value(.steps, on: $0) ?? 0) }
        return WalkingSummaryBlock(todaySteps: s.todaySteps, usualByNow: s.pace?.usualByNow, average7: s.average7?.value,
                                   average30: s.average30?.value, baseline28: base?.mean,
                                   changeVsBaseline: s.average7.flatMap { cur in base.flatMap { Stats.percentChange(from: $0.mean, to: cur.value) } },
                                   todayDistance: s.todayDistance, last7: last7)
    }

    func stepChartBlock(_ period: WalkPeriod) -> AssistantBlock {
        let p = snapshot.periods[period] ?? a.periodSummary(.steps, period: period)
        return .stepChart(StepChartBlock(title: period.title, period: period, bucketUnit: p.bucketUnit, buckets: p.buckets,
                                         average: p.dailyAverage, previousAverage: p.previousDailyAverage, change: p.change))
    }

    func walkingSummary(period: WalkPeriod) -> ToolOutput {
        let p = snapshot.periods[period] ?? a.periodSummary(.steps, period: period)
        let base = a.baseline(.steps, window: 28)
        let obj: [String: JSONValue] = [
            "period": .string(period.title),
            "range": .string("\(p.span.start) to \(p.span.end)"),
            "daily_average_steps_complete_days": .num(p.dailyAverage),
            "previous_period_range": .string("\(p.previousSpan.start) to \(p.previousSpan.end)"),
            "previous_period_daily_average": .num(p.previousDailyAverage),
            "change_vs_previous_pct": .num(p.change.map { $0 * 100 }, digits: 1),
            "total_steps_including_today": .num(p.total),
            "days_with_data": .number(Double(p.daysWithData)),
            "highest_day": p.highest.map { .string("\($0.date) (\(Fmt.weekday($0.date))): \(Fmt.int($0.value))") } ?? .null,
            "lowest_day": p.lowest.map { .string("\($0.date) (\(Fmt.weekday($0.date))): \(Fmt.int($0.value))") } ?? .null,
            "median_day": .num(p.median),
            "variability_cv_pct": .num(p.variability.map { $0 * 100 }),
            "days_at_or_above_threshold": .number(Double(p.activeDays)),
            "threshold_steps": .num(p.activeThreshold),
            "weekday_average": .num(p.weekdayAverage), "weekend_average": .num(p.weekendAverage),
            "baseline_28_day_mean": .num(base?.mean), "baseline_28_day_median": .num(base?.median),
            "distance_note": fmt(a.average(.distanceWalkingRunning, in: p.span)?.value, .distanceWalkingRunning).stringValue.map { .string("Average distance per day: \($0)") } ?? .null,
            "note": availabilityNote(.steps),
        ]
        return ToolOutput(result: .object(obj),
                          evidence: [EvidenceItem(label: "Steps · \(period.title.lowercased())", detail: "\(Fmt.shortDate(p.span.start)) – \(Fmt.shortDate(p.span.end)) vs the \(p.previousSpan.dayCount) days before · \(ctx.sourceLabel(.steps))")],
                          suggestedBlock: stepChartBlock(period))
    }

    func metricSummary(_ m: HealthMetric, _ span: DateSpan) -> ToolOutput {
        let vals = ctx.history.values(m, in: span)
        let sorted = vals.sorted { $0.key < $1.key }
        let complete = vals.filter { $0.key != ctx.today }.map(\.value)
        var obj: [String: JSONValue] = [
            "metric": .string(m.displayName), "range": .string("\(span.start) to \(span.end)"),
            "days_in_range": .number(Double(span.dayCount)), "days_with_data": .number(Double(vals.count)),
            "daily_average": fmt(Stats.mean(complete.isEmpty ? Array(vals.values) : complete), m),
            "highest": sorted.max { $0.value < $1.value }.map { .string("\($0.key): \(Fmt.value($0.value, metric: m, units: units))") } ?? .null,
            "lowest": sorted.min { $0.value < $1.value }.map { .string("\($0.key): \(Fmt.value($0.value, metric: m, units: units))") } ?? .null,
            "note": availabilityNote(m),
        ]
        if m.aggregation == .cumulative && m != .sleepDuration { obj["total"] = fmt(vals.values.reduce(0, +), m) }
        let suggested: AssistantBlock?
        switch m {
        case .steps: suggested = stepChartBlock(span.dayCount <= 8 ? .week : (span.dayCount <= 31 ? .month : .sixMonths))
        case .weight: suggested = weightBlock()
        default: suggested = Stats.mean(Array(vals.values)).map {
            .metricCard(MetricCardBlock(metric: m, title: m.displayName, value: $0, caption: "Daily average, \(Fmt.shortDate(span.start)) – \(Fmt.shortDate(span.end))"))
        }
        }
        return ToolOutput(result: .object(obj), evidence: [EvidenceItem(label: m.displayName, detail: "\(Fmt.shortDate(span.start)) – \(Fmt.shortDate(span.end)) · \(ctx.sourceLabel(m))")],
                          suggestedBlock: suggested)
    }

    func timeSeries(_ m: HealthMetric, _ span: DateSpan, interval: String) -> ToolOutput {
        let vals = ctx.history.values(m, in: span)
        var points: [JSONValue] = []
        switch interval {
        case "week", "month":
            var groups: [LocalDate: [Double]] = [:]
            for (d, v) in vals {
                let key = interval == "week" ? d.startOfWeek(firstWeekday: ctx.profile.firstWeekday) : d.startOfMonth
                groups[key, default: []].append(v)
            }
            for k in groups.keys.sorted().suffix(120) {
                let g = groups[k]!
                points.append(["start": .string(k.description), "daily_average": fmt(Stats.mean(g), m), "days": .number(Double(g.count))])
            }
        default:
            for (d, v) in vals.sorted(by: { $0.key < $1.key }).suffix(120) {
                points.append(["date": .string(d.description), "weekday": .string(Fmt.weekdayShort[d.weekday - 1]), "value": fmt(v, m)])
            }
        }
        return ToolOutput(result: ["metric": .string(m.displayName), "interval": .string(interval), "points": .array(points), "note": availabilityNote(m)],
                          evidence: [EvidenceItem(label: "\(m.displayName) by \(interval)", detail: "\(Fmt.shortDate(span.start)) – \(Fmt.shortDate(span.end))")],
                          suggestedBlock: m == .steps ? stepChartBlock(span.dayCount <= 8 ? .week : (span.dayCount <= 31 ? .month : .sixMonths)) : (m == .weight ? weightBlock() : nil))
    }

    func compare(_ m: HealthMetric, _ sa: DateSpan, _ sb: DateSpan) -> ToolOutput {
        let va = Array(ctx.history.values(m, in: sa).filter { $0.key != ctx.today || sa.dayCount == 1 }.values)
        let vb = Array(ctx.history.values(m, in: sb).filter { $0.key != ctx.today || sb.dayCount == 1 }.values)
        guard let ma = Stats.mean(va), let mb = Stats.mean(vb) else {
            return ToolOutput(result: ["error": "Not enough data in one of the periods", "days_with_data_a": .number(Double(va.count)), "days_with_data_b": .number(Double(vb.count)), "note": availabilityNote(m)])
        }
        let change = Stats.percentChange(from: mb, to: ma)
        let labelA = "\(Fmt.shortDate(sa.start)) – \(Fmt.shortDate(sa.end))"
        let labelB = "\(Fmt.shortDate(sb.start)) – \(Fmt.shortDate(sb.end))"
        let block = ComparisonBlock(metric: m, labelA: labelA, valueA: ma, labelB: labelB, valueB: mb, change: change, spanA: sa, spanB: sb)
        return ToolOutput(result: [
            "metric": .string(m.displayName),
            "period_a": .string("\(sa.start) to \(sa.end)"), "period_a_daily_average": fmt(ma, m), "period_a_days_with_data": .number(Double(va.count)),
            "period_b": .string("\(sb.start) to \(sb.end)"), "period_b_daily_average": fmt(mb, m), "period_b_days_with_data": .number(Double(vb.count)),
            "change_b_to_a_pct": .num(change.map { $0 * 100 }, digits: 1),
            "difference": fmt(abs(ma - mb), m), "direction": .string(ma >= mb ? "A higher" : "A lower"),
        ], evidence: [EvidenceItem(label: "Compared \(m.displayName.lowercased())", detail: "\(labelA) vs \(labelB) · daily averages")],
            suggestedBlock: .comparison(block))
    }

    func baseline(_ m: HealthMetric, window: Int) -> ToolOutput {
        let w = [7, 28, 90].contains(window) ? window : 28
        guard let b = a.baseline(m, window: w) else {
            return ToolOutput(result: ["error": "Not enough history for a \(w)-day baseline yet", "note": availabilityNote(m)])
        }
        var obj: [String: JSONValue] = [
            "metric": .string(m.displayName), "window": .string("\(b.span.start) to \(b.span.end)"),
            "mean": fmt(b.mean, m), "median": fmt(b.median, m), "days_with_data": .number(Double(b.observations)),
        ]
        if m == .steps {
            let p = snapshot.weekdayPattern
            obj["typical_by_weekday_last_12_weeks"] = .object(Dictionary(uniqueKeysWithValues: (1...7).map { wd in
                (Fmt.weekdayNames[wd - 1], p.medians[wd - 1].map { JSONValue.number($0.rounded()) } ?? .null)
            }))
        }
        return ToolOutput(result: .object(obj), evidence: [EvidenceItem(label: "\(w)-day baseline", detail: "\(Fmt.shortDate(b.span.start)) – \(Fmt.shortDate(b.span.end)), \(b.observations) days")],
                          suggestedBlock: .metricCard(MetricCardBlock(metric: m, title: "Your \(w)-day normal", value: b.mean, caption: "Average of \(b.observations) days")))
    }

    func dayDetail(_ d: LocalDate) -> ToolOutput {
        let h = ctx.history
        var obj: [String: JSONValue] = ["date": .string(d.description), "weekday": .string(Fmt.weekday(d))]
        if d > ctx.today { return ToolOutput(result: ["error": "That date is in the future"]) }
        obj["steps"] = .num(h.value(.steps, on: d))
        if let usual = a.usual(.steps, weekday: d.weekday) {
            obj["usual_for_\(Fmt.weekday(d).lowercased())"] = .num(usual.median)
            if let v = h.value(.steps, on: d) { obj["change_vs_usual_pct"] = .num(Stats.percentChange(from: usual.median, to: v).map { $0 * 100 }) }
        }
        if let hb = h.hourlySteps[d], hb.total > 0 {
            let peak = hb.values.enumerated().max { $0.element < $1.element }!.offset
            obj["busiest_hour"] = .string(Fmt.hour(peak))
            obj["share_before_noon_pct"] = .num(hb.values[0..<12].reduce(0, +) / hb.total * 100)
        }
        obj["distance"] = fmt(h.value(.distanceWalkingRunning, on: d), .distanceWalkingRunning)
        obj["exercise_minutes"] = .num(h.value(.exerciseMinutes, on: d))
        obj["sleep_night_before"] = h.sleepNights[d].map { .string(Fmt.duration($0.asleepDuration)) } ?? .null
        obj["weight"] = fmt(h.value(.weight, on: d), .weight)
        let ws = h.workouts.filter { LocalDate($0.start, calendar: ctx.calendar) == d }
        obj["workouts"] = .array(ws.map { .string("\($0.activity), \(Fmt.duration($0.duration))") })
        let notes = h.notes(on: d) + h.events.filter { $0.date < d && $0.isActive(on: d) }
        obj["body_notes"] = .array(notes.map { n in
            ["id": .string(n.id), "title": .string(n.title), "region": .str(n.bodyRegion?.displayName),
             "event_date": .string(n.date.description), "status_on_that_day": .string(n.date == d ? "noted that day" : "unresolved since \(n.date)")]
        })
        var blocks: [AssistantBlock] = []
        if let n = h.notes(on: d).first { blocks.append(.bodyNote(n)) }
        return ToolOutput(result: .object(obj), blocks: [], evidence: [EvidenceItem(label: Fmt.dayLabel(d), detail: ctx.sourceLabel(.steps))]
                          + notes.map { EvidenceItem(label: "Body note", detail: "\($0.title) · \(Fmt.dayLabel($0.date))") },
                          suggestedBlock: .daySteps(dayBlock(d)), extraBlocks: blocks)
    }

    func dayBlock(_ d: LocalDate) -> DayStepsBlock {
        let usual = a.usualBefore(d)
        return DayStepsBlock(date: d, steps: ctx.history.value(.steps, on: d), usual: usual?.median,
                             usualObservations: usual?.observations ?? 0, hourly: ctx.history.hourlySteps[d]?.values)
    }

    func bodyNotes(_ span: DateSpan?) -> ToolOutput {
        let notes = span.map { ctx.history.notes(in: $0) } ?? ctx.history.bodyNotes
        return ToolOutput(result: [
            "notes": .array(notes.prefix(20).map { n in
                ["id": .string(n.id), "title": .string(n.title), "details": .str(n.note), "region": .str(n.bodyRegion?.displayName),
                 "kind": .string(n.kindLabel), "event_date": .string(n.date.description),
                 "entered_on": .string(LocalDate(n.createdAt, calendar: ctx.calendar).description),
                 "resolved_on": .str(n.resolvedDate?.description), "active_today": .bool(n.isActive(on: ctx.today))]
            }),
            "reminder": "These are the user's own notes. Don't diagnose from them or treat old notes as current.",
        ], evidence: notes.prefix(3).map { EvidenceItem(label: "Body note", detail: "\($0.title) · \(Fmt.dayLabel($0.date))") },
           suggestedBlock: notes.first.map(AssistantBlock.bodyNote))
    }

    /// A note built from the person's words for them to confirm. History is never changed here.
    func proposeBodyNote(_ args: JSONValue) -> ToolOutput {
        guard let region = args["region"]?.stringValue.flatMap(BodyRegion.named) else {
            return invalid("region must be one of the listed body regions")
        }
        let title = (args["title"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return invalid("title is required") }
        let details = args["details"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = min(args["date"]?.stringValue.flatMap(LocalDate.init(string:)) ?? ctx.today, ctx.today)
        let kind = args["kind"]?.stringValue.flatMap(HealthEvent.Kind.init(rawValue:)) ?? .note
        var resolved = false
        if case .bool(true)? = args["resolved"] { resolved = true }
        let note = HealthEvent(date: date, kind: kind, title: String(title.prefix(80)),
                               note: details.flatMap { $0.isEmpty ? nil : String($0.prefix(400)) },
                               bodyRegion: region, createdAt: ctx.now, resolvedDate: resolved ? ctx.today : nil)
        return ToolOutput(result: [
            "proposed": true, "saved": false, "region": .string(region.displayName), "event_date": .string(date.description),
            "next": "The person sees a card with Edit and Add note. Nothing is saved until they tap Add note; say so.",
        ], blocks: [.bodyNoteProposal(note)])
    }

    func weightBlock() -> AssistantBlock? {
        guard let w = snapshot.weight else { return nil }
        let cutoff = ctx.now.addingTimeInterval(-120 * 86_400)
        return .weightChart(WeightChartBlock(points: w.points.filter { $0.date >= cutoff }, latest: w.latest.value, trend: w.trendNow,
                                             change30: w.change30Days, goalKg: w.goalKg))
    }

    func weightTrend() -> ToolOutput {
        guard let w = snapshot.weight else {
            return ToolOutput(result: ["error": "No weight readings", "note": availabilityNote(.weight)])
        }
        return ToolOutput(result: [
            "latest_reading": .string(Fmt.weight(w.latest.value, units: units)),
            "latest_reading_date": .string(LocalDate(w.latest.date, calendar: ctx.calendar).description),
            "smoothed_trend_now": .string(Fmt.weight(w.trendNow, units: units)),
            "trend_30_days_ago": .str(w.trend30DaysAgo.map { Fmt.weight($0, units: units) }),
            "trend_change_30_days": .str(w.change30Days.map { Fmt.weightChange($0, units: units) }),
            "trend_change_7_days": .str(w.trendChangeLast7Days.map { Fmt.weightChange($0, units: units) }),
            "weekly_rate": .str(w.weeklyRate.map { Fmt.weightChange($0, units: units) + " per week" }),
            "readings_last_7_days": .number(Double(w.readingsLast7Days)),
            "reading_range_last_7_days": .str(w.rangeLast7Days.map { "\(Fmt.weight($0.lowerBound, units: units)) – \(Fmt.weight($0.upperBound, units: units))" }),
            "change_since_first_reading": .string(Fmt.weightChange(w.changeSinceStart, units: units)),
            "first_reading_date": .string(LocalDate(w.startDate, calendar: ctx.calendar).description),
            "direction": .string(w.direction.rawValue),
            "goal": .str(w.goalKg.map { Fmt.weight($0, units: units) }),
            "distance_to_goal": .str(w.distanceToGoal.map { Fmt.weight(abs($0), units: units) + ($0 > 0 ? " above goal" : " below goal") }),
            "method": "Exponentially smoothed trend (7-day time constant) to filter daily water-weight swings",
            "stale": .bool(w.isStale),
        ], evidence: [EvidenceItem(label: "Weight trend", detail: "\(w.sampleCount) readings · \(ctx.sourceLabel(.weight))")], suggestedBlock: weightBlock())
    }

    func scoresBlock(_ date: LocalDate) -> ScoresBlock {
        let e = ScoreEngine(ctx)
        let r = e.readiness(on: date)
        let l = e.load(on: date)
        return ScoresBlock(date: date, readiness: r.score, band: r.band, calibrationDays: r.calibrationDays, sleep: e.sleep(on: date)?.score,
                           load: l?.value, loadUsual: l?.usualRange.map { [$0.lowerBound, $0.upperBound] }, factors: r.factors, summary: r.summary)
    }

    func readiness(_ date: LocalDate) -> ToolOutput {
        let e = ScoreEngine(ctx)
        let r = e.readiness(on: date)
        let sl = e.sleep(on: date)
        let l = e.load(on: date)
        let m = e.monitor(on: date)
        var obj: [String: JSONValue] = [
            "date": .string(date.description),
            "readiness": .num(r.score.map(Double.init)),
            "band": .str(r.band?.label),
            "calibrating": .bool(r.isCalibrating),
            "calibration_nights": .number(Double(r.calibrationDays)),
            "summary": .string(r.summary),
            "readiness_factors": .array(r.factors.map { f in
                ["factor": .string(f.title), "value": .string(f.value), "usual": .string(f.baseline),
                 "effect_minus1_to_1": .number((f.effect * 100).rounded() / 100), "share_of_score": .number((f.weight * 100).rounded() / 100)]
            }),
            "sleep_performance": .num(sl.map { Double($0.score) }),
            "load_0_to_10": .num(l?.value, digits: 1),
            "load_usual_range": .str(l?.usualRange.map { "\(Fmt.decimal($0.lowerBound))–\(Fmt.decimal($0.upperBound))" }),
            "health_monitor": .array(m.vitals.map { v in
                ["metric": .string(v.metric.displayName), "value": .str(v.value.map { Fmt.value($0, metric: v.metric, units: units) }),
                 "status": .string(v.status.rawValue),
                 "personal_range": .str(v.range.map { "\(Fmt.value($0.lowerBound, metric: v.metric, units: units)) – \(Fmt.value($0.upperBound, metric: v.metric, units: units))" })]
            }),
        ]
        if let sl {
            obj["sleep_asleep"] = .string(Fmt.duration(sl.asleep))
            obj["sleep_need"] = .string(Fmt.duration(sl.need))
            obj["sleep_debt_7_nights"] = .string(Fmt.duration(sl.debt))
        }
        return ToolOutput(result: .object(obj),
                          evidence: [EvidenceItem(label: "Readiness", detail: "HRV and resting heart rate vs your 30-day baseline, plus sleep performance · \(r.calibrationDays) nights of baseline")],
                          suggestedBlock: .scores(scoresBlock(date)))
    }

    func sleepBlock(_ night: SleepNight) -> AssistantBlock {
        let s = snapshot.sleep
        let others = LocalDate.range(night.date.adding(days: -28), night.date.adding(days: -1)).compactMap { ctx.history.sleepNights[$0]?.asleepDuration }
        let avg = Stats.mean(others)
        return .sleepTimeline(SleepTimelineBlock(night: night, asleep: night.asleepDuration, average28: avg ?? s.average28,
                                                 differenceFromAverage: others.count >= 5 ? avg.map { night.asleepDuration - $0 } : nil))
    }

    func sleep(_ date: LocalDate?) -> ToolOutput {
        let night = date.flatMap { ctx.history.sleepNights[$0] } ?? (date == nil ? snapshot.sleep.lastNight : nil)
        guard let night else {
            return ToolOutput(result: ["error": .string(date == nil ? "No sleep recorded for last night" : "No sleep recorded for that night"),
                                       "nights_recorded_last_28": .number(Double(snapshot.sleep.nights28)), "note": availabilityNote(.sleepDuration)])
        }
        let others = LocalDate.range(night.date.adding(days: -28), night.date.adding(days: -1)).compactMap { ctx.history.sleepNights[$0]?.asleepDuration }
        let avg = Stats.mean(others)
        var obj: [String: JSONValue] = [
            "wake_date": .string(night.date.description), "asleep": .string(Fmt.duration(night.asleepDuration)),
            "in_bed_span": .string(Fmt.duration(night.inBedDuration)),
            "average_prior_28_nights": .str(avg.map { Fmt.duration($0) }),
            "difference_vs_average_minutes": .num(avg.map { (night.asleepDuration - $0) / 60 }),
            "nights_in_average": .number(Double(others.count)), "source": .string(night.source.name),
            "has_stages": .bool(night.hasStages),
        ]
        if let s = night.start, let e = night.end {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.timeZone = ctx.calendar.timeZone
            f.dateFormat = "h:mm a"
            obj["fell_asleep_around"] = .string(f.string(from: s))
            obj["woke_around"] = .string(f.string(from: e))
        }
        if night.hasStages {
            obj["stages"] = .object(Dictionary(uniqueKeysWithValues: [SleepStage.core, .deep, .rem, .awake].map { ($0.displayName, .string(Fmt.duration(night.duration(of: $0)))) }))
        }
        return ToolOutput(result: .object(obj), evidence: [EvidenceItem(label: "Sleep", detail: "Night ending \(Fmt.dayLabel(night.date)) · \(night.source.name)")],
                          suggestedBlock: sleepBlock(night))
    }

    func workouts(_ span: DateSpan) -> ToolOutput {
        let interval = span.dateInterval(in: ctx.calendar)
        let ws = ctx.history.workouts.filter { interval.contains($0.start) }.sorted { $0.start > $1.start }
        let list: [JSONValue] = ws.prefix(30).map { w in
            ["date": .string(LocalDate(w.start, calendar: ctx.calendar).description), "type": .string(w.activity),
             "duration": .string(Fmt.duration(w.duration)), "distance": .str(w.distanceMeters.map { Fmt.distance($0, units: units) }),
             "energy_kcal": .num(w.energyKcal)]
        }
        return ToolOutput(result: ["range": .string("\(span.start) to \(span.end)"), "count": .number(Double(ws.count)),
                                   "total_duration": .string(Fmt.duration(ws.reduce(0) { $0 + $1.duration })), "workouts": .array(list)],
                          evidence: [EvidenceItem(label: "Workouts", detail: "\(Fmt.shortDate(span.start)) – \(Fmt.shortDate(span.end)) · \(ws.count) recorded")],
                          suggestedBlock: ws.isEmpty ? nil : .workouts(WorkoutListBlock(workouts: Array(ws.prefix(6)))))
    }

    func personalBest(_ m: HealthMetric, unit: String, lowest: Bool, span: DateSpan?) -> ToolOutput {
        let first = ctx.history.firstDate(m, calendar: ctx.calendar) ?? ctx.today
        let range = span ?? DateSpan(first, ctx.today)
        if unit == "week" {
            guard let best = a.bestWeek(m, in: range) else { return ToolOutput(result: ["error": "Not enough complete weeks"]) }
            let week = DateSpan(best.start, best.start.adding(days: 6))
            return ToolOutput(result: ["best_week": .string("\(week.start) to \(week.end)"), "total": fmt(best.total, m), "daily_average": fmt(best.average, m),
                                       "searched": .string("\(range.start) to \(range.end)")],
                              evidence: [EvidenceItem(label: "Best week", detail: "Searched \(range.start) – \(range.end)")],
                              suggestedBlock: .metricCard(MetricCardBlock(metric: m, title: "Week of \(Fmt.shortDate(best.start))", value: best.average, caption: "Daily average, your best week")))
        }
        guard let best = a.personalBest(m, in: range, highest: !lowest) else { return ToolOutput(result: ["error": "No data in range"]) }
        return ToolOutput(result: [lowest ? "lowest_day" : "best_day": .string("\(best.date) (\(Fmt.weekday(best.date)))"), "value": fmt(best.value, m),
                                   "searched": .string("\(range.start) to \(range.end)")],
                          evidence: [EvidenceItem(label: lowest ? "Lowest day" : "Best day", detail: "Searched \(range.start) – \(range.end)")],
                          suggestedBlock: .metricCard(MetricCardBlock(metric: m, title: Fmt.dayLabel(best.date), value: best.value, caption: lowest ? "Lowest day" : "Best day")))
    }

    func anomalies(_ m: HealthMetric, _ span: DateSpan) -> ToolOutput {
        let list = a.anomalies(m, in: span)
        return ToolOutput(result: [
            "range": .string("\(span.start) to \(span.end)"),
            "method": "More than 2 standard deviations from the preceding 28-day mean",
            "days": .array(list.suffix(20).map { an in
                ["date": .string("\(an.date) (\(Fmt.weekdayShort[an.date.weekday - 1]))"), "value": fmt(an.value, m),
                 "usual": fmt(an.baseline, m), "direction": .string(an.zScore > 0 ? "unusually high" : "unusually low")]
            }),
        ], evidence: [EvidenceItem(label: "Unusual days", detail: "\(m.displayName), \(Fmt.shortDate(span.start)) – \(Fmt.shortDate(span.end))")])
    }

    func correlation(_ ma: HealthMetric, _ mb: HealthMetric, lag: Int, span: DateSpan) -> ToolOutput {
        guard let c = a.correlation(ma, mb, in: span, lagDays: max(-3, min(3, lag))) else {
            return ToolOutput(result: ["error": "Fewer than 10 days with both metrics in this range", "note": availabilityNote(mb)])
        }
        return ToolOutput(result: [
            "metric_a": .string(ma.displayName), "metric_b": .string(mb.displayName), "lag_days": .number(Double(c.lagDays)),
            "pearson_r": .num(c.coefficient, digits: 2), "paired_days": .number(Double(c.pairs)), "strength": .string(c.strength),
            "range": .string("\(span.start) to \(span.end)"),
            "caveat": .string(InsightEngine.relationshipCaveat + " Other factors (weather, schedule, illness) can drive both."),
        ], evidence: [EvidenceItem(label: "Correlation", detail: "\(ma.displayName) vs \(mb.displayName), \(c.pairs) paired days")])
    }

    func insights() -> ToolOutput {
        ToolOutput(result: ["insights": .array(snapshot.allInsights.prefix(8).map { i in
            ["id": .string(i.id), "headline": .string(i.headline), "explanation": .string(i.explanation), "confidence": .string(i.confidence.rawValue)]
        })])
    }

    func explain(_ id: String) -> ToolOutput {
        guard let i = snapshot.insight(id: id) ?? snapshot.allInsights.first(where: { $0.kind.rawValue == id }) else {
            return ToolOutput(result: ["error": "Unknown insight id"])
        }
        return ToolOutput(result: [
            "headline": .string(i.headline), "explanation": .string(i.explanation),
            "evidence": .object(Dictionary(uniqueKeysWithValues: i.evidence.map { ($0.label, .string($0.value)) })),
            "observations": .number(Double(i.sampleCount)), "confidence": .string(i.confidence.label), "source": .string(i.source),
            "caveat": .str(i.caveat),
        ], evidence: [EvidenceItem(label: "Insight", detail: i.headline)], suggestedBlock: .insight(i))
    }

    func sources(_ m: HealthMetric) -> ToolOutput {
        let shares = (ctx.history.sources[m] ?? []).sorted { $0.value > $1.value }
        let total = shares.reduce(0) { $0 + $1.value }
        return ToolOutput(result: [
            "provider": .string(ctx.history.origin.providerKind.displayName),
            "sources_last_30_days": .array(shares.map { s in
                ["name": .string(s.source.name), "device": .str(s.source.device), "share_pct": .num(total > 0 ? s.value / total * 100 : nil)]
            }),
            "deduplication": "Apple Health merges overlapping iPhone and watch samples before totals are calculated, so steps are not double counted.",
        ], suggestedBlock: shares.isEmpty ? nil : .sources(SourcesBlock(metric: m, sources: shares)))
    }

    func showWidget(_ args: JSONValue, session: Session) -> ToolOutput {
        let type = args["type"]?.stringValue ?? ""
        var block: AssistantBlock?
        switch type {
        case "scores": block = readiness(args["date"]?.stringValue.flatMap(LocalDate.init(string:)) ?? ctx.today).suggestedBlock
        case "step_chart": block = stepChartBlock(WalkPeriod(token: args["period"]?.stringValue ?? "week") ?? .week)
        case "walking_summary": block = .walkingSummary(walkingBlock())
        case "weight_chart": block = weightBlock()
        case "sleep_timeline":
            let night = args["date"]?.stringValue.flatMap(LocalDate.init(string:)).flatMap { ctx.history.sleepNights[$0] } ?? snapshot.sleep.lastNight
            block = night.map(sleepBlock)
        case "workouts": block = workouts(ctx.trailing(30, endingDaysAgo: 0)).suggestedBlock
        case "comparison": block = session.lastComparison.map(AssistantBlock.comparison)
        case "insight": block = args["insight_id"]?.stringValue.flatMap { snapshot.insight(id: $0) }.map(AssistantBlock.insight)
        case "day_steps": block = args["date"]?.stringValue.flatMap(LocalDate.init(string:)).map { .daySteps(dayBlock($0)) }
        case "body_note": block = args["note_id"]?.stringValue.flatMap { id in ctx.history.events.first { $0.id == id } }.map(AssistantBlock.bodyNote)
        case "sources": block = sources(metric(args["metric"]) ?? .steps).suggestedBlock
        case "metric_card":
            if let m = metric(args["metric"]), let avg = a.rollingAverage(m, days: 7) {
                block = .metricCard(MetricCardBlock(metric: m, title: m.displayName, value: avg.value, caption: "7-day average"))
            }
        default: break
        }
        guard let block else { return ToolOutput(result: ["shown": false, "reason": "No data for that widget"]) }
        return ToolOutput(result: ["shown": true, "widget": .string(block.kind)], blocks: [block])
    }
}

/// Metric names the model uses.
public enum ToolMetric: String, CaseIterable, Sendable {
    case steps, distance, active_energy, exercise_minutes, flights, walking_speed, step_length
    case weight, body_fat, sleep, resting_heart_rate, heart_rate, hrv

    public var metric: HealthMetric {
        switch self {
        case .steps: .steps
        case .distance: .distanceWalkingRunning
        case .active_energy: .activeEnergy
        case .exercise_minutes: .exerciseMinutes
        case .flights: .flightsClimbed
        case .walking_speed: .walkingSpeed
        case .step_length: .walkingStepLength
        case .weight: .weight
        case .body_fat: .bodyFat
        case .sleep: .sleepDuration
        case .resting_heart_rate: .restingHeartRate
        case .heart_rate: .heartRate
        case .hrv: .hrv
        }
    }
}
