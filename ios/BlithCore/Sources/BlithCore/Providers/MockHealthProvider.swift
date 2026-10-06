import Foundation

/// Named demo worlds for design, QA and App Review. Demo data is always labelled as sample
/// data in the UI and stored separately from real data.
public enum DemoScenario: String, Codable, CaseIterable, Sendable, Identifiable {
    case balanced
    case highActivity
    case lowActivity
    case improving
    case declining
    case weekendHeavy
    case weightDeclining
    case weightFluctuating
    case missingSleep
    case missingWeight
    case noWalkingSpeed
    case partialPermissions
    case newUser

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: "Typical year"
        case .highActivity: "High activity"
        case .lowActivity: "Low activity"
        case .improving: "Improving trend"
        case .declining: "Declining trend"
        case .weekendHeavy: "Weekend-heavy movement"
        case .weightDeclining: "Weight slowly declining"
        case .weightFluctuating: "Weight fluctuating"
        case .missingSleep: "No sleep data"
        case .missingWeight: "No weight data"
        case .noWalkingSpeed: "No walking speed"
        case .partialPermissions: "Movement only"
        case .newUser: "Brand-new user (3 days)"
        }
    }
}

/// Deterministic, realistic sample data. Every value is a pure function of (seed, scenario,
/// day), so chunked fetches are consistent and tests are reproducible.
public struct MockHealthProvider: HealthDataProvider {
    public let scenario: DemoScenario
    public let seed: UInt64
    public let now: @Sendable () -> Date
    /// Screenshots only: pretend Huawei Health last wrote to Apple Health this long ago.
    public let huaweiLag: TimeInterval?
    public var kind: ProviderKind { .demo }
    public var isAvailable: Bool { true }

    public init(scenario: DemoScenario = .balanced, seed: UInt64 = 42, now: @escaping @Sendable () -> Date = { Date() },
                huaweiLag: TimeInterval? = nil) {
        self.scenario = scenario
        self.seed = seed
        self.now = now
        self.huaweiLag = huaweiLag
    }

    static let watch = SourceRef(provider: .demo, name: "Apple Watch", identifier: "com.apple.health.demo.watch", device: "Watch")
    static let phone = SourceRef(provider: .demo, name: "iPhone", identifier: "com.apple.health.demo.phone", device: "iPhone")
    static let scale = SourceRef(provider: .demo, name: "Smart scale", identifier: "com.demo.scale", device: "Scale")

    var historyDays: Int { scenario == .newUser ? 3 : 420 }

    /// The sample ankle note's date; walking dips for a few days after it.
    public static let ankleNoteDaysAgo = 40

    public func requestAuthorization(for categories: Set<HealthCategory>) async throws {}

    public func earliestDataDate() async -> Date? {
        let cal = Calendar.current
        return LocalDate(now(), calendar: cal).adding(days: -(historyDays - 1)).startDate(in: cal)
    }

    public func fetch(_ request: ProviderFetch, calendar: Calendar) async throws -> ProviderBatch {
        var batch = ProviderBatch()
        let nowDate = now()
        let today = LocalDate(nowDate, calendar: calendar)
        let first = today.adding(days: -(historyDays - 1))
        let hourNow = Double(calendar.component(.hour, from: nowDate)) + Double(calendar.component(.minute, from: nowDate)) / 60

        var days: [DailyAggregate] = []
        var distance: [DailyAggregate] = []
        var energy: [DailyAggregate] = []
        var exercise: [DailyAggregate] = []
        var flights: [DailyAggregate] = []
        var speed: [DailyAggregate] = []
        var stepLength: [DailyAggregate] = []
        var asymmetry: [DailyAggregate] = []
        var doubleSupport: [DailyAggregate] = []
        var rhr: [DailyAggregate] = []
        var hrv: [DailyAggregate] = []
        var walkingHR: [DailyAggregate] = []
        var resp: [DailyAggregate] = []
        var spo2: [DailyAggregate] = []
        var temp: [DailyAggregate] = []
        var vo2: [DailyAggregate] = []

        for date in request.span.days where date >= first && date <= today {
            var hours = hourly(for: date, today: today)
            if date == today {
                hours = HourlyBuckets(values: hours.values.enumerated().map { i, v in
                    Double(i) < floor(hourNow) ? v : (Double(i) == floor(hourNow) ? (v * (hourNow - floor(hourNow))).rounded() : 0)
                })
            }
            let steps = hours.total
            if request.includeHourlySteps { batch.hourlySteps[date] = hours }
            days.append(DailyAggregate(date: date, metric: .steps, value: steps, sampleCount: 24))
            var rng = rngFor(date, salt: 7)
            let strideM = 0.71 + rng.gaussian() * 0.01
            distance.append(DailyAggregate(date: date, metric: .distanceWalkingRunning, value: (steps * strideM).rounded()))
            energy.append(DailyAggregate(date: date, metric: .activeEnergy, value: (steps * 0.042 + 90 + rng.gaussian() * 25).rounded()))
            exercise.append(DailyAggregate(date: date, metric: .exerciseMinutes, value: max(0, (steps / 260 + rng.gaussian() * 6).rounded())))
            flights.append(DailyAggregate(date: date, metric: .flightsClimbed, value: max(0, (4 + rng.gaussian() * 3).rounded())))

            let k = Double(date.days(until: today))
            if scenario != .noWalkingSpeed && steps > 1500 && rng.uniform() < 0.85 {
                // Walking speed improves ~4% over the last 8 weeks.
                let gain = k < 56 ? 0.07 * (1 - k / 56) : 0
                let v = 1.22 + gain + rng.gaussian() * 0.03
                speed.append(DailyAggregate(date: date, metric: .walkingSpeed, value: v, min: v - 0.15, max: v + 0.18, sampleCount: 6))
                stepLength.append(DailyAggregate(date: date, metric: .walkingStepLength, value: 0.70 + gain * 0.2 + rng.gaussian() * 0.01, sampleCount: 6))
                asymmetry.append(DailyAggregate(date: date, metric: .walkingAsymmetry, value: max(0, 0.025 + rng.gaussian() * 0.008), sampleCount: 4))
                doubleSupport.append(DailyAggregate(date: date, metric: .walkingDoubleSupport, value: 0.275 + rng.gaussian() * 0.008, sampleCount: 4))
            }
            if scenario != .partialPermissions {
                // Overnight vitals respond to the night's sleep and the previous day's load, so
                // readiness moves for believable reasons.
                var v = rngFor(date, salt: 8)
                let sleepEffect = max(-1, min(1, ((sleepHours(for: date) ?? 7.1) - 7.1) / 1.4))
                let loadEffect = max(-1, min(1, (hourly(for: date.adding(days: -1), today: today).total - 7_500) / 5_000))
                let sinceAnkle = Self.ankleNoteDaysAgo - date.days(until: today)
                let ankle = scenario == .balanced && (0...3).contains(sinceAnkle) ? 1.0 : 0
                let restingHR = 58.5 + 2.5 * min(k, 120) / 120 - 1.3 * sleepEffect + 1.1 * loadEffect + 1.8 * ankle + v.gaussian() * 1.2
                rhr.append(DailyAggregate(date: date, metric: .restingHeartRate, value: restingHR, sampleCount: 1))
                let variability = 46 + 6.5 * sleepEffect - 4.5 * loadEffect - 5 * ankle + v.gaussian() * 6
                hrv.append(DailyAggregate(date: date, metric: .hrv, value: max(15, variability), sampleCount: 5))
                walkingHR.append(DailyAggregate(date: date, metric: .walkingHeartRate, value: 99 - 3 * min(1, max(0, 1 - k / 70)) + v.gaussian() * 3, sampleCount: 8))
                resp.append(DailyAggregate(date: date, metric: .respiratoryRate, value: 14.6 + 0.35 * ankle + v.gaussian() * 0.35, sampleCount: 1))
                spo2.append(DailyAggregate(date: date, metric: .oxygenSaturation, value: min(0.995, 0.966 + v.gaussian() * 0.006), sampleCount: 6))
                if scenario != .missingSleep {
                    temp.append(DailyAggregate(date: date, metric: .wristTemperature, value: 35.92 + 0.12 * ankle + v.gaussian() * 0.12, sampleCount: 1))
                }
                if v.uniform() < 0.22 {
                    // Cardio fitness creeps up with the recent walking.
                    vo2.append(DailyAggregate(date: date, metric: .vo2Max, value: 40.6 + 1.9 * max(0, 1 - k / 120) + v.gaussian() * 0.25, sampleCount: 1))
                }
            }
        }

        let wanted = Set(request.metrics)
        func put(_ m: HealthMetric, _ v: [DailyAggregate]) { if wanted.contains(m) { batch.daily[m] = v } }
        put(.steps, days)
        put(.distanceWalkingRunning, distance)
        put(.activeEnergy, energy)
        put(.exerciseMinutes, exercise)
        put(.flightsClimbed, flights)
        put(.walkingSpeed, speed)
        put(.walkingStepLength, stepLength)
        put(.walkingAsymmetry, asymmetry)
        put(.walkingDoubleSupport, doubleSupport)
        put(.restingHeartRate, rhr)
        put(.hrv, hrv)
        put(.walkingHeartRate, walkingHR)
        put(.respiratoryRate, resp)
        put(.oxygenSaturation, spo2)
        put(.wristTemperature, temp)
        put(.vo2Max, vo2)
        if scenario == .noWalkingSpeed { batch.unsupported = [.walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport] }

        if request.includeBody && scenario != .missingWeight && scenario != .partialPermissions {
            batch.weights = weights(in: request.span, first: first, today: today, calendar: calendar)
        }
        if request.includeSleep && scenario != .missingSleep && scenario != .partialPermissions {
            batch.sleepSegments = sleepSegments(in: request.span, first: first, today: today, calendar: calendar)
        }
        if request.includeWorkouts {
            batch.workouts = workouts(in: request.span, first: first, today: today, calendar: calendar)
        }
        if request.includeSources {
            let total = days.reduce(0) { $0 + $1.value }
            batch.sources[.steps] = [SourceShare(source: Self.watch, value: (total * 0.64).rounded()),
                                     SourceShare(source: Self.phone, value: (total * 0.36).rounded())]
            if !batch.weights.isEmpty { batch.sources[.weight] = [SourceShare(source: Self.scale, value: Double(batch.weights.count))] }
            if let huaweiLag {
                let last = now().addingTimeInterval(-huaweiLag)
                batch.sourceRecency[CompanionApp.huawei.rawValue] = SourceRecency(
                    app: .huawei,
                    latest: [.steps: last, .distanceWalkingRunning: last, .restingHeartRate: last.addingTimeInterval(-3600),
                             .sleepDuration: last.addingTimeInterval(-8 * 3600)],
                    checkedAt: now())
            }
        }
        return batch
    }

    // MARK: Generators

    /// Expected steps for a day before noise, by scenario.
    func baseSteps(_ date: LocalDate, today: LocalDate) -> Double {
        let k = Double(date.days(until: today)) // days ago
        var base: Double
        switch scenario {
        case .highActivity: base = 11_200
        case .lowActivity: base = 3_400
        case .improving: base = 5_200 + 2_300 * max(0, 1 - k / 90)
        case .declining: base = 8_400 - 2_600 * max(0, 1 - k / 90)
        default:
            // A believable year: a dip last winter, then a steady climb over the last ~10 weeks.
            base = 6_300 + 700 * sin(Double(date.dayNumber) / 58) + 1_150 * max(0, 1 - k / 70)
        }
        let weekday = date.weekday
        let weekdayFactor: Double
        if scenario == .weekendHeavy {
            weekdayFactor = [1: 1.55, 2: 0.78, 3: 0.82, 4: 0.8, 5: 0.84, 6: 0.9, 7: 1.7][weekday] ?? 1
        } else {
            weekdayFactor = [1: 0.82, 2: 0.97, 3: 1.04, 4: 0.99, 5: 1.03, 6: 0.98, 7: 1.24][weekday] ?? 1
        }
        return base * weekdayFactor
    }

    func hourly(for date: LocalDate, today: LocalDate) -> HourlyBuckets {
        var rng = rngFor(date, salt: 1)
        var total = baseSteps(date, today: today) * exp(rng.gaussian() * 0.2)
        if rng.uniform() < 0.05 { total *= 0.4 } // an occasional quiet day
        // The night before being short trims the next day (lets the sleep insight emerge honestly).
        if let asleep = sleepHours(for: date), asleep < 6 { total *= 0.83 }
        // Around the sample ankle note: a clear dip, recovering over ~5 days.
        let sinceAnkle = Self.ankleNoteDaysAgo - date.days(until: today)
        if scenario == .balanced, (0...5).contains(sinceAnkle) { total *= [0.42, 0.48, 0.58, 0.7, 0.82, 0.92][sinceAnkle] }
        let k = date.days(until: today)
        // This week the balanced user walks later in the day.
        let shiftLater = (scenario == .balanced || scenario == .improving) && k < 7
        var weights: [Double] = (0..<24).map { h in
            let x = Double(h)
            let morning = 1.0 * exp(-pow((x - 8.2) / 1.3, 2))
            let lunch = 0.8 * exp(-pow((x - 12.6) / 1.2, 2))
            let evening = (shiftLater ? 1.9 : 1.1) * exp(-pow((x - 18.2) / 1.8, 2))
            let day = 0.25 * (x >= 7 && x <= 21 ? 1 : 0)
            let base = morning * (shiftLater ? 0.5 : 1) + lunch + evening + day
            return max(0, base * (1 + rng.gaussian() * 0.25))
        }
        let sum = weights.reduce(0, +)
        weights = weights.map { ($0 / sum * total).rounded() }
        return HourlyBuckets(values: weights)
    }

    func sleepHours(for date: LocalDate) -> Double? {
        guard scenario != .missingSleep, scenario != .partialPermissions else { return nil }
        var rng = rngFor(date, salt: 3)
        var hours = 7.15 + rng.gaussian() * 0.6
        if rng.uniform() < 0.14 { hours = 5.2 + rng.uniform() * 0.7 }
        return hours
    }

    func sleepSegments(in span: DateSpan, first: LocalDate, today: LocalDate, calendar: Calendar) -> [SleepSegment] {
        var out: [SleepSegment] = []
        for date in span.days where date >= first && date <= today {
            guard let hours = sleepHours(for: date) else { continue }
            var rng = rngFor(date, salt: 4)
            let wake = date.startDate(in: calendar).addingTimeInterval((6.6 + rng.gaussian() * 0.45) * 3600)
            var cursor = wake.addingTimeInterval(-hours * 3600 - 18 * 60)
            out.append(SleepSegment(start: cursor, end: cursor.addingTimeInterval(14 * 60), stage: .awake, source: Self.watch))
            cursor = cursor.addingTimeInterval(14 * 60)
            // ~90 minute cycles: core → deep → core → REM, deep shrinking and REM growing.
            var cycle = 0
            while cursor < wake.addingTimeInterval(-4 * 60) {
                let remaining = wake.timeIntervalSince(cursor)
                let deep = max(4, 28 - Double(cycle) * 7 + rng.gaussian() * 4) * 60
                let rem = min(40, 12 + Double(cycle) * 6 + rng.gaussian() * 3) * 60
                let core1 = (25 + rng.gaussian() * 5) * 60
                let core2 = (20 + rng.gaussian() * 5) * 60
                for (stage, length) in [(SleepStage.core, core1), (.deep, deep), (.core, core2), (.rem, rem)] {
                    let len = min(length, wake.timeIntervalSince(cursor))
                    guard len > 60 else { break }
                    out.append(SleepSegment(start: cursor, end: cursor.addingTimeInterval(len), stage: stage, source: Self.watch))
                    cursor = cursor.addingTimeInterval(len)
                }
                if remaining > 30 * 60 && rng.uniform() < 0.35 {
                    out.append(SleepSegment(start: cursor, end: cursor.addingTimeInterval(4 * 60), stage: .awake, source: Self.watch))
                    cursor = cursor.addingTimeInterval(4 * 60)
                }
                cycle += 1
            }
            out.append(SleepSegment(start: wake, end: wake.addingTimeInterval(5 * 60), stage: .awake, source: Self.watch))
        }
        return out
    }

    func weights(in span: DateSpan, first: LocalDate, today: LocalDate, calendar: Calendar) -> [HealthSample] {
        var out: [HealthSample] = []
        for date in span.days where date >= first && date <= today {
            var rng = rngFor(date, salt: 5)
            guard rng.uniform() < 0.72 else { continue }
            let k = Double(date.days(until: today))
            let trend: Double
            let noise: Double
            switch scenario {
            case .weightFluctuating:
                trend = 81.0
                noise = 1.1
            case .weightDeclining:
                trend = 80.2 + k * 0.045
                noise = 0.45
            default:
                // Flat until ~10 weeks ago, then drifting down ~0.25 kg a week.
                trend = 82.9 + (k < 70 ? -0.036 * (70 - k) : 0) + 0.3 * sin(Double(date.dayNumber) / 40)
                noise = 0.5
            }
            let value = ((trend + rng.gaussian() * noise) * 10).rounded() / 10
            let time = date.startDate(in: calendar).addingTimeInterval((7.1 + rng.uniform() * 0.8) * 3600)
            out.append(HealthSample(id: "demo-weight-\(date)", metric: .weight, value: value, start: time, end: time,
                                    source: Self.scale, syncedAt: time))
        }
        return out
    }

    func workouts(in span: DateSpan, first: LocalDate, today: LocalDate, calendar: Calendar) -> [WorkoutRecord] {
        var out: [WorkoutRecord] = []
        for date in span.days where date >= first && date <= today {
            var rng = rngFor(date, salt: 6)
            let roll = rng.uniform()
            let isWalkDay = [1, 3, 5, 7].contains(date.weekday) ? roll < 0.55 : roll < 0.15
            guard isWalkDay, scenario != .lowActivity else { continue }
            let run = rng.uniform() < 0.15
            let minutes = run ? 28 + rng.uniform() * 15 : 32 + rng.uniform() * 40
            let start = date.startDate(in: calendar).addingTimeInterval((17.5 + rng.gaussian() * 1.2) * 3600)
            guard date < today || start.addingTimeInterval(minutes * 60) < now() else { continue }
            let speed = run ? 2.7 : 1.35
            out.append(WorkoutRecord(id: "demo-workout-\(date)", activity: run ? "Running" : "Walking",
                                     start: start, end: start.addingTimeInterval(minutes * 60),
                                     energyKcal: (minutes * (run ? 10.5 : 4.6)).rounded(),
                                     distanceMeters: (minutes * 60 * speed).rounded(), source: Self.watch))
        }
        return out
    }

    func rngFor(_ date: LocalDate, salt: UInt64) -> SeededRandom {
        SeededRandom(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(date.dayNumber)) &* 31 &+ salt &* 0x5851_F42D)
    }
}

/// SplitMix64: tiny, fast, deterministic.
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// Standard normal via Box–Muller.
    public mutating func gaussian() -> Double {
        let u1 = max(uniform(), 1e-12)
        let u2 = uniform()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
