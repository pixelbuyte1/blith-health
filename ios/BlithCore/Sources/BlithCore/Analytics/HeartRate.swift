import Foundation

/// One heart rate reading (beats per minute) and when it was recorded.
public struct HeartSample: Codable, Hashable, Sendable, Identifiable {
    public var date: Date
    public var bpm: Double
    public var id: Date { date }

    public init(date: Date, bpm: Double) {
        self.date = date
        self.bpm = bpm
    }
}

/// How hard the heart is working relative to the person's own resting rate. Zones are a way to
/// describe intensity, not a health assessment.
public enum HeartZone: Int, CaseIterable, Sendable, Comparable {
    case resting, warm, elevated, hard, peak

    public static func < (a: HeartZone, b: HeartZone) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .resting: "Resting"
        case .warm: "Warm"
        case .elevated: "Elevated"
        case .hard: "Hard"
        case .peak: "Peak"
        }
    }

    /// Estimated maximum heart rate when the person's age isn't known.
    public static let defaultMax = 190.0

    /// 0 … 1: how far between resting and maximum the rate is.
    public static func intensity(bpm: Double, resting: Double?, maxHR: Double = defaultMax) -> Double {
        let rest = min(90, max(40, resting ?? 62))
        let top = max(maxHR, rest + 40)
        return min(1, max(0, (bpm - rest) / (top - rest)))
    }

    public static func zone(bpm: Double, resting: Double?, maxHR: Double = defaultMax) -> HeartZone {
        switch intensity(bpm: bpm, resting: resting, maxHR: maxHR) {
        case ..<0.20: .resting
        case ..<0.40: .warm
        case ..<0.60: .elevated
        case ..<0.80: .hard
        default: .peak
        }
    }
}

/// The live heart rate card's state, derived from recent samples.
public struct LiveHeartSummary: Sendable, Equatable {
    public enum Freshness: Sendable { case live, recent, stale, none }

    /// A reading under 90 seconds old counts as live, under 30 minutes as recent.
    public static let liveWindow: TimeInterval = 90
    public static let recentWindow: TimeInterval = 30 * 60

    public var latest: HeartSample?
    public var freshness: Freshness
    public var zone: HeartZone
    public var intensity: Double
    public var resting: Double?
    public var minToday: Double?
    public var maxToday: Double?
    /// Readings from the last hour, oldest first.
    public var lastHour: [HeartSample]

    public var bpm: Double? { latest?.bpm }
    public var aboveResting: Double? { latest.flatMap { l in resting.map { l.bpm - $0 } } }

    public func age(now: Date) -> TimeInterval? { latest.map { max(0, now.timeIntervalSince($0.date)) } }

    public static func make(samples: [HeartSample], now: Date, resting: Double?, calendar: Calendar = .current,
                            maxHR: Double = HeartZone.defaultMax) -> LiveHeartSummary {
        let valid = samples.filter { $0.bpm >= 20 && $0.bpm <= 250 && $0.date <= now.addingTimeInterval(60) }.sorted { $0.date < $1.date }
        guard let latest = valid.last else {
            return LiveHeartSummary(latest: nil, freshness: .none, zone: .resting, intensity: 0, resting: resting,
                                    minToday: nil, maxToday: nil, lastHour: [])
        }
        let age = max(0, now.timeIntervalSince(latest.date))
        let freshness: Freshness = age <= liveWindow ? .live : (age <= recentWindow ? .recent : .stale)
        let today = valid.filter { $0.date >= calendar.startOfDay(for: now) }.map(\.bpm)
        return LiveHeartSummary(
            latest: latest, freshness: freshness,
            zone: HeartZone.zone(bpm: latest.bpm, resting: resting, maxHR: maxHR),
            intensity: HeartZone.intensity(bpm: latest.bpm, resting: resting, maxHR: maxHR),
            resting: resting, minToday: today.min(), maxToday: today.max(),
            lastHour: valid.filter { $0.date >= now.addingTimeInterval(-3600) })
    }
}

/// The shape of one heartbeat, in beat phase (0 … 1). Kept here so it can be tested; the app
/// draws the heart and the ECG trace from these functions.
public enum HeartWaveform {
    /// Phase at which the ECG's R spike and the heart's first thump ("lub") land together.
    public static let lubPhase = 0.31
    public static let dubPhase = 0.56

    static func bump(_ x: Double, _ center: Double, _ width: Double) -> Double {
        var d = x - center
        d -= d.rounded() // wrap to -0.5 … 0.5 so the pattern is periodic
        return exp(-(d * d) / (2 * width * width))
    }

    /// 0 … ~1 thump strength: a strong "lub" and a softer "dub" once per beat.
    public static func thump(phase: Double) -> Double {
        min(1, bump(phase, lubPhase, 0.035) + 0.62 * bump(phase, dubPhase, 0.04))
    }

    /// Normalised ECG voltage: P wave, Q dip, R spike, S dip, T wave.
    public static func ecg(phase: Double) -> Double {
        0.10 * bump(phase, 0.14, 0.03)
            - 0.10 * bump(phase, 0.275, 0.010)
            + 1.00 * bump(phase, lubPhase, 0.009)
            - 0.58 * bump(phase, 0.335, 0.010)
            + 0.18 * bump(phase, 0.56, 0.05)
    }
}
