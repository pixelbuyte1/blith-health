import Foundation

/// Which world the stored history belongs to. Demo data is never mixed with a real provider's
/// data: each origin is persisted in its own file.
public enum DataOrigin: Codable, Hashable, Sendable {
    case appleHealth
    case demo(DemoScenario)

    public var isDemo: Bool { if case .demo = self { true } else { false } }

    public var fileName: String {
        switch self {
        case .appleHealth: "history-applehealth.json"
        case .demo(let s): "history-demo-\(s.rawValue).json"
        }
    }

    public var providerKind: ProviderKind {
        switch self {
        case .appleHealth: .appleHealth
        case .demo: .demo
        }
    }
}

public struct SyncMetadata: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case never, importing, idle, failed }

    public var status: Status = .never
    public var lastSync: Date?
    public var initialImportCompleted: Date?
    /// Earliest day imported so far.
    public var importedFrom: LocalDate?
    public var lastError: String?

    public init() {}
}

/// Everything the app knows about the user's health, as normalized daily aggregates plus the
/// few raw series the product needs (weights, sleep nights, workouts, hourly steps).
///
/// Days are replaced wholesale on re-sync, which is what makes incremental sync idempotent:
/// re-importing a day can never double count it.
public struct HealthHistory: Codable, Sendable {
    public var origin: DataOrigin
    public var daily: [HealthMetric: [LocalDate: DailyAggregate]]
    /// Hourly step buckets; kept for a rolling window (see `SyncEngine.hourlyWindowDays`).
    public var hourlySteps: [LocalDate: HourlyBuckets]
    public var weights: [HealthSample]
    public var bodyFat: [HealthSample]
    public var sleepNights: [LocalDate: SleepNight]
    public var workouts: [WorkoutRecord]
    /// Per-source contribution over the recent window, per metric.
    public var sources: [HealthMetric: [SourceShare]]
    /// When each companion app (Huawei Health) last wrote to Apple Health, keyed by `CompanionApp.rawValue`.
    public var sourceRecency: [String: SourceRecency]
    public var requestedCategories: Set<HealthCategory>
    public var unsupportedMetrics: Set<HealthMetric>
    public var events: [HealthEvent]
    public var sync: SyncMetadata

    public init(origin: DataOrigin) {
        self.origin = origin
        daily = [:]
        hourlySteps = [:]
        weights = []
        bodyFat = []
        sleepNights = [:]
        workouts = []
        sources = [:]
        sourceRecency = [:]
        requestedCategories = []
        unsupportedMetrics = []
        events = []
        sync = SyncMetadata()
    }

    enum CodingKeys: String, CodingKey {
        case origin, daily, hourlySteps, weights, bodyFat, sleepNights, workouts, sources, sourceRecency
        case requestedCategories, unsupportedMetrics, events, sync
    }

    // Lenient decoding: a field added in a later version must never discard stored history.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decode(DataOrigin.self, forKey: .origin)
        daily = (try? c.decode([HealthMetric: [LocalDate: DailyAggregate]].self, forKey: .daily)) ?? [:]
        hourlySteps = (try? c.decode([LocalDate: HourlyBuckets].self, forKey: .hourlySteps)) ?? [:]
        weights = (try? c.decode([HealthSample].self, forKey: .weights)) ?? []
        bodyFat = (try? c.decode([HealthSample].self, forKey: .bodyFat)) ?? []
        sleepNights = (try? c.decode([LocalDate: SleepNight].self, forKey: .sleepNights)) ?? [:]
        workouts = (try? c.decode([WorkoutRecord].self, forKey: .workouts)) ?? []
        sources = (try? c.decode([HealthMetric: [SourceShare]].self, forKey: .sources)) ?? [:]
        sourceRecency = (try? c.decode([String: SourceRecency].self, forKey: .sourceRecency)) ?? [:]
        requestedCategories = (try? c.decode(Set<HealthCategory>.self, forKey: .requestedCategories)) ?? []
        unsupportedMetrics = (try? c.decode(Set<HealthMetric>.self, forKey: .unsupportedMetrics)) ?? []
        events = (try? c.decode([HealthEvent].self, forKey: .events)) ?? []
        sync = (try? c.decode(SyncMetadata.self, forKey: .sync)) ?? SyncMetadata()
    }

    // MARK: Reads

    public func value(_ metric: HealthMetric, on date: LocalDate) -> Double? {
        if metric == .sleepDuration {
            guard let night = sleepNights[date] else { return nil }
            let asleep = night.asleepDuration
            return asleep > 0 ? asleep : nil
        }
        return daily[metric]?[date]?.value
    }

    /// Values for each day in the span; days without data are omitted (never treated as zero).
    public func values(_ metric: HealthMetric, in span: DateSpan) -> [LocalDate: Double] {
        var out: [LocalDate: Double] = [:]
        if metric == .sleepDuration {
            for (date, night) in sleepNights where span.contains(date) {
                let asleep = night.asleepDuration
                if asleep > 0 { out[date] = asleep }
            }
            return out
        }
        guard let series = daily[metric] else { return [:] }
        if series.count < span.dayCount {
            for (date, agg) in series where span.contains(date) { out[date] = agg.value }
        } else {
            for date in span.days { if let v = series[date]?.value { out[date] = v } }
        }
        return out
    }

    public func firstDate(_ metric: HealthMetric, calendar: Calendar) -> LocalDate? {
        switch metric {
        case .weight: weights.map { $0.start }.min().map { LocalDate($0, calendar: calendar) }
        case .bodyFat: bodyFat.map { $0.start }.min().map { LocalDate($0, calendar: calendar) }
        case .sleepDuration: sleepNights.keys.min()
        default: daily[metric]?.keys.min()
        }
    }

    public func lastDate(_ metric: HealthMetric, calendar: Calendar) -> LocalDate? {
        switch metric {
        case .weight: weights.map { $0.start }.max().map { LocalDate($0, calendar: calendar) }
        case .bodyFat: bodyFat.map { $0.start }.max().map { LocalDate($0, calendar: calendar) }
        case .sleepDuration: sleepNights.keys.max()
        default: daily[metric]?.keys.max()
        }
    }

    public func availability(_ metric: HealthMetric, today: LocalDate, calendar: Calendar) -> MetricAvailability {
        if unsupportedMetrics.contains(metric) { return .unsupported }
        if !origin.isDemo && !requestedCategories.contains(metric.category) { return .notAuthorized }
        guard let last = lastDate(metric, calendar: calendar) else { return .noData }
        return last.days(until: today) > metric.staleAfterDays ? .stale : .available
    }

    public var hasAnyData: Bool {
        !(daily[.steps]?.isEmpty ?? true) || !weights.isEmpty || !sleepNights.isEmpty
    }

    // MARK: Writes

    /// Replace every stored day in `span` for `metric` with `aggregates` (idempotent).
    public mutating func replaceDaily(_ metric: HealthMetric, in span: DateSpan, with aggregates: [DailyAggregate]) {
        var series = daily[metric] ?? [:]
        for date in series.keys where span.contains(date) { series[date] = nil }
        for agg in aggregates where span.contains(agg.date) { series[agg.date] = agg }
        daily[metric] = series
    }

    public mutating func replaceHourly(in span: DateSpan, with buckets: [LocalDate: HourlyBuckets]) {
        for date in hourlySteps.keys where span.contains(date) { hourlySteps[date] = nil }
        for (date, b) in buckets where span.contains(date) { hourlySteps[date] = b }
    }

    public mutating func replaceSleep(in span: DateSpan, with nights: [SleepNight]) {
        for date in sleepNights.keys where span.contains(date) { sleepNights[date] = nil }
        for n in nights where span.contains(n.date) { sleepNights[n.date] = n }
    }

    /// Merge samples by id so re-fetching an overlapping window never duplicates readings.
    public mutating func mergeSamples(_ samples: [HealthSample], into keyPath: WritableKeyPath<HealthHistory, [HealthSample]>, replacing interval: DateInterval) {
        var kept = self[keyPath: keyPath].filter { !interval.contains($0.start) }
        var seen = Set(kept.map(\.id))
        for s in samples where !seen.contains(s.id) {
            kept.append(s)
            seen.insert(s.id)
        }
        self[keyPath: keyPath] = kept.sorted { $0.start < $1.start }
    }

    public mutating func mergeWorkouts(_ items: [WorkoutRecord], replacing interval: DateInterval) {
        var kept = workouts.filter { !interval.contains($0.start) }
        var seen = Set(kept.map(\.id))
        for w in items where !seen.contains(w.id) {
            kept.append(w)
            seen.insert(w.id)
        }
        workouts = kept.sorted { $0.start < $1.start }
    }

    /// Drop hourly buckets older than the retention window.
    public mutating func pruneHourly(keepingFrom date: LocalDate) {
        for key in hourlySteps.keys where key < date { hourlySteps[key] = nil }
    }
}
