import Foundation

/// The small, self-contained summary the Home and Lock Screen widgets draw from.
///
/// The app writes one after every snapshot rebuild; the widget extension only reads it, so the
/// widgets never recompute anything and always agree with the Today screen.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    /// Start of the local day the numbers belong to; widgets stop showing them once it's over.
    public var dayStart: Date
    public var isSample: Bool

    public var readiness: Int?
    public var readinessBand: ScoreBand?
    public var calibrationDays: Int
    public var calibrationTarget: Int
    /// Readiness for the last seven days, oldest first; nil where there was no score.
    public var readinessWeek: [Int?]

    public var sleepScore: Int?
    public var asleep: TimeInterval?
    public var sleepNeed: TimeInterval?

    public var load: Double?
    public var loadUsualLow: Double?
    public var loadUsualHigh: Double?
    public var loadMaximum: Double

    public var steps: Double?
    public var usualStepsByNow: Double?
    public var usualStepsDay: Double?

    public var hrv: Double?
    public var restingHeartRate: Double?

    /// Set when a companion app (Huawei Health) has fallen behind.
    public var companionName: String?
    public var companionLastSync: Date?

    public init(version: Int = WidgetSnapshot.currentVersion, generatedAt: Date, dayStart: Date, isSample: Bool,
                readiness: Int?, readinessBand: ScoreBand?, calibrationDays: Int, calibrationTarget: Int,
                readinessWeek: [Int?], sleepScore: Int?, asleep: TimeInterval?, sleepNeed: TimeInterval?,
                load: Double?, loadUsualLow: Double?, loadUsualHigh: Double?, loadMaximum: Double,
                steps: Double?, usualStepsByNow: Double?, usualStepsDay: Double?,
                hrv: Double?, restingHeartRate: Double?, companionName: String?, companionLastSync: Date?) {
        self.version = version
        self.generatedAt = generatedAt
        self.dayStart = dayStart
        self.isSample = isSample
        self.readiness = readiness
        self.readinessBand = readinessBand
        self.calibrationDays = calibrationDays
        self.calibrationTarget = calibrationTarget
        self.readinessWeek = readinessWeek
        self.sleepScore = sleepScore
        self.asleep = asleep
        self.sleepNeed = sleepNeed
        self.load = load
        self.loadUsualLow = loadUsualLow
        self.loadUsualHigh = loadUsualHigh
        self.loadMaximum = loadMaximum
        self.steps = steps
        self.usualStepsByNow = usualStepsByNow
        self.usualStepsDay = usualStepsDay
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.companionName = companionName
        self.companionLastSync = companionLastSync
    }

    /// Builds the widget summary from the same snapshot the Today screen shows.
    public init(snapshot s: HealthSnapshot, companion: CompanionSyncStatus?, isSample: Bool) {
        let ctx = s.ctx
        let byDate = Dictionary(s.scoreHistory.map { ($0.date, $0.readiness) }, uniquingKeysWith: { a, _ in a })
        let week: [Int?] = (0..<7).reversed().map { ago in
            let d = ctx.today.adding(days: -ago)
            return ago == 0 ? s.readiness.score : (byDate[d] ?? nil)
        }
        self.init(
            generatedAt: ctx.now,
            dayStart: ctx.today.startDate(in: ctx.calendar),
            isSample: isSample,
            readiness: s.readiness.score,
            readinessBand: s.readiness.band,
            calibrationDays: s.readiness.calibrationDays,
            calibrationTarget: ScoreEngine.calibrationDays,
            readinessWeek: week,
            sleepScore: s.sleepScore?.score,
            asleep: s.sleepScore?.asleep,
            sleepNeed: s.sleepScore?.need,
            load: s.load?.value,
            loadUsualLow: s.load?.usualRange?.lowerBound,
            loadUsualHigh: s.load?.usualRange?.upperBound,
            loadMaximum: LoadResult.maximum,
            steps: s.todaySteps,
            usualStepsByNow: s.pace?.usualByNow,
            usualStepsDay: s.pace?.usualFullDay,
            hrv: ctx.history.value(.hrv, on: ctx.today),
            restingHeartRate: ctx.history.value(.restingHeartRate, on: ctx.today),
            companionName: companion.flatMap { $0.freshness == .current ? nil : $0.app.displayName },
            companionLastSync: companion.flatMap { $0.freshness == .current ? nil : $0.lastSync })
    }

    /// True while `date` falls on the day these numbers describe.
    public func isCurrent(at date: Date, calendar: Calendar) -> Bool {
        calendar.isDate(date, inSameDayAs: dayStart)
    }

    /// Steps compared with a usual day at the same hour (0.12 = 12% ahead).
    public var paceChange: Double? {
        guard let steps, let usual = usualStepsByNow, usual > 0 else { return nil }
        return steps / usual - 1
    }

    /// Placeholder and gallery preview.
    public static func preview(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: now, dayStart: calendar.startOfDay(for: now), isSample: true,
                       readiness: 74, readinessBand: .high, calibrationDays: 14, calibrationTarget: 14,
                       readinessWeek: [61, 58, 70, 66, 52, 69, 74], sleepScore: 86, asleep: 7.4 * 3600, sleepNeed: 7.6 * 3600,
                       load: 5.4, loadUsualLow: 4.1, loadUsualHigh: 5.9, loadMaximum: LoadResult.maximum,
                       steps: 6_420, usualStepsByNow: 5_710, usualStepsDay: 8_900,
                       hrv: 48, restingHeartRate: 57, companionName: nil, companionLastSync: nil)
    }
}
