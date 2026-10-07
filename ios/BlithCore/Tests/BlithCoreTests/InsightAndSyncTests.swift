import Foundation
import Testing
@testable import BlithCore

@Suite("Insights")
struct InsightTests {
    @Test func baselineChangeRequiresMeaningfulMagnitude() {
        var steps = T.constant(6000, days: 8...35)
        for d in 1...7 { steps[d] = 6200 } // +3%: below the 8% bar
        #expect(InsightEngine(T.ctx(T.history(steps: steps))).baselineChange() == nil)
        for d in 1...7 { steps[d] = 7080 } // +18%
        let i = InsightEngine(T.ctx(T.history(steps: steps))).baselineChange()!
        #expect(abs(i.change! - 0.18) < 1e-9)
        #expect(i.currentValue == 7080 && i.comparisonValue == 6000)
        #expect(i.explanation.contains("7,080") && i.explanation.contains("18%") && i.explanation.contains("6,000"))
        #expect(i.evidence.contains { $0.label == "Difference" && $0.value == "+18%" })
        #expect(i.comparisonRange == DateSpan(T.today.adding(days: -35), T.today.adding(days: -8)))
    }

    @Test func insufficientDataProducesNoInsights() {
        let engine = InsightEngine(T.ctx(T.history(steps: T.constant(7000, days: 0...3))))
        #expect(engine.allInsights().isEmpty)
        #expect(TodayHeadline.make(engine.ctx, pace: nil, feed: []).contains("still learning"))
    }

    @Test func consistencyComparesAgainstPriorRate() {
        var steps: [Int: Double] = [:]
        for d in 8...35 { steps[d] = d % 2 == 0 ? 7000 : 4000 } // median 5,500 → threshold 4,700; ~3.5 days/week
        for d in 1...7 { steps[d] = 7000 }
        let i = InsightEngine(T.ctx(T.history(steps: steps))).consistency()!
        #expect(i.currentValue == 7)
        #expect(i.headline.contains("consistent"))
    }

    @Test func sleepRelationshipAlwaysCarriesCaveat() {
        var h = T.history(steps: [:])
        var steps: [LocalDate: DailyAggregate] = [:]
        for ago in 1...60 {
            let d = T.today.adding(days: -ago)
            let short = ago % 6 == 0
            let asleep: Double = short ? 5 : 7.5
            let start = T.date(d, hour: 7 - asleep)
            h.sleepNights[d] = SleepNight(date: d, segments: [SleepSegment(start: start, end: start.addingTimeInterval(asleep * 3600), stage: .core, source: T.source)], source: T.source)
            steps[d] = DailyAggregate(date: d, metric: .steps, value: short ? 5000 : 7000)
        }
        h.daily[.steps] = steps
        let i = InsightEngine(T.ctx(h)).sleepMovement()!
        #expect(i.caveat == InsightEngine.relationshipCaveat)
        #expect(i.explanation.contains("2,000 fewer steps"))
        #expect(i.explanation.contains("not enough to say sleep caused it"))
    }

    @Test func feedIsRankedLimitedAndOnePerFamily() async throws {
        let provider = MockHealthProvider(scenario: .balanced, now: { T.now })
        var h = HealthHistory(origin: .demo(.balanced))
        h = try await SyncEngine(provider: provider, calendar: T.calendar, now: { T.now }).initialImport(into: h)
        let engine = InsightEngine(T.ctx(h, profile: UserProfile(goals: [.weightManagement])))
        let feed = engine.feed()
        #expect(feed.count <= 4 && !feed.isEmpty)
        #expect(Set(feed.map(\.kind.family)).count == feed.count)
        #expect(zip(feed, feed.dropFirst()).allSatisfy { $0.score >= $1.score })
        #expect(feed.allSatisfy { $0.score >= 0.3 })
        // Goal relevance lifts the weight insight.
        if let w = engine.allInsights().first(where: { $0.kind == .weightTrend }) {
            let without = InsightEngine(T.ctx(h)).allInsights().first { $0.kind == .weightTrend }!
            #expect(w.score > without.score)
        }
    }

    @Test func deterministicForSameInputs() async throws {
        let provider = MockHealthProvider(scenario: .improving, now: { T.now })
        let h = try await SyncEngine(provider: provider, calendar: T.calendar, now: { T.now }).initialImport(into: HealthHistory(origin: .demo(.improving)))
        let a = InsightEngine(T.ctx(h)).allInsights().map(\.explanation)
        let b = InsightEngine(T.ctx(h)).allInsights().map(\.explanation)
        #expect(a == b)
    }
}

@Suite("Sync and provenance")
struct SyncTests {
    @Test func initialImportThenIncrementalIsIdempotent() async throws {
        let provider = MockHealthProvider(scenario: .balanced, now: { T.now })
        let engine = SyncEngine(provider: provider, calendar: T.calendar, now: { T.now })
        var h = HealthHistory(origin: .demo(.balanced))
        h = try await engine.initialImport(into: h)
        let steps = h.values(.steps, in: DateSpan(T.today.adding(days: -60), T.today))
        let weights = h.weights.count
        #expect(h.sync.status == .idle && h.sync.initialImportCompleted != nil)
        #expect(steps.count == 61)
        #expect(!h.sleepNights.isEmpty && weights > 100 && !h.workouts.isEmpty)
        #expect(h.hourlySteps.count <= SyncEngine.hourlyWindowDays)
        // Re-sync the overlapping window: nothing is double counted.
        let h2 = try await engine.incrementalSync(h)
        #expect(h2.values(.steps, in: DateSpan(T.today.adding(days: -60), T.today)) == steps)
        #expect(h2.weights.count == weights)
        #expect(h2.workouts.count == h.workouts.count)
    }

    @Test func incrementalSyncBackfillsOnlyAMetricAddedLater() async throws {
        let provider = MockHealthProvider(scenario: .balanced, now: { T.now })
        let engine = SyncEngine(provider: provider, calendar: T.calendar, now: { T.now })
        var h = try await engine.initialImport(into: HealthHistory(origin: .demo(.balanced)))
        let workouts = h.workouts.count
        h.daily[.heartRate] = nil
        let h2 = try await engine.incrementalSync(h)
        // Older than the recent window, so only the backfill can have filled it.
        #expect(!h2.values(.heartRate, in: DateSpan(T.today.adding(days: -300), T.today.adding(days: -200))).isEmpty)
        #expect(h2.workouts.count == workouts)
    }

    @Test func missingScenariosDegradeGracefully() async throws {
        for scenario in [DemoScenario.missingSleep, .missingWeight, .noWalkingSpeed, .newUser, .partialPermissions] {
            let provider = MockHealthProvider(scenario: scenario, now: { T.now })
            let h = try await SyncEngine(provider: provider, calendar: T.calendar, now: { T.now }).initialImport(into: HealthHistory(origin: .demo(scenario)))
            let s = HealthSnapshot.build(history: h, profile: UserProfile(), now: T.now, calendar: T.calendar)
            switch scenario {
            case .missingSleep: #expect(s.sleep.lastNight == nil && s.availability[.sleepDuration] == .noData)
            case .missingWeight: #expect(s.weight == nil && s.availability[.weight] == .noData)
            case .noWalkingSpeed: #expect(s.availability[.walkingSpeed] == .unsupported)
            case .newUser: #expect(s.feed.isEmpty && s.average30?.days ?? 0 <= 2)
            default: #expect(s.weight == nil && s.sleep.lastNight == nil)
            }
        }
    }

    @Test func mergerTakesMaxPerHourNotSum() {
        var a = ProviderBatch()
        var b = ProviderBatch()
        a.hourlySteps[T.today] = HourlyBuckets(values: Array(repeating: 100, count: 24))
        b.hourlySteps[T.today] = HourlyBuckets(values: (0..<24).map { $0 < 12 ? 150 : 50 })
        a.daily[.steps] = [DailyAggregate(date: T.today, metric: .steps, value: 2400)]
        b.daily[.steps] = [DailyAggregate(date: T.today, metric: .steps, value: 2400)]
        let m = SourceMerger.merge([a, b])
        #expect(m.hourlySteps[T.today]!.total == 150 * 12 + 100 * 12)
        #expect(m.daily[.steps]!.first!.value == 3000)
    }

    @Test func duplicateReadingsAreKeptOnce() {
        let t = T.now
        let huawei = SourceRef(provider: .huawei, name: "Huawei Health", identifier: "com.huawei.health")
        let s = [
            HealthSample(id: "a", metric: .weight, value: 80.0, start: t, end: t, source: T.source, syncedAt: t),
            HealthSample(id: "b", metric: .weight, value: 80.02, start: t.addingTimeInterval(60), end: t, source: huawei, syncedAt: t),
            HealthSample(id: "c", metric: .weight, value: 79.1, start: t.addingTimeInterval(3600 * 24), end: t, source: huawei, syncedAt: t),
        ]
        #expect(SourceMerger.dedupeSamples(s, tolerance: 0.05).map(\.id) == ["a", "c"])
        #expect(huawei.deviceFamily == "huawei")
    }

    @Test func sleepAssemblerPicksOneSourcePerNightByWakeDate() {
        let phone = SourceRef(provider: .appleHealth, name: "iPhone", identifier: "phone")
        let watch = SourceRef(provider: .appleHealth, name: "Watch", identifier: "watch")
        let bed = T.date(T.today.adding(days: -1), hour: 23)
        let segments = [
            SleepSegment(start: bed, end: bed.addingTimeInterval(8 * 3600), stage: .asleepUnspecified, source: phone),
            SleepSegment(start: bed.addingTimeInterval(600), end: bed.addingTimeInterval(4 * 3600), stage: .core, source: watch),
            SleepSegment(start: bed.addingTimeInterval(4 * 3600), end: bed.addingTimeInterval(7 * 3600), stage: .deep, source: watch),
        ]
        let nights = SleepAssembler.nights(from: segments, calendar: T.calendar)
        #expect(nights.count == 1)
        #expect(nights[0].date == T.today)
        #expect(nights[0].source == watch) // staged source preferred
        #expect(abs(nights[0].asleepDuration - (7 * 3600 - 600)) < 1)
    }

    @Test func historyPersistsAndDecodesLeniently() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blith-test-\(UUID().uuidString)")
        let store = LocalHealthStore(directory: dir)
        var h = T.history(steps: T.constant(5000, days: 0...10))
        h.events = [HealthEvent(date: T.today, kind: .injury, title: "Twisted right ankle", bodyRegion: .rightAnkle, severity: 2)]
        try await store.save(h)
        let loaded = await store.load(.appleHealth)!
        #expect(loaded.values(.steps, in: DateSpan(T.today.adding(days: -10), T.today)).count == 11)
        #expect(loaded.events.first?.bodyRegion == .rightAnkle)
        // A file missing newer fields still loads.
        let minimal = #"{"origin":{"appleHealth":{}}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HealthHistory.self, from: minimal)
        #expect(decoded.daily.isEmpty && decoded.sync.status == .never)
        await store.deleteAll()
    }
}

@Suite("Assistant")
struct AssistantTests {
    func snapshot(_ steps: [Int: Double]) -> HealthSnapshot {
        HealthSnapshot.build(history: T.history(steps: steps), profile: UserProfile(), now: T.now, calendar: T.calendar)
    }

    @Test func comparePeriodsComputesChangeDeterministically() {
        var steps = T.constant(7410, days: 1...7)
        for d in 8...14 { steps[d] = 6810 }
        let tools = HealthAssistantTools(snapshot: snapshot(steps))
        let out = tools.execute(name: "compare_periods", arguments: [
            "metric": "steps",
            "a_start": .string(T.today.adding(days: -7).description), "a_end": .string(T.today.adding(days: -1).description),
            "b_start": .string(T.today.adding(days: -14).description), "b_end": .string(T.today.adding(days: -8).description),
        ])
        #expect(out.result["change_b_to_a_pct"]?.doubleValue == 8.8)
        #expect(out.result["period_a_daily_average"]?.stringValue == "7,410")
        guard case .comparison(let c)? = out.suggestedBlock else { Issue.record("expected comparison block"); return }
        #expect(c.valueA == 7410 && c.valueB == 6810)
    }

    @Test func showWidgetReturnsTrustedBlockWithDeepLink() {
        let tools = HealthAssistantTools(snapshot: snapshot(T.constant(6000, days: 0...40)))
        let out = tools.execute(name: "show_widget", arguments: ["type": "step_chart", "period": "month"])
        #expect(out.blocks.count == 1)
        #expect(out.blocks.first?.link == .walk(.month))
        let missing = tools.execute(name: "show_widget", arguments: ["type": "weight_chart"])
        #expect(missing.blocks.isEmpty)
        #expect(tools.execute(name: "get_weight_trend", arguments: [:]).result["error"] != nil)
    }

    @Test func invalidArgumentsAreReportedNotCrashed() {
        let tools = HealthAssistantTools(snapshot: snapshot([:]))
        #expect(tools.execute(name: "get_metric_summary", arguments: ["metric": "nope"]).result["error"] != nil)
        #expect(tools.execute(name: "unknown_tool", arguments: [:]).result["error"] != nil)
    }

    struct ScriptedClient: ChatCompletionClient {
        func complete(messages: [LLMMessage], tools: [ToolDefinition]) async throws -> LLMMessage {
            if messages.last?.role == "user" {
                return LLMMessage(role: "assistant", content: nil, tool_calls: [
                    .init(id: "1", type: "function", function: .init(name: "get_walking_summary", arguments: #"{"period":"week"}"#)),
                    .init(id: "2", type: "function", function: .init(name: "show_widget", arguments: #"{"type":"step_chart","period":"week"}"#)),
                ])
            }
            let tool = messages.last { $0.role == "tool" && $0.tool_call_id == "1" }!
            let avg = JSONValue.parse(tool.content!)!["daily_average_steps_complete_days"]!.doubleValue!
            return .assistant("You're averaging \(Fmt.int(avg)) steps a day this week.")
        }
    }

    @Test func orchestratorRunsToolsAndReturnsStructuredMessage() async throws {
        let tools = HealthAssistantTools(snapshot: snapshot(T.constant(7000, days: 0...40)))
        let reply = try await LLMAssistant(client: ScriptedClient(), tools: tools).respond(to: "How have I been walking?", history: []) { _ in }
        #expect(reply.text == "You're averaging 7,000 steps a day this week.")
        #expect(reply.toolsUsed == ["get_walking_summary", "show_widget"])
        #expect(reply.blocks.map(\.kind) == ["stepChart"])
        #expect(!reply.evidence.isEmpty)
    }

    @Test func urgentSymptomsBypassTheModel() async throws {
        let tools = HealthAssistantTools(snapshot: snapshot([:]))
        let reply = try await LLMAssistant(client: ScriptedClient(), tools: tools).respond(to: "I have chest pain after walking", history: []) { _ in }
        #expect(reply.text.contains("emergency"))
        #expect(reply.toolsUsed.isEmpty)
    }

    @Test func localAssistantAnswersCommonQuestions() async throws {
        let tools = HealthAssistantTools(snapshot: snapshot(T.constant(7000, days: 0...40)))
        let r = try await LocalAssistant(tools: tools).respond(to: "How have I been walking?", history: []) { _ in }
        #expect(r.text.contains("7,000"))
        #expect(r.blocks.first?.kind == "stepChart")
        let w = try await LocalAssistant(tools: tools).respond(to: "How has my weight changed?", history: []) { _ in }
        #expect(w.text.contains("no weight readings"))
    }

    @Test func profileContextIsMinimal() {
        let s = HealthSnapshot.build(history: T.history(steps: T.constant(7000, days: 0...40)), profile: UserProfile(name: "Zen"), now: T.now, calendar: T.calendar)
        let text = ProfileContext.summary(s)
        #expect(!text.contains("Zen")) // no name goes to the AI provider
        #expect(text.contains("2026-09-29"))
        #expect(text.count < 1500)
    }
}

@Suite("Huawei adapter")
struct HuaweiTests {
    struct FakeTransport: HuaweiHealthProvider.Transport {
        func dailyTotals(dataType: String, span: DateSpan, calendar: Calendar) async throws -> [(LocalDate, Double)] {
            dataType.contains("steps") ? span.days.map { ($0, 5000) } : []
        }
        func samples(dataType: String, interval: DateInterval) async throws -> [HuaweiHealthProvider.RawSample] {
            if dataType.contains("sleep") {
                let bed = T.date(T.today.adding(days: -1), hour: 23)
                return [.init(id: "s1", start: bed, end: bed.addingTimeInterval(3 * 3600), value: 1, device: nil),
                        .init(id: "s2", start: bed.addingTimeInterval(3 * 3600), end: bed.addingTimeInterval(5 * 3600), value: 2, device: nil)]
            }
            return [.init(id: "w1", start: T.now, end: T.now, value: 80.4, device: "HUAWEI Scale")]
        }
    }

    @Test func unconfiguredProviderIsUnavailable() async {
        let p = HuaweiHealthProvider()
        #expect(!p.isAvailable)
        await #expect(throws: HealthProviderError.self) { try await p.requestAuthorization(for: [.movement]) }
    }

    @Test func mapsToNormalizedTypesAndMergesWithoutDoubleCounting() async throws {
        let huawei = HuaweiHealthProvider(configuration: .init(clientID: "id", redirectURI: "blith://huawei"), transport: FakeTransport())
        let request = ProviderFetch(span: DateSpan(T.today.adding(days: -2), T.today), metrics: [.steps, .hrv], includeHourlySteps: false,
                                    includeSleep: true, includeBody: true, includeWorkouts: false, includeSources: false)
        let hb = try await huawei.fetch(request, calendar: T.calendar)
        #expect(hb.daily[.steps]?.count == 3)
        #expect(hb.unsupported.contains(.hrv))
        #expect(hb.weights.first?.source.provider == .huawei)
        let nights = SleepAssembler.nights(from: hb.sleepSegments, calendar: T.calendar)
        #expect(nights.first?.hasStages == true && nights.first?.date == T.today)

        var apple = ProviderBatch()
        apple.daily[.steps] = [DailyAggregate(date: T.today, metric: .steps, value: 5200)]
        let merged = SourceMerger.merge([apple, hb])
        #expect(merged.daily[.steps]?.first { $0.date == T.today }?.value == 5200) // max, not 10,200
        #expect(huawei.authorizationURL(state: "x")?.absoluteString.contains("client_id=id") == true)
    }
}

@Suite("Notes, streaks and achievements")
struct EngagementTests {
    @Test func streakCountsConsecutiveDaysAndKeepsTotals() {
        let days: Set<LocalDate> = [T.today, T.today.adding(days: -1), T.today.adding(days: -2), T.today.adding(days: -5), T.today.adding(days: -6)]
        let s = CheckInStreak.compute(days, today: T.today)
        #expect(s.current == 3 && s.best == 3 && s.total == 5 && s.checkedInToday)
        // Not checked in yet today: yesterday's run still counts.
        let y = CheckInStreak.compute(days.subtracting([T.today]), today: T.today)
        #expect(y.current == 2 && !y.checkedInToday)
    }

    @Test func achievementsCarryTheDayTheyBecameTrue() {
        var steps = T.constant(6000, days: 1...40)
        steps[12] = 10_400
        let h = T.history(steps: steps)
        let list = AchievementEngine.evaluate(history: h, engagement: Engagement(checkIns: [T.today], questionsAsked: 0),
                                              today: T.today, threshold: 5100)
        #expect(list.first { $0.id == "tenk" }?.unlockedOn == T.today.adding(days: -12))
        #expect(list.first { $0.id == "baseline" }?.unlockedOn == T.today.adding(days: -34))
        #expect(list.first { $0.id == "checkin3" }?.isUnlocked == false)
        #expect(list.first { $0.id == "firstask" }?.isUnlocked == false)
    }

    @Test func relativeDatesResolveToThePast() {
        #expect(RelativeDates.day(in: "why was my walking lower last tuesday?", today: T.today) == T.today.adding(days: -7))
        #expect(RelativeDates.day(in: "what about monday", today: T.today) == T.today.adding(days: -1))
        #expect(RelativeDates.day(in: "yesterday", today: T.today) == T.today.adding(days: -1))
        #expect(RelativeDates.day(in: "on Sep 3", today: T.today) == LocalDate(year: 2026, month: 9, day: 3))
        #expect(RelativeDates.day(in: "Dec 3", today: T.today) == LocalDate(year: 2025, month: 12, day: 3))
        #expect(RelativeDates.day(in: "how have I been walking", today: T.today) == nil)
    }

    func historyWithAnkleNote() -> (HealthHistory, HealthEvent) {
        var steps = T.constant(6400, days: 1...70)
        steps[7] = 3100 // last Tuesday
        var h = T.history(steps: steps)
        let note = HealthEvent(id: "n1", date: T.today.adding(days: -7), kind: .injury, title: "Rolled right ankle",
                               bodyRegion: .rightAnkle, createdAt: T.now)
        h.events = [note]
        return (h, note)
    }

    @Test func noteContextShowsRecordsSideBySideWithoutCausation() {
        let (h, _) = historyWithAnkleNote()
        let i = InsightEngine(T.ctx(h)).noteContext()!
        #expect(i.currentValue == 3100 && i.comparisonValue == 6400)
        #expect(i.caveat?.contains("can't establish") == true)
        #expect(i.link == .body("n1"))
        #expect(!i.explanation.lowercased().contains("because"))
    }

    @Test func localAssistantAnswersWhyALowerDay() async throws {
        let (h, _) = historyWithAnkleNote()
        let s = HealthSnapshot.build(history: h, profile: UserProfile(), now: T.now, calendar: T.calendar)
        let r = try await LocalAssistant(tools: HealthAssistantTools(snapshot: s)).respond(to: "Why was my walking lower last Tuesday?", history: []) { _ in }
        #expect(r.text.contains("3,100") && r.text.contains("6,400"))
        #expect(r.text.contains("can't establish what caused"))
        #expect(r.blocks.map(\.kind) == ["daySteps", "bodyNote"])
        #expect(r.blocks.first?.link == .walkDay(T.today.adding(days: -7)))
    }

    @Test func notesAreActiveOnlyUntilResolved() {
        let n = HealthEvent(date: T.today.adding(days: -10), kind: .pain, title: "Knee", resolvedDate: T.today.adding(days: -3))
        #expect(n.isActive(on: T.today.adding(days: -5)))
        #expect(!n.isActive(on: T.today))
        #expect(!n.isActive(on: T.today.adding(days: -11)))
        // Unknown stored regions decode as .other rather than dropping the note.
        let json = #"{"id":"x","date":"2026-09-01","title":"t","bodyRegion":"leftPinky"}"#.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(HealthEvent.self, from: json)
        #expect(decoded?.bodyRegion == .other && decoded?.kind == .note)
    }
}

@Suite("Assistant maths and heart rate")
struct AssistantMathTests {
    func tools(heartRate: [Int: (avg: Double, min: Double, max: Double)] = [:]) -> HealthAssistantTools {
        var h = T.history(steps: T.constant(6000, days: 0...10))
        var series: [LocalDate: DailyAggregate] = [:]
        for (ago, v) in heartRate {
            let date = T.today.adding(days: -ago)
            series[date] = DailyAggregate(date: date, metric: .heartRate, value: v.avg, min: v.min, max: v.max)
        }
        h.daily[.heartRate] = series
        return HealthAssistantTools(snapshot: HealthSnapshot.build(history: h, profile: UserProfile(), now: T.now, calendar: T.calendar))
    }

    @Test func calculateEvaluatesWithPrecedenceAndFunctions() {
        let t = tools()
        func result(_ e: String) -> Double? { t.execute(name: "calculate", arguments: ["expression": .string(e)]).result["result"]?.doubleValue }
        #expect(result("(62 + 58 + 61) / 3") == 60.3333)
        #expect(result("220 - 34") == 186)
        #expect(result("2 + 3 * 4") == 14)
        #expect(result("-2 ^ 2") == -4)
        #expect(result("round(7.456, 1)") == 7.5)
        #expect(result("max(55, 65, 60) - min(55, 65, 60)") == 10)
        #expect(t.execute(name: "calculate", arguments: ["expression": "1 / 0"]).result["error"] != nil)
        #expect(t.execute(name: "calculate", arguments: ["expression": "foo(1)"]).result["error"] != nil)
        #expect(t.execute(name: "calculate", arguments: ["expression": ""]).result["error"] != nil)
    }

    @Test func heartRateRangeReturnsHighestReadingAndItsDay() {
        let t = tools(heartRate: [1: (70, 52, 131), 3: (75, 50, 168), 6: (72, 54, 149)])
        let out = t.execute(name: "get_heart_rate_range", arguments: [:])
        #expect(out.result["highest_reading"]?.stringValue == "168 bpm")
        #expect(out.result["highest_reading_date"]?.stringValue?.hasPrefix(T.today.adding(days: -3).description) == true)
        #expect(out.result["lowest_reading"]?.stringValue == "50 bpm")
        #expect(out.result["days_with_data"]?.doubleValue == 3)
    }

    @Test func heartRateRangeWithoutReadingsReportsMissingData() {
        #expect(tools().execute(name: "get_heart_rate_range", arguments: [:]).result["error"] != nil)
    }
}
