import Foundation

/// Provider-independent metric identifiers. Every provider (HealthKit, Huawei, demo) maps its
/// native types onto these, and every value is stored in `canonicalUnit`.
public enum HealthMetric: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    // Movement
    case steps
    case distanceWalkingRunning
    case activeEnergy
    case exerciseMinutes
    case flightsClimbed
    // Mobility (gait)
    case walkingSpeed
    case walkingStepLength
    case walkingAsymmetry
    case walkingDoubleSupport
    // Body
    case weight
    case bodyFat
    // Heart
    case restingHeartRate
    case walkingHeartRate
    /// Every heart rate reading in a day: the daily mean, with the day's lowest and highest in min/max.
    case heartRate
    case hrv
    // Vitals
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case vo2Max
    // Sleep (derived from sleep stage segments)
    case sleepDuration

    public enum Aggregation: Sendable { case cumulative, discrete }

    /// Cumulative metrics are summed per day; discrete metrics are averaged.
    public var aggregation: Aggregation {
        switch self {
        case .steps, .distanceWalkingRunning, .activeEnergy, .exerciseMinutes, .flightsClimbed, .sleepDuration:
            .cumulative
        default:
            .discrete
        }
    }

    public var category: HealthCategory {
        switch self {
        case .steps, .distanceWalkingRunning, .activeEnergy, .exerciseMinutes, .flightsClimbed,
             .walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport:
            .movement
        case .weight, .bodyFat: .body
        case .restingHeartRate, .walkingHeartRate, .heartRate, .hrv, .respiratoryRate, .oxygenSaturation, .wristTemperature, .vo2Max: .heart
        case .sleepDuration: .sleep
        }
    }

    /// Unit every stored value uses.
    public var canonicalUnit: String {
        switch self {
        case .steps, .flightsClimbed: "count"
        case .distanceWalkingRunning, .walkingStepLength: "m"
        case .activeEnergy: "kcal"
        case .exerciseMinutes: "min"
        case .walkingSpeed: "m/s"
        case .walkingAsymmetry, .walkingDoubleSupport, .bodyFat: "fraction"
        case .weight: "kg"
        case .restingHeartRate, .walkingHeartRate, .heartRate: "bpm"
        case .hrv: "ms"
        case .respiratoryRate: "breaths/min"
        case .oxygenSaturation: "fraction"
        case .wristTemperature: "degC"
        case .vo2Max: "ml/kg/min"
        case .sleepDuration: "s"
        }
    }

    public var displayName: String {
        switch self {
        case .steps: "Steps"
        case .distanceWalkingRunning: "Walking + running distance"
        case .activeEnergy: "Active energy"
        case .exerciseMinutes: "Exercise minutes"
        case .flightsClimbed: "Flights climbed"
        case .walkingSpeed: "Walking speed"
        case .walkingStepLength: "Step length"
        case .walkingAsymmetry: "Walking asymmetry"
        case .walkingDoubleSupport: "Double support time"
        case .weight: "Weight"
        case .bodyFat: "Body fat"
        case .restingHeartRate: "Resting heart rate"
        case .walkingHeartRate: "Walking heart rate"
        case .heartRate: "Heart rate"
        case .hrv: "Heart rate variability"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Blood oxygen"
        case .wristTemperature: "Wrist temperature"
        case .vo2Max: "Cardio fitness (VO₂ max)"
        case .sleepDuration: "Sleep"
        }
    }

    /// How long without a new value before a metric is considered stale.
    public var staleAfterDays: Int {
        switch self {
        case .weight, .bodyFat: 45
        case .walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport: 21
        case .vo2Max: 90
        default: 7
        }
    }

    /// Metrics that are stored as one aggregate per day.
    public static let dailyMetrics: [HealthMetric] = [
        .steps, .distanceWalkingRunning, .activeEnergy, .exerciseMinutes, .flightsClimbed,
        .walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport,
        .restingHeartRate, .walkingHeartRate, .heartRate, .hrv,
        .respiratoryRate, .oxygenSaturation, .wristTemperature, .vo2Max,
    ]
}

/// Permission groups shown during onboarding. Users choose which to connect.
public enum HealthCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case movement, sleep, body, heart

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .movement: "Movement"
        case .sleep: "Sleep"
        case .body: "Body"
        case .heart: "Heart and vitals"
        }
    }

    public var detail: String {
        switch self {
        case .movement: "Steps, distance, walking speed and workouts"
        case .sleep: "Sleep duration and stages"
        case .body: "Weight and body fat"
        case .heart: "Heart rate, HRV, respiratory rate, blood oxygen, wrist temperature and cardio fitness"
        }
    }

    public var isRecommended: Bool { self == .movement }

    public var metrics: [HealthMetric] { HealthMetric.allCases.filter { $0.category == self } }
}

/// Where a value came from, independent of provider.
public enum ProviderKind: String, Codable, Sendable {
    case appleHealth
    case huawei
    case demo
    case manual

    public var displayName: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .huawei: "Huawei Health"
        case .demo: "Sample data"
        case .manual: "Manual entry"
        }
    }
}

/// Provenance for a sample or aggregate.
public struct SourceRef: Codable, Hashable, Sendable {
    public var provider: ProviderKind
    /// Human name, e.g. "Zen's Apple Watch", "iPhone", "Huawei Health".
    public var name: String
    /// Stable identifier such as a bundle identifier.
    public var identifier: String
    /// Recording device model if known ("Watch", "iPhone", "HUAWEI WATCH GT").
    public var device: String?

    public init(provider: ProviderKind, name: String, identifier: String, device: String? = nil) {
        self.provider = provider
        self.name = name
        self.identifier = identifier
        self.device = device
    }

    /// Sources that represent the same physical recording, even when they reach us through
    /// different providers (a Huawei watch syncing into Apple Health, and the Huawei cloud).
    public var deviceFamily: String {
        let lowered = (identifier + " " + name + " " + (device ?? "")).lowercased()
        if lowered.contains("huawei") { return "huawei" }
        if lowered.contains("watch") { return "apple-watch" }
        if lowered.contains("iphone") || lowered.contains("com.apple.health") { return "iphone" }
        return identifier.lowercased()
    }
}

/// One raw measurement with full provenance.
public struct HealthSample: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metric: HealthMetric
    /// Value in `metric.canonicalUnit`.
    public var value: Double
    public var start: Date
    public var end: Date
    public var source: SourceRef
    public var syncedAt: Date

    public init(id: String, metric: HealthMetric, value: Double, start: Date, end: Date, source: SourceRef, syncedAt: Date) {
        self.id = id
        self.metric = metric
        self.value = value
        self.start = start
        self.end = end
        self.source = source
        self.syncedAt = syncedAt
    }
}

/// A source's share of a metric over a period ("Apple Watch: 71%").
public struct SourceShare: Codable, Hashable, Sendable, Identifiable {
    public var source: SourceRef
    public var value: Double
    public var id: String { source.provider.rawValue + ":" + source.identifier + ":" + source.name }

    public init(source: SourceRef, value: Double) {
        self.source = source
        self.value = value
    }
}

/// One metric's value for one local day.
public struct DailyAggregate: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var metric: HealthMetric
    /// Sum for cumulative metrics, mean for discrete metrics, canonical unit.
    public var value: Double
    public var min: Double?
    public var max: Double?
    public var sampleCount: Int

    public init(date: LocalDate, metric: HealthMetric, value: Double, min: Double? = nil, max: Double? = nil, sampleCount: Int = 1) {
        self.date = date
        self.metric = metric
        self.value = value
        self.min = min
        self.max = max
        self.sampleCount = sampleCount
    }
}

/// Step totals per hour of one local day (index 0 = midnight–1 AM).
public struct HourlyBuckets: Codable, Hashable, Sendable {
    public var values: [Double]

    public init(values: [Double] = Array(repeating: 0, count: 24)) {
        var v = values
        if v.count < 24 { v += Array(repeating: 0, count: 24 - v.count) }
        self.values = Array(v.prefix(24))
    }

    public var total: Double { values.reduce(0, +) }

    /// Cumulative total through the end of each hour.
    public var cumulative: [Double] {
        var running = 0.0
        return values.map { running += $0; return running }
    }

    /// Cumulative total at a fractional hour of the day (e.g. 14.5 = 2:30 PM), interpolating
    /// linearly inside the current hour.
    public func cumulative(atHour hour: Double) -> Double {
        let h = Swift.max(0, Swift.min(24, hour))
        let whole = Int(h)
        let before = values.prefix(whole).reduce(0, +)
        guard whole < 24 else { return before }
        return before + values[whole] * (h - Double(whole))
    }
}
