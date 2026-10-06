import Foundation

/// A phone app that copies a wearable's data into Apple Health (today: Huawei Health).
///
/// These apps only write to Apple Health while they run, so their data can lag by hours or days.
/// Blith records when each one last delivered each metric, and says so plainly instead of
/// letting a quiet day look like an inactive one.
public enum CompanionApp: String, Codable, Sendable, CaseIterable {
    case huawei

    public var displayName: String {
        switch self {
        case .huawei: "Huawei Health"
        }
    }

    public static func matching(_ source: SourceRef) -> CompanionApp? {
        source.deviceFamily == "huawei" ? .huawei : nil
    }

    /// Metrics a watch paired through this app records and can hand to Apple Health.
    public var watchMetrics: [HealthMetric] {
        switch self {
        case .huawei: [.steps, .distanceWalkingRunning, .activeEnergy, .restingHeartRate, .hrv, .oxygenSaturation, .sleepDuration]
        }
    }

    /// How to turn the Apple Health link on, in the companion app's own words.
    public var setupSteps: [String] {
        switch self {
        case .huawei: [
            "Open Huawei Health and sign in with the HUAWEI ID your watch uses.",
            "Go to Me, then Privacy management (or Settings), then Data sharing and authorization.",
            "Choose Health (Apple Health) and turn on every data type.",
            "Leave Huawei Health running in the background. It only writes to Apple Health while it runs.",
        ]
        }
    }
}

/// The most recent sample a companion app wrote to Apple Health, per metric.
public struct SourceRecency: Codable, Hashable, Sendable {
    public var app: CompanionApp
    public var latest: [HealthMetric: Date]
    public var checkedAt: Date

    public init(app: CompanionApp, latest: [HealthMetric: Date], checkedAt: Date) {
        self.app = app
        self.latest = latest
        self.checkedAt = checkedAt
    }

    public var lastSeen: Date? { latest.values.max() }
}

public struct CompanionSyncStatus: Sendable, Equatable {
    public enum Freshness: Sendable, Equatable {
        /// Wrote within `CompanionSync.behindAfter`.
        case current
        /// Hasn't written for a while; opening the app usually catches it up.
        case behind
        /// Nothing for days: the link is probably off or the app was closed.
        case stopped
    }

    public struct Arriving: Sendable, Equatable, Identifiable {
        public var metric: HealthMetric
        public var latest: Date
        public var id: HealthMetric { metric }
    }

    public var app: CompanionApp
    public var lastSync: Date
    public var freshness: Freshness
    /// Metrics the app is delivering, most recent first.
    public var arriving: [Arriving]
    /// Watch metrics nothing has delivered in the last `CompanionSync.missingWindowDays` days.
    public var missing: [HealthMetric]
}

public enum CompanionSync {
    public static let behindAfter: TimeInterval = 12 * 3600
    public static let stoppedAfter: TimeInterval = 3 * 86_400
    public static let missingWindowDays = 7

    public static func status(_ app: CompanionApp, history: HealthHistory, now: Date, calendar: Calendar) -> CompanionSyncStatus? {
        guard let rec = history.sourceRecency[app.rawValue], let last = rec.lastSeen else { return nil }
        let age = now.timeIntervalSince(last)
        let freshness: CompanionSyncStatus.Freshness = age >= stoppedAfter ? .stopped : age >= behindAfter ? .behind : .current
        let arriving = rec.latest
            .map { CompanionSyncStatus.Arriving(metric: $0.key, latest: $0.value) }
            .sorted { $0.latest != $1.latest ? $0.latest > $1.latest : $0.metric.rawValue < $1.metric.rawValue }
        let today = LocalDate(now, calendar: calendar)
        let missing = app.watchMetrics.filter { metric in
            guard rec.latest[metric] == nil else { return false }
            return !(0..<missingWindowDays).contains { history.value(metric, on: today.adding(days: -$0)) != nil }
        }
        return CompanionSyncStatus(app: app, lastSync: last, freshness: freshness, arriving: arriving, missing: missing)
    }
}
