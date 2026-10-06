import Foundation

public struct SyncProgress: Sendable, Equatable {
    public enum Stage: Int, Sendable, CaseIterable {
        case connecting, importingRecent, importingHistory, analyzing, done

        public var title: String {
            switch self {
            case .connecting: "Connecting health data"
            case .importingRecent: "Reading your recent weeks"
            case .importingHistory: "Building your history"
            case .analyzing: "Understanding your patterns"
            case .done: "Ready"
            }
        }
    }

    public var stage: Stage
    /// 0…1 across the whole import, derived from completed chunks.
    public var fraction: Double
    public var detail: String

    public init(stage: Stage, fraction: Double, detail: String) {
        self.stage = stage
        self.fraction = fraction
        self.detail = detail
    }
}

/// Imports history from a provider into `HealthHistory`.
///
/// - Initial import reads the most recent 120 days first (so Today and Walk work quickly),
///   then walks backwards a year at a time, up to `maxYears`.
/// - Incremental sync re-reads from two days before the last sync through today. Days are
///   replaced, not added to, so overlapping windows never double count.
/// - Each chunk is retried with backoff before the sync is marked failed; completed chunks
///   are kept.
public struct SyncEngine: Sendable {
    public static let recentWindowDays = 120
    public static let hourlyWindowDays = 120
    public static let sourceWindowDays = 30

    public let provider: any HealthDataProvider
    public let calendar: Calendar
    public let now: @Sendable () -> Date
    public var maxYears: Int
    public var retryDelays: [Double]

    public init(provider: any HealthDataProvider, calendar: Calendar, maxYears: Int = 5,
                retryDelays: [Double] = [0.5, 1.5], now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.calendar = calendar
        self.maxYears = maxYears
        self.retryDelays = retryDelays
        self.now = now
    }

    public func initialImport(into history: HealthHistory,
                              progress: @Sendable (SyncProgress) -> Void = { _ in }) async throws -> HealthHistory {
        var h = history
        let today = LocalDate(now(), calendar: calendar)
        h.sync.status = .importing
        progress(SyncProgress(stage: .connecting, fraction: 0.02, detail: "Checking what's available"))

        let cap = today.adding(days: -365 * maxYears)
        let earliest = await provider.earliestDataDate().map { LocalDate($0, calendar: calendar) } ?? today.adding(days: -Self.recentWindowDays)
        let oldest = max(cap, min(earliest, today.adding(days: -Self.recentWindowDays)))

        var chunks: [DateSpan] = [DateSpan(today.adding(days: -(Self.recentWindowDays - 1)), today)]
        var cursor = today.adding(days: -Self.recentWindowDays)
        while cursor >= oldest {
            let start = max(oldest, cursor.adding(days: -364))
            chunks.append(DateSpan(start, cursor))
            cursor = start.adding(days: -1)
        }

        for (index, span) in chunks.enumerated() {
            let stage: SyncProgress.Stage = index == 0 ? .importingRecent : .importingHistory
            let detail = index == 0 ? "Last \(Self.recentWindowDays) days" : "\(Self.monthYear(span.start)) – \(Self.monthYear(span.end))"
            progress(SyncProgress(stage: stage, fraction: 0.05 + 0.85 * Double(index) / Double(chunks.count), detail: detail))
            let batch = try await fetchWithRetry(request(for: span, today: today, isMostRecent: index == 0))
            ingest(batch, span: span, into: &h, today: today)
            h.sync.importedFrom = span.start
        }

        progress(SyncProgress(stage: .analyzing, fraction: 0.95, detail: "Calculating your baselines"))
        h.sync.status = .idle
        h.sync.lastSync = now()
        h.sync.initialImportCompleted = now()
        h.sync.lastError = nil
        return h
    }

    public func incrementalSync(_ history: HealthHistory) async throws -> HealthHistory {
        var h = history
        let today = LocalDate(now(), calendar: calendar)
        let lastDay = h.sync.lastSync.map { LocalDate($0, calendar: calendar) } ?? today.adding(days: -Self.recentWindowDays)
        var start = min(today.adding(days: -2), lastDay.adding(days: -2))
        start = max(start, today.adding(days: -365 * maxYears))
        // Long gaps are fetched in the same chunk sizes as the initial import.
        var spans: [DateSpan] = []
        var cursor = today
        while cursor >= start {
            let s = max(start, cursor.adding(days: -(Self.recentWindowDays - 1)))
            spans.append(DateSpan(s, cursor))
            cursor = s.adding(days: -1)
        }
        for (i, span) in spans.enumerated() {
            let batch = try await fetchWithRetry(request(for: span, today: today, isMostRecent: i == 0))
            ingest(batch, span: span, into: &h, today: today)
        }
        h.sync.status = .idle
        h.sync.lastSync = now()
        h.sync.lastError = nil
        return h
    }

    func request(for span: DateSpan, today: LocalDate, isMostRecent: Bool) -> ProviderFetch {
        let hourlyFrom = today.adding(days: -(Self.hourlyWindowDays - 1))
        return ProviderFetch(
            span: span,
            metrics: HealthMetric.dailyMetrics,
            includeHourlySteps: span.end >= hourlyFrom,
            includeSleep: true,
            includeBody: true,
            includeWorkouts: true,
            includeSources: isMostRecent
        )
    }

    func ingest(_ batch: ProviderBatch, span: DateSpan, into h: inout HealthHistory, today: LocalDate) {
        for metric in HealthMetric.dailyMetrics {
            h.replaceDaily(metric, in: span, with: batch.daily[metric] ?? [])
        }
        if !batch.hourlySteps.isEmpty || span.end >= today.adding(days: -(Self.hourlyWindowDays - 1)) {
            let hourlySpan = DateSpan(max(span.start, today.adding(days: -(Self.hourlyWindowDays - 1))), span.end)
            h.replaceHourly(in: hourlySpan, with: batch.hourlySteps)
        }
        h.pruneHourly(keepingFrom: today.adding(days: -(Self.hourlyWindowDays - 1)))
        let interval = span.dateInterval(in: calendar)
        h.mergeSamples(batch.weights, into: \.weights, replacing: interval)
        h.mergeSamples(batch.bodyFat, into: \.bodyFat, replacing: interval)
        // Daily means of point readings, so weight works with the same series tools as steps.
        for (metric, samples) in [(HealthMetric.weight, h.weights), (.bodyFat, h.bodyFat)] {
            var byDay: [LocalDate: [Double]] = [:]
            for s in samples where interval.contains(s.start) {
                byDay[LocalDate(s.start, calendar: calendar), default: []].append(s.value)
            }
            h.replaceDaily(metric, in: span, with: byDay.map { date, vals in
                DailyAggregate(date: date, metric: metric, value: vals.reduce(0, +) / Double(vals.count),
                               min: vals.min(), max: vals.max(), sampleCount: vals.count)
            })
        }
        h.replaceSleep(in: span, with: SleepAssembler.nights(from: batch.sleepSegments, calendar: calendar))
        h.mergeWorkouts(batch.workouts, replacing: interval)
        if !batch.sources.isEmpty { h.sources = batch.sources }
        h.sourceRecency.merge(batch.sourceRecency) { _, new in new }
        h.unsupportedMetrics = batch.unsupported
    }

    func fetchWithRetry(_ request: ProviderFetch) async throws -> ProviderBatch {
        var attempt = 0
        while true {
            do {
                return try await provider.fetch(request, calendar: calendar)
            } catch {
                guard attempt < retryDelays.count else { throw error }
                try? await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                attempt += 1
            }
        }
    }

    static func monthYear(_ d: LocalDate) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[d.month - 1]) \(d.year)"
    }
}
