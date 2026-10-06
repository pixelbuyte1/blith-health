import Foundation

public protocol AssistantEngine: Sendable {
    func respond(to question: String, history: [ChatMessage], progress: @escaping @Sendable (String) -> Void) async throws -> ChatMessage
}

/// Screens for urgent symptoms before anything else runs. Wearable history can't explain
/// these, and the right answer is always the same.
public enum SafetyScreen {
    static let urgentPhrases = [
        "chest pain", "chest pressure", "can't breathe", "cannot breathe", "can’t breathe", "trouble breathing",
        "short of breath", "shortness of breath", "fainted", "passed out", "stroke", "face drooping", "slurred speech",
        "suicid", "kill myself", "end my life", "self harm", "self-harm", "overdose", "severe bleeding", "heart attack",
        "numb on one side", "worst headache",
    ]

    public static func check(_ text: String) -> ChatMessage? {
        let t = text.lowercased()
        guard urgentPhrases.contains(where: { t.contains($0) }) else { return nil }
        let crisis = ["suicid", "kill myself", "end my life", "self harm", "self-harm"].contains { t.contains($0) }
        let body = crisis
            ? "I'm really sorry you're going through this. Please reach out now: call or text 988 (Suicide & Crisis Lifeline, US) or your local emergency number. If you're outside the US, your local emergency services or a crisis line can help right away. You don't have to handle this alone."
            : "What you're describing could be urgent. Please call your local emergency number (911 in the US) or get to emergency care now. Your step, sleep or heart data can't rule out or explain a symptom like this, so please don't wait on the app."
        return ChatMessage(role: .assistant, text: body, isLocal: true)
    }
}

/// Compact, minimized context about the user sent with each AI request. No name, no raw
/// samples, no identifiers — only the aggregates needed to orient the model. Deeper history
/// is fetched through tools only when a question needs it.
public enum ProfileContext {
    public static func summary(_ s: HealthSnapshot) -> String {
        let ctx = s.ctx
        let u = ctx.units
        var lines: [String] = []
        let time = Fmt.hour(Int(ctx.hourNow))
        lines.append("Today is \(Fmt.weekday(ctx.today)), \(ctx.today) (local time about \(time)). Week starts on \(Fmt.weekdayNames[ctx.profile.firstWeekday - 1]). Units: \(u == .metric ? "metric (kg, km)" : "imperial (lb, mi)").")
        if !ctx.profile.goals.isEmpty { lines.append("Goals: " + ctx.profile.goals.map(\.title).sorted().joined(separator: ", ") + ".") }
        if let g = ctx.profile.dailyStepGoal { lines.append("Daily step goal: \(Fmt.int(Double(g))).") }
        lines.append("Data: \(ctx.history.origin.isDemo ? "SAMPLE DATA (demo mode, not the user's real data)" : "Apple Health").")
        let first = ctx.history.firstDate(.steps, calendar: ctx.calendar)
        lines.append("Step history from \(first?.description ?? "none"); weight readings: \(ctx.history.weights.count); sleep nights: \(ctx.history.sleepNights.count); workouts: \(ctx.history.workouts.count).")
        var steps = "Steps: today so far \(Fmt.int(s.todaySteps ?? 0))"
        if let u = s.pace?.usualByNow { steps += " (usual by now \(Fmt.int(u)))" }
        if let a = s.average7 { steps += "; 7-day avg \(Fmt.int(a.value))" }
        if let a = s.average30 { steps += "; 30-day avg \(Fmt.int(a.value))" }
        if let a = s.average90 { steps += "; 90-day avg \(Fmt.int(a.value))" }
        lines.append(steps + ".")
        if let w = s.weight {
            lines.append("Weight trend \(Fmt.weight(w.trendNow, units: u))" + (w.change30Days.map { ", 30-day change \(Fmt.weightChange($0, units: u))" } ?? "") + ".")
        }
        if let avg = s.sleep.average28 { lines.append("Sleep: 28-night average \(Fmt.duration(avg)).") }
        let unavailable = [HealthMetric.weight, .sleepDuration, .walkingSpeed].filter { s.availability[$0] != .available }
        if !unavailable.isEmpty { lines.append("Not available: " + unavailable.map { "\($0.displayName) (\(s.availability[$0]?.rawValue ?? "noData"))" }.joined(separator: ", ") + ".") }
        if !ctx.history.events.isEmpty {
            lines.append("The user keeps \(ctx.history.events.count) body notes (their own words, with dates). Fetch them with get_body_notes only when relevant; never assume an old note describes today.")
        }
        if !s.feed.isEmpty {
            lines.append("Current insights: " + s.feed.map { "[\($0.id)] \($0.headline)" }.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: "\n")
    }
}

/// The AI assistant: the model picks tools, the tool layer computes, the model explains.
public struct LLMAssistant: AssistantEngine {
    public let client: any ChatCompletionClient
    public let tools: HealthAssistantTools
    public var maxRounds = 5

    public init(client: any ChatCompletionClient, tools: HealthAssistantTools) {
        self.client = client
        self.tools = tools
    }

    public static let systemPrompt = """
    You are Ask, the assistant inside Blith, a personal health intelligence app. You help one person understand their own health data: walking, activity, weight, sleep, workouts and heart context.

    Rules:
    - For readiness, recovery, HRV, resting heart rate, vitals or load questions, call get_readiness and attach the "scores" widget. Readiness, sleep performance and load are Blith's own scores relative to the user's history; never present them as medical assessments.
    - Every number you state must come from a tool result or the context below. Never do arithmetic yourself; if you need a comparison or percentage, call compare_periods or another tool that returns it.
    - Compare against the person's own history (their baselines), not population norms, unless they ask.
    - Be specific and brief: 2–4 short sentences, plain language, no bullet lists unless asked. Name the comparison window ("vs your previous 4 weeks").
    - Attach a widget with show_widget when a chart or card would help (e.g. step_chart for walking, sleep_timeline for sleep, weight_chart for weight). Don't describe the widget in text.
    - Relationships between metrics are correlations, never causes. Say so when discussing them.
    - You are not a clinician. Don't diagnose, don't interpret symptoms from wearable data, and suggest talking to a doctor when something sounds medical. For urgent symptoms, tell them to contact emergency services.
    - If data is missing, say what's missing and how to connect it; don't guess.
    - Avoid empty praise ("Great job!") unless the data supports it, and never shame.
    - Body notes are the person's own words with an event date. Show them with dates, never diagnose from them, and never treat a resolved or old note as a current condition. When a note sits beside a change in the data, say the data can't show the cause.
    - For a question about one day, call get_day_detail and attach show_widget day_steps (and body_note when a note exists that day).
    - Hard limit: 4 short sentences. Write plain sentences. Never use em dashes; use a full stop or a comma.
    - For an everyday ache or pain the person mentions (for example a stiff lower back), don't explain causes and don't give treatment advice. Acknowledge it in one sentence, say Blith can't assess it, suggest a clinician if it lasts or gets worse, and tell them they can add it as a dated note on the Body tab. Mention emergency care in one line only if they describe red flags.
    - Dates: resolve relative dates ("last Tuesday", "August") from today's date given below, using YYYY-MM-DD in tool calls.
    """

    public func respond(to question: String, history: [ChatMessage], progress: @escaping @Sendable (String) -> Void) async throws -> ChatMessage {
        if let safety = SafetyScreen.check(question) { return safety }
        var messages: [LLMMessage] = [.system(Self.systemPrompt + "\n\nAbout this person (aggregates only):\n" + ProfileContext.summary(tools.snapshot))]
        for m in history.suffix(8) where !m.isError {
            messages.append(m.role == .user ? .user(m.text) : .assistant(m.text))
        }
        messages.append(.user(question))

        let session = HealthAssistantTools.Session()
        var blocks: [AssistantBlock] = []
        var evidence: [EvidenceItem] = []
        var used: [String] = []
        var suggested: AssistantBlock?
        var extras: [AssistantBlock] = []

        for round in 0..<maxRounds {
            progress(round == 0 ? "Thinking" : "Reading your data")
            // Final round: no tools, force an answer.
            let reply = try await client.complete(messages: messages, tools: round == maxRounds - 1 ? [] : HealthAssistantTools.definitions)
            guard let calls = reply.tool_calls, !calls.isEmpty else {
                let text = Self.plainStyle(reply.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw AssistantError.emptyResponse }
                if blocks.isEmpty, let suggested { blocks.append(suggested); blocks.append(contentsOf: extras) }
                return ChatMessage(role: .assistant, text: text, blocks: Self.dedupe(blocks), evidence: Self.dedupe(evidence), toolsUsed: used)
            }
            messages.append(LLMMessage(role: "assistant", content: reply.content, tool_calls: calls))
            for call in calls {
                progress(Self.progressLabel(call.function.name))
                let args = JSONValue.parse(call.function.arguments) ?? [:]
                let out = tools.execute(name: call.function.name, arguments: args, session: session)
                used.append(call.function.name)
                blocks.append(contentsOf: out.blocks)
                evidence.append(contentsOf: out.evidence)
                if suggested == nil, call.function.name != "show_widget" {
                    suggested = out.suggestedBlock
                    extras = out.extraBlocks
                }
                var json = out.result.jsonString()
                if json.count > 8000 { json = String(json.prefix(8000)) }
                messages.append(LLMMessage(role: "tool", content: json, tool_call_id: call.id))
            }
        }
        throw AssistantError.emptyResponse
    }

    /// Blith's voice uses plain sentences: models still slip in em dashes, so they become commas here.
    static func plainStyle(_ text: String) -> String {
        text.replacingOccurrences(of: " \u{2014} ", with: ", ")
            .replacingOccurrences(of: "\u{2014}", with: ", ")
    }

    static func dedupe<T: Identifiable>(_ items: [T]) -> [T] {
        var seen = Set<AnyHashable>()
        return items.filter { seen.insert(AnyHashable($0.id)).inserted }.prefix(3).map { $0 }
    }

    static func progressLabel(_ tool: String) -> String {
        switch tool {
        case "get_walking_summary", "get_today_summary": "Checking your walking"
        case "get_weight_trend": "Looking at your weight trend"
        case "get_readiness": "Checking your readiness"
        case "get_sleep_summary": "Reading your sleep"
        case "compare_periods": "Comparing periods"
        case "find_correlation": "Looking for patterns"
        case "show_widget": "Preparing a chart"
        default: "Reading your history"
        }
    }
}
