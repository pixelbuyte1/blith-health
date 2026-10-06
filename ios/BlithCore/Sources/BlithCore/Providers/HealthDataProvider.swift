import Foundation

/// What the sync engine asks a provider for. Spans are local days; the provider buckets
/// cumulative metrics by local day (and by hour for steps when `includeHourlySteps`).
public struct ProviderFetch: Sendable, Hashable {
    public var span: DateSpan
    public var metrics: [HealthMetric]
    public var includeHourlySteps: Bool
    public var includeSleep: Bool
    public var includeBody: Bool
    public var includeWorkouts: Bool
    /// Ask for a per-source breakdown of cumulative metrics over the span.
    public var includeSources: Bool

    public init(span: DateSpan, metrics: [HealthMetric], includeHourlySteps: Bool, includeSleep: Bool,
                includeBody: Bool, includeWorkouts: Bool, includeSources: Bool) {
        self.span = span
        self.metrics = metrics
        self.includeHourlySteps = includeHourlySteps
        self.includeSleep = includeSleep
        self.includeBody = includeBody
        self.includeWorkouts = includeWorkouts
        self.includeSources = includeSources
    }

    /// Sleep samples are attributed to the day the user woke up; nights start the previous evening.
    public func sleepInterval(calendar: Calendar) -> DateInterval {
        let start = span.start.adding(days: -1).startDate(in: calendar).addingTimeInterval(SleepAssembler.dayBoundaryHour * 3600)
        let end = span.end.startDate(in: calendar).addingTimeInterval(SleepAssembler.dayBoundaryHour * 3600)
        return DateInterval(start: start, end: max(start, end))
    }
}

/// Normalized output of one provider fetch.
public struct ProviderBatch: Sendable {
    public var daily: [HealthMetric: [DailyAggregate]] = [:]
    public var hourlySteps: [LocalDate: HourlyBuckets] = [:]
    public var weights: [HealthSample] = []
    public var bodyFat: [HealthSample] = []
    public var sleepSegments: [SleepSegment] = []
    public var workouts: [WorkoutRecord] = []
    public var sources: [HealthMetric: [SourceShare]] = [:]
    /// Companion apps seen in the source window and their latest sample per metric.
    public var sourceRecency: [String: SourceRecency] = [:]
    /// Metrics this provider cannot supply on this device.
    public var unsupported: Set<HealthMetric> = []

    public init() {}
}

public enum HealthProviderError: Error, LocalizedError, Sendable {
    case unavailable
    case authorizationFailed(String)
    case queryFailed(String)
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Health data isn't available on this device."
        case .authorizationFailed(let m): "Couldn't request access: \(m)"
        case .queryFailed(let m): "Couldn't read health data: \(m)"
        case .notConfigured(let m): m
        }
    }
}

/// A source of health data. HealthKit, Huawei and the demo generator all implement this and
/// emit the same normalized types, so nothing above the provider knows where data came from
/// except through `SourceRef` provenance.
public protocol HealthDataProvider: Sendable {
    var kind: ProviderKind { get }
    var isAvailable: Bool { get }
    /// Request read access. Completing without error does NOT mean access was granted.
    func requestAuthorization(for categories: Set<HealthCategory>) async throws
    /// Oldest step sample, used to size the initial import.
    func earliestDataDate() async -> Date?
    func fetch(_ request: ProviderFetch, calendar: Calendar) async throws -> ProviderBatch
}
