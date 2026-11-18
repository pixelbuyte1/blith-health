import Foundation

// GPS walk tracking: the pure part. The app feeds raw Core Location fixes, pause/resume events,
// barometer readings and heart rate samples into these types; everything that decides what
// counts (which fixes, which distance, which time) lives here so it is tested on Linux.

/// One location fix as Core Location delivered it. Nothing is dropped when recording; the
/// processor decides what counts, so a walk can be reprocessed if the rules improve.
public struct TrackPoint: Codable, Hashable, Sendable {
    public var time: Date
    public var latitude: Double
    public var longitude: Double
    /// Metres; negative means invalid (Core Location's convention).
    public var horizontalAccuracy: Double
    public var altitude: Double?

    public init(time: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double, altitude: Double? = nil) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
    }
}

public enum WalkEventKind: String, Codable, Sendable {
    case pause, resume
}

/// A pause or resume the person tapped.
public struct WalkEvent: Codable, Hashable, Sendable {
    public var kind: WalkEventKind
    public var time: Date

    public init(_ kind: WalkEventKind, at time: Date) {
        self.kind = kind
        self.time = time
    }
}

/// Where a walk number came from. Every number on the walk screens shows one of these.
public enum WalkSource: String, Codable, Sendable {
    case gps = "GPS"
    case iPhone = "iPhone"
    case barometer = "Barometer"
    case watch = "Apple Watch"
    case health = "Apple Health"
    case estimated = "Estimated"
}

public enum Geo {
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres.
    public static func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}

/// The rules for which fixes count. Tuned for walking and hiking.
public struct TrackRules: Sendable {
    /// Fixes less accurate than this (metres) are ignored.
    public var maxAccuracy: Double = 25
    /// A jump faster than this (m/s, about 18 km/h) between fixes is a GPS glitch, not a walk.
    public var maxSpeed: Double = 5
    /// No good fix for this long (seconds) while walking is a GPS gap: the timer keeps
    /// running, but the gap is not drawn and its distance is not counted.
    public var gapSeconds: TimeInterval = 30
    /// Movement smaller than this from the last counted point is GPS jitter, not walking.
    public var minStep: Double = 3

    public init() {}
}

/// A walk's fixes after filtering: drawable segments, the GPS gaps between them, and the
/// distance that counts.
public struct ProcessedTrack: Sendable, Equatable {
    /// Smoothed good fixes, split wherever GPS dropped or the walk was paused. Draw each
    /// segment on its own; never join them.
    public var segments: [[TrackPoint]]
    /// Stretches with no usable GPS while the walk was running (not paused).
    public var gaps: [DateInterval]
    /// Metres, counted only along good fixes inside segments.
    public var distance: Double
    /// Fixes ignored for poor accuracy or impossible speed.
    public var rejected: Int

    public var gapSeconds: TimeInterval { gaps.reduce(0) { $0 + $1.duration } }

    public init(segments: [[TrackPoint]], gaps: [DateInterval], distance: Double, rejected: Int) {
        self.segments = segments
        self.gaps = gaps
        self.distance = distance
        self.rejected = rejected
    }

    public static let empty = ProcessedTrack(segments: [], gaps: [], distance: 0, rejected: 0)
}

public enum TrackProcessor {
    public static func process(_ raw: [TrackPoint], pauses: [DateInterval] = [], rules: TrackRules = TrackRules()) -> ProcessedTrack {
        let sorted = raw.sorted { $0.time < $1.time }
        var segments: [[TrackPoint]] = []
        var gaps: [DateInterval] = []
        var rejected = 0
        var current: [TrackPoint] = []

        func close() {
            if !current.isEmpty { segments.append(current) }
            current = []
        }

        for p in sorted {
            if pauses.contains(where: { $0.contains(p.time) }) { continue }
            guard p.horizontalAccuracy >= 0, p.horizontalAccuracy <= rules.maxAccuracy else {
                rejected += 1
                continue
            }
            if let last = current.last {
                let dt = p.time.timeIntervalSince(last.time)
                let pausedBetween = pauses.contains { $0.end > last.time && $0.start < p.time }
                if pausedBetween {
                    close()
                } else if dt > rules.gapSeconds {
                    gaps.append(DateInterval(start: last.time, end: p.time))
                    close()
                } else if dt > 0, Geo.distance(last, p) / dt > rules.maxSpeed {
                    rejected += 1
                    continue
                }
            }
            current.append(p)
        }
        close()

        let smoothed = segments.map(smooth)
        let distance = smoothed.reduce(0) { $0 + segmentDistance($1, minStep: rules.minStep) }
        return ProcessedTrack(segments: smoothed, gaps: gaps, distance: distance, rejected: rejected)
    }

    /// A light 1-2-1 weighted average of neighbouring fixes; the first and last stay put.
    static func smooth(_ points: [TrackPoint]) -> [TrackPoint] {
        guard points.count > 2 else { return points }
        var out = points
        for i in 1..<(points.count - 1) {
            out[i].latitude = (points[i - 1].latitude + 2 * points[i].latitude + points[i + 1].latitude) / 4
            out[i].longitude = (points[i - 1].longitude + 2 * points[i].longitude + points[i + 1].longitude) / 4
        }
        return out
    }

    /// Distance along a segment, ignoring jitter: a fix only adds distance once it is at least
    /// `minStep` from the last fix that did.
    static func segmentDistance(_ points: [TrackPoint], minStep: Double) -> Double {
        guard var anchor = points.first else { return 0 }
        var total = 0.0
        for p in points.dropFirst() {
            let d = Geo.distance(anchor, p)
            if d >= minStep {
                total += d
                anchor = p
            }
        }
        return total
    }
}

// MARK: Time

public enum WalkClock {
    /// Pause intervals from the tapped events. A pause with no resume runs to `end`.
    public static func pauses(_ events: [WalkEvent], end: Date) -> [DateInterval] {
        var out: [DateInterval] = []
        var pausedAt: Date?
        for e in events.sorted(by: { $0.time < $1.time }) {
            switch e.kind {
            case .pause:
                if pausedAt == nil { pausedAt = e.time }
            case .resume:
                if let p = pausedAt, e.time > p { out.append(DateInterval(start: p, end: e.time)) }
                pausedAt = nil
            }
        }
        if let p = pausedAt, end > p { out.append(DateInterval(start: p, end: end)) }
        return out
    }

    /// Elapsed time minus paused time. GPS gaps still count: the person was walking.
    public static func movingTime(start: Date, end: Date, pauses: [DateInterval]) -> TimeInterval {
        guard end > start else { return 0 }
        let paused = pauses.reduce(0.0) { total, p in
            let s = max(p.start, start), e = min(p.end, end)
            return total + max(0, e.timeIntervalSince(s))
        }
        return max(0, end.timeIntervalSince(start) - paused)
    }

    /// The walk's running intervals (start to end with pauses cut out).
    public static func movingIntervals(start: Date, end: Date, pauses: [DateInterval]) -> [DateInterval] {
        guard end > start else { return [] }
        var out: [DateInterval] = []
        var cursor = start
        for p in pauses.sorted(by: { $0.start < $1.start }) where p.end > cursor && p.start < end {
            if p.start > cursor { out.append(DateInterval(start: cursor, end: p.start)) }
            cursor = max(cursor, p.end)
        }
        if end > cursor { out.append(DateInterval(start: cursor, end: end)) }
        return out
    }
}

// MARK: Pace and splits

public enum WalkPace {
    /// Seconds per km (metric) or per mile (imperial).
    public static func unitLength(_ units: UnitSystem) -> Double { units == .metric ? 1000 : 1609.344 }

    /// Average pace over the whole walk, or nil before there's enough distance to mean anything.
    public static func average(distance: Double, movingTime: TimeInterval, units: UnitSystem) -> Double? {
        guard distance >= 50, movingTime > 0 else { return nil }
        return movingTime / distance * unitLength(units)
    }

    /// Pace over the last `window` seconds of the newest segment. Nil when GPS is stale or the
    /// person is standing still, so the screen says "Not available" instead of a made-up pace.
    public static func current(_ track: ProcessedTrack, now: Date, units: UnitSystem, window: TimeInterval = 60) -> Double? {
        guard let segment = track.segments.last, let last = segment.last, now.timeIntervalSince(last.time) <= 20 else { return nil }
        let recent = segment.filter { last.time.timeIntervalSince($0.time) <= window }
        guard let first = recent.first else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        let distance = TrackProcessor.segmentDistance(recent, minStep: TrackRules().minStep)
        guard span >= 15, distance >= 10 else { return nil }
        return span / distance * unitLength(units)
    }

    /// "12′28″" for a pace in seconds.
    public static func format(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 6 * 3600 else { return "–" }
        let total = Int(seconds.rounded())
        return "\(total / 60)′\(String(format: "%02d", total % 60))″"
    }

    /// "26:41" or "1:05:09".
    public static func clock(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))" : "\(m):\(String(format: "%02d", s))"
    }
}

public struct WalkSplit: Sendable, Equatable, Identifiable {
    public var index: Int
    /// Metres covered in this split (a full unit, except the last).
    public var distance: Double
    /// Moving seconds spent on it.
    public var duration: TimeInterval
    /// True when a GPS gap fell inside it, so its pace is less certain.
    public var includesGap: Bool
    public var id: Int { index }

    /// Seconds per unit length.
    public func pace(_ units: UnitSystem) -> Double? {
        guard distance >= 50 else { return nil }
        return duration / distance * WalkPace.unitLength(units)
    }
}

public enum WalkSplits {
    /// Per-km (or per-mile) splits from the counted distance. Time is moving time, so pauses
    /// don't slow a split; a split that spans a GPS gap is flagged.
    public static func compute(_ track: ProcessedTrack, start: Date, pauses: [DateInterval], units: UnitSystem) -> [WalkSplit] {
        let unit = WalkPace.unitLength(units)
        let rules = TrackRules()
        var marks: [(distance: Double, time: TimeInterval)] = []
        var total = 0.0
        for segment in track.segments {
            guard var anchor = segment.first else { continue }
            marks.append((total, WalkClock.movingTime(start: start, end: anchor.time, pauses: pauses)))
            for p in segment.dropFirst() {
                let d = Geo.distance(anchor, p)
                if d >= rules.minStep {
                    total += d
                    anchor = p
                    marks.append((total, WalkClock.movingTime(start: start, end: p.time, pauses: pauses)))
                }
            }
        }
        guard total > 0, let lastMark = marks.last else { return [] }

        func time(at distance: Double) -> TimeInterval {
            guard let i = marks.firstIndex(where: { $0.distance >= distance }) else { return lastMark.time }
            guard i > 0 else { return marks[0].time }
            let a = marks[i - 1], b = marks[i]
            let f = b.distance > a.distance ? (distance - a.distance) / (b.distance - a.distance) : 0
            return a.time + (b.time - a.time) * f
        }

        func moving(_ date: Date) -> TimeInterval { WalkClock.movingTime(start: start, end: date, pauses: pauses) }
        let gapWindows = track.gaps.map { (moving($0.start), moving($0.end)) }

        var splits: [WalkSplit] = []
        var from = 0.0
        var fromTime = time(at: 0)
        var index = 1
        while from < total {
            let to = min(total, from + unit)
            let toTime = time(at: to)
            let gap = gapWindows.contains { $0.1 > fromTime && $0.0 < toTime }
            if to - from >= 1 {
                splits.append(WalkSplit(index: index, distance: to - from, duration: max(0, toTime - fromTime), includesGap: gap))
            }
            from = to
            fromTime = toTime
            index += 1
        }
        return splits
    }
}

extension WalkSplits {
    /// The fix where each full km (or mile) was reached, for the map's markers.
    public static func markers(_ track: ProcessedTrack, units: UnitSystem) -> [TrackPoint] {
        let unit = WalkPace.unitLength(units)
        let minStep = TrackRules().minStep
        var total = 0.0
        var next = unit
        var out: [TrackPoint] = []
        for segment in track.segments {
            guard var anchor = segment.first else { continue }
            for p in segment.dropFirst() {
                let d = Geo.distance(anchor, p)
                guard d >= minStep else { continue }
                total += d
                anchor = p
                while total >= next {
                    out.append(p)
                    next += unit
                }
            }
        }
        return out
    }
}

// MARK: Climb and heart rate

/// Climb from the barometer's relative altitude, with a small dead band so pressure noise
/// standing still doesn't add up to a hill.
public struct ClimbCounter: Codable, Sendable, Equatable {
    public private(set) var gain: Double = 0
    private var reference: Double?
    public var threshold: Double

    public init(threshold: Double = 1.0) { self.threshold = threshold }

    public mutating func add(_ relativeAltitude: Double) {
        guard let ref = reference else {
            reference = relativeAltitude
            return
        }
        if relativeAltitude - ref >= threshold {
            gain += relativeAltitude - ref
            reference = relativeAltitude
        } else if ref - relativeAltitude >= threshold {
            reference = relativeAltitude
        }
    }

    /// After a pause the barometer keeps reading; start from the new altitude, not the old one.
    public mutating func resetReference() { reference = nil }
}

public struct WalkHeartSummary: Sendable, Equatable {
    public var average: Double
    public var maximum: Double
    public var count: Int
}

public enum WalkHeart {
    /// Average and peak over the moving part of the walk. Nil with too few readings to mean anything.
    public static func summary(_ samples: [HeartSample], within intervals: [DateInterval]) -> WalkHeartSummary? {
        let inside = samples.filter { s in intervals.contains { $0.contains(s.date) } && s.bpm >= 30 && s.bpm <= 230 }
        guard inside.count >= 3 else { return nil }
        let bpm = inside.map(\.bpm)
        return WalkHeartSummary(average: bpm.reduce(0, +) / Double(bpm.count), maximum: bpm.max() ?? 0, count: bpm.count)
    }
}
