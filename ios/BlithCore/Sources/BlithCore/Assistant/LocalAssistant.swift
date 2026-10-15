import Foundation

/// On-device assistant used when AI sharing is off, no network, or no key is configured. It
/// answers the common questions by calling the same tools as the AI and filling templates,
/// so answers are factual and widgets are identical — just less conversational.
public struct LocalAssistant: AssistantEngine {
    public let tools: HealthAssistantTools

    public init(tools: HealthAssistantTools) { self.tools = tools }

    enum Intent { case readiness, today, walking(WalkPeriod), bestWeek, weight, sleep, workouts, sources, insights, compareMonth, day(LocalDate), notes, unknown }

    static func intent(for q: String, today: LocalDate = LocalDate(Date(), calendar: .current)) -> Intent {
        let t = q.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("note", "ankle", "knee", "injur", "hurt", "pain", "sprain", "body") && !has("walk", "step") { return .notes }
        if isReport(q), BodyRegion.match(in: q) != nil, !has("walk", "step") { return .notes }
        if has("readiness", "recovery", "recovered", "ready", "score", "hrv", "heart rate", "resting", "load", "strain", "vitals") { return .readiness }
        if let d = RelativeDates.day(in: t, today: today), d != today, !has("sleep", "slept", "weigh") { return .day(d) }
        if has("sleep", "slept", "bed", "night") { return .sleep }
        if has("weight", "weigh", "scale", "lose", "lost", "kg", "lb", "pound") { return .weight }
        if has("workout", "exercise", "run", "training") && !has("walk") { return .workouts }
        if has("best week", "most active week", "walked the most", "biggest week") { return .bestWeek }
        if has("source", "device", "watch", "iphone", "where does") { return .sources }
        if has("insight", "changed", "worth knowing", "notice", "pattern") { return .insights }
        if has("this month", "last month", "month") && has("compare", "vs", "versus", "than") { return .compareMonth }
        if has("today", "right now", "so far", "low today") { return .today }
        if has("year") { return .walking(.year) }
        if has("month", "30 days", "lately", "recently") { return .walking(.month) }
        if has("walk", "step", "moving", "active", "move", "week") { return .walking(.week) }
        return .unknown
    }

    /// The person is telling Ask about something that happened, not asking to see their notes.
    static func isReport(_ q: String) -> Bool {
        let t = q.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        guard !has("show", "list", "how many", "when did", "what ", "which notes", "my notes") else { return false }
        return has("hurt", "sprain", "rolled", "twist", "sore", "pain", "ache", "aching", "injur", "pulled", "strain", "stiff",
                   "bruise", "swollen", "fell", "broke", "tweak")
    }

    static func noteKind(_ q: String) -> HealthEvent.Kind {
        let t = q.lowercased()
        if ["injur", "sprain", "rolled", "twist", "pulled", "strain", "bruise", "fell", "broke", "tweak"].contains(where: { t.contains($0) }) { return .injury }
        if ["hurt", "sore", "pain", "ache", "aching", "stiff", "swollen"].contains(where: { t.contains($0) }) { return .pain }
        return .note
    }

    /// Their own words, first sentence only, capitalised.
    static func noteTitle(_ q: String) -> String {
        let first = q.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? q
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.prefix(1).uppercased() + trimmed.dropFirst()).prefix(80))
    }

    public func respond(to question: String, history: [ChatMessage], progress: @escaping @Sendable (String) -> Void) async throws -> ChatMessage {
        if let safety = SafetyScreen.check(question) { return safety }
        let s = tools.snapshot
        let ctx = s.ctx
        let u = ctx.units
        var text: String
        var output: ToolOutput

        switch Self.intent(for: question, today: ctx.today) {
        case .readiness:
            output = tools.execute(name: "get_readiness", arguments: [:])
            let r = s.readiness
            if let score = r.score, let band = r.band {
                text = "Your readiness today is \(score) (\(band.label.lowercased())). \(r.summary)"
                if let top = r.factors.max(by: { abs($0.effect * $0.weight) < abs($1.effect * $1.weight) }) {
                    text += " The biggest factor: \(top.title.lowercased()) at \(top.value) (\(top.baseline))."
                }
            } else {
                text = r.summary
            }
            if let l = s.load { text += " Load so far today is \(Fmt.decimal(l.value)) of 10." }
        case .day(let d):
            output = tools.execute(name: "get_day_detail", arguments: ["date": .string(d.description)])
            let a = HealthAnalytics(ctx)
            let steps = ctx.history.value(.steps, on: d)
            let notes = ctx.history.notes(on: d)
            if let steps {
                text = "On \(Fmt.dayLabel(d)) you recorded \(Fmt.int(steps)) steps"
                if let usual = a.usualBefore(d) {
                    text += ", compared with about \(Fmt.int(usual.median)) on your usual \(Fmt.weekday(d)) (median of the \(usual.observations) before it)."
                } else {
                    text += ". There aren't enough earlier \(Fmt.weekday(d))s to say what's usual."
                }
            } else {
                text = "There are no steps recorded for \(Fmt.dayLabel(d)), so I can't compare that day."
            }
            if let n = notes.first {
                text += " You also added a note that day: “\(n.title)”\(n.bodyRegion.map { " (\($0.displayName.lowercased()))" } ?? ""). I can show both records, but the data can't establish what caused the change."
            }
            let blocks = [output.suggestedBlock].compactMap { $0 } + output.extraBlocks
            return ChatMessage(role: .assistant, text: text, blocks: blocks, evidence: output.evidence, toolsUsed: [], isLocal: true)
        case .notes:
            if Self.isReport(question), let match = BodyRegion.match(in: question) {
                switch match {
                case .region(let region):
                    let date = RelativeDates.day(in: question, today: ctx.today) ?? ctx.today
                    let proposal = tools.execute(name: "propose_body_note", arguments: [
                        "region": .string(region.rawValue), "title": .string(Self.noteTitle(question)),
                        "date": .string(date.description), "kind": .string(Self.noteKind(question).rawValue)])
                    text = "I can add this as a note on your \(region.displayName.lowercased()). Check the card and tap Add note to save it. Blith can't assess it, so see a clinician if it gets worse or doesn't ease."
                    return ChatMessage(role: .assistant, text: text, blocks: proposal.blocks, isLocal: true)
                case .needsSide(let part):
                    return ChatMessage(role: .assistant, text: "Which \(part), left or right? Say for example “my left \(part) hurts” and I'll set up the note.", isLocal: true)
                }
            }
            output = tools.execute(name: "get_body_notes", arguments: [:])
            let notes = ctx.history.bodyNotes
            if let latest = notes.first {
                let active = notes.filter { $0.isActive(on: ctx.today) }
                text = "You have \(notes.count) body \(notes.count == 1 ? "note" : "notes"). The most recent is “\(latest.title)” from \(Fmt.dayLabel(latest.date))\(latest.resolvedDate.map { ", marked resolved \(Fmt.shortDate($0))" } ?? "")."
                text += active.isEmpty ? " None are marked unresolved." : " \(active.count) \(active.count == 1 ? "is" : "are") still unresolved."
            } else {
                text = "You haven't added any body notes yet. Tap a spot on the body in the Body tab to add one."
            }
        case .today:
            output = tools.execute(name: "get_today_summary", arguments: [:])
            if let pace = s.pace, let usual = pace.usualByNow, let change = pace.change {
                let basis = pace.basis == .sameWeekday ? "a typical \(Fmt.weekday(ctx.today))" : "a typical day"
                text = "You're at \(Fmt.int(pace.stepsSoFar)) steps so far. By this time on \(basis) you're usually around \(Fmt.int(usual)), so today is \(Fmt.percent(change)) \(change >= 0 ? "ahead" : "behind")."
            } else {
                text = "You're at \(Fmt.int(s.todaySteps ?? 0)) steps so far today. There isn't enough history yet to say what's usual for this time of day."
            }
        case .walking(let period):
            output = tools.execute(name: "get_walking_summary", arguments: ["period": .string(period.rawValue == "sixMonths" ? "6m" : period.rawValue)])
            let p = s.periods[period]
            if let avg = p?.dailyAverage, let prev = p?.previousDailyAverage, let change = p?.change {
                text = "Over the \(period.title.lowercased()) you averaged \(Fmt.int(avg)) steps a day, \(Fmt.percent(change)) \(change >= 0 ? "more" : "less") than the period before (\(Fmt.int(prev)))."
                if let b = p?.highest { text += " Your biggest day was \(Fmt.dayLabel(b.date)) with \(Fmt.int(b.value))." }
            } else if let avg = p?.dailyAverage {
                text = "Over the \(period.title.lowercased()) you averaged \(Fmt.int(avg)) steps a day. There isn't enough earlier data to compare yet."
            } else {
                text = "There's no step data for that period yet."
            }
        case .bestWeek:
            output = tools.execute(name: "find_personal_best", arguments: ["metric": "steps", "unit": "week"])
            let first = ctx.history.firstDate(.steps, calendar: ctx.calendar) ?? ctx.today
            if let best = HealthAnalytics(ctx).bestWeek(.steps, in: DateSpan(first, ctx.today)) {
                text = "Your most active week was the week of \(Fmt.shortDate(best.start)), \(best.start.year): \(Fmt.int(best.total)) steps, about \(Fmt.int(best.average)) a day."
            } else {
                text = "There aren't enough complete weeks yet to find your best one."
            }
        case .weight:
            output = tools.execute(name: "get_weight_trend", arguments: [:])
            if let w = s.weight {
                text = "Your smoothed weight trend is \(Fmt.weight(w.trendNow, units: u))"
                if let c = w.change30Days { text += ", \(Fmt.weightChange(c, units: u)) over the last 30 days" }
                text += "."
                if let r = w.rangeLast7Days, w.readingsLast7Days >= 2 {
                    text += " This week's readings ranged \(Fmt.weight(r.lowerBound, units: u))–\(Fmt.weight(r.upperBound, units: u)); the trend smooths out those daily swings."
                }
                if let d = w.distanceToGoal { text += " You're about \(Fmt.weight(abs(d), units: u)) \(d > 0 ? "above" : "below") your goal." }
            } else {
                text = "There are no weight readings yet. Connect a scale or log weight in Apple Health to see your trend here."
            }
        case .sleep:
            output = tools.execute(name: "get_sleep_summary", arguments: [:])
            if let n = s.sleep.lastNight {
                text = "You slept \(Fmt.duration(n.asleepDuration)) on the night ending \(Fmt.dayLabel(n.date))."
                if let d = s.sleep.differenceFromAverage {
                    text += " That's \(Fmt.duration(abs(d))) \(d >= 0 ? "more" : "less") than your recent average."
                }
            } else {
                text = "There's no sleep recorded for last night. Sleep comes from Apple Watch or a sleep app that writes to Apple Health."
            }
        case .workouts:
            output = tools.execute(name: "get_workout_history", arguments: [:])
            let count = output.result["count"]?.doubleValue ?? 0
            text = count > 0 ? "You recorded \(Int(count)) workouts in the last 30 days, \(output.result["total_duration"]?.stringValue ?? "") in total." : "No workouts were recorded in the last 30 days."
        case .sources:
            output = tools.execute(name: "get_data_sources", arguments: ["metric": "steps"])
            let names = (ctx.history.sources[.steps] ?? []).map(\.source.name)
            text = names.isEmpty ? "Your steps come from \(ctx.history.origin.providerKind.displayName)." : "Your steps over the last 30 days came from \(names.joined(separator: " and ")). Apple Health merges overlapping samples, so nothing is counted twice."
        case .insights:
            output = tools.execute(name: "get_insights", arguments: [:])
            if let first = s.feed.first {
                text = first.explanation
                if s.feed.count > 1 { text += " There's also: " + s.feed.dropFirst().prefix(2).map { $0.headline.lowercased() }.joined(separator: "; ") + "." }
                output.suggestedBlock = .insight(first)
            } else {
                text = "Nothing unusual stands out right now. Insights appear once there's a meaningful change against your own baseline."
            }
        case .compareMonth:
            let thisMonth = DateSpan(ctx.today.startOfMonth, ctx.yesterday)
            let lastMonthEnd = ctx.today.startOfMonth.adding(days: -1)
            let lastMonth = DateSpan(lastMonthEnd.startOfMonth, lastMonthEnd)
            output = tools.execute(name: "compare_periods", arguments: [
                "metric": "steps", "a_start": .string(thisMonth.start.description), "a_end": .string(thisMonth.end.description),
                "b_start": .string(lastMonth.start.description), "b_end": .string(lastMonth.end.description)])
            if let a = output.result["period_a_daily_average"]?.stringValue, let b = output.result["period_b_daily_average"]?.stringValue,
               let c = output.result["change_b_to_a_pct"]?.doubleValue {
                text = "This month you're averaging \(a) steps a day vs \(b) last month (\(Fmt.signedPercent(c / 100)))."
            } else {
                text = "There isn't enough data in both months to compare yet."
            }
        case .unknown:
            output = ToolOutput(result: [:])
            text = "I can answer questions about your walking, weight, sleep, workouts and how they've changed. Try “How have I been walking?” or “How is my weight trending?”"
        }

        return ChatMessage(role: .assistant, text: text, blocks: output.suggestedBlock.map { [$0] } ?? [],
                           evidence: output.evidence, toolsUsed: [], isLocal: true)
    }
}
