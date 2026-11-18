import Foundation

public enum WalkFeel: String, Codable, Sendable, CaseIterable {
    case easy, steady, hard

    public var title: String {
        switch self {
        case .easy: "Easy"
        case .steady: "Steady"
        case .hard: "Hard"
        }
    }
}

/// A walk recorded with GPS in Blith. Raw fixes are kept; distance, time and splits are always
/// derived by `TrackProcessor`, so the numbers and the map can never disagree.
public struct RecordedWalk: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String?
    public var start: Date
    /// When the walk was finished (or, for a walk still running, the last checkpoint).
    public var end: Date
    public var points: [TrackPoint]
    public var events: [WalkEvent]
    /// Steps from the iPhone's motion sensor over the moving intervals. Nil when unavailable.
    public var steps: Int?
    /// Metres climbed, from the barometer. Nil when the iPhone has no barometer data.
    public var climb: Double?
    /// Heart rate samples Apple Health received during the walk.
    public var heart: [HeartSample]
    /// Where the heart rate came from ("Apple Watch"), when there is any.
    public var heartSource: String?
    /// The HKWorkout this walk is stored as: Blith's own save, or the Watch's walk it was merged into.
    public var healthWorkoutID: String?
    /// True when the Watch had already recorded this walk and Blith kept that one instead of saving a second.
    public var mergedWithWatch: Bool
    public var feel: WalkFeel?
    public var note: String?
    /// Recorded in demo mode: real GPS, but never written to Apple Health.
    public var isDemo: Bool

    public init(id: String = UUID().uuidString, title: String? = nil, start: Date, end: Date, points: [TrackPoint] = [],
                events: [WalkEvent] = [], steps: Int? = nil, climb: Double? = nil, heart: [HeartSample] = [],
                heartSource: String? = nil, healthWorkoutID: String? = nil, mergedWithWatch: Bool = false,
                feel: WalkFeel? = nil, note: String? = nil, isDemo: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.points = points
        self.events = events
        self.steps = steps
        self.climb = climb
        self.heart = heart
        self.heartSource = heartSource
        self.healthWorkoutID = healthWorkoutID
        self.mergedWithWatch = mergedWithWatch
        self.feel = feel
        self.note = note
        self.isDemo = isDemo
    }

    public var pauses: [DateInterval] { WalkClock.pauses(events, end: end) }
    public var movingTime: TimeInterval { WalkClock.movingTime(start: start, end: end, pauses: pauses) }
    public var movingIntervals: [DateInterval] { WalkClock.movingIntervals(start: start, end: end, pauses: pauses) }
    public var track: ProcessedTrack { TrackProcessor.process(points, pauses: pauses) }

    /// "Walk" plus the time of day when no route name was given.
    public func displayTitle(calendar: Calendar = .current) -> String {
        if let title, !title.isEmpty { return title }
        let hour = calendar.component(.hour, from: start)
        switch hour {
        case 5..<12: return "Morning walk"
        case 12..<17: return "Afternoon walk"
        case 17..<22: return "Evening walk"
        default: return "Night walk"
        }
    }
}

// MARK: Counting once

public enum WalkMerge {
    /// Seconds two intervals share.
    public static func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
    }

    /// True when the two recordings are the same walk: they share at least half of the shorter one.
    public static func isSameWalk(_ a: DateInterval, _ b: DateInterval) -> Bool {
        let shorter = min(a.duration, b.duration)
        guard shorter > 0 else { return false }
        return overlap(a, b) >= shorter * 0.5
    }

    /// A walking workout from another app or device (usually the Watch) that already covers this
    /// walk. When there is one, Blith keeps it and saves nothing new, so steps, distance and
    /// energy are never counted twice.
    public static func existingWalk(for walk: DateInterval, in workouts: [WorkoutRecord], ownSourceID: String) -> WorkoutRecord? {
        workouts
            .filter { $0.isWalking && $0.source.identifier != ownSourceID && isSameWalk(walk, DateInterval(start: $0.start, end: max($0.start, $0.end))) }
            .max { overlap(walk, DateInterval(start: $0.start, end: max($0.start, $0.end))) < overlap(walk, DateInterval(start: $1.start, end: max($1.start, $1.end))) }
    }
}

/// One row of Walk history: a GPS walk recorded in Blith, or a walk that only exists in Apple Health.
public struct WalkHistoryEntry: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable { case gps, health }

    public var id: String
    public var kind: Kind
    public var title: String
    public var start: Date
    public var movingTime: TimeInterval
    /// Nil when the record has no distance (shown as "Not available", never 0).
    public var distance: Double?
    public var recordedWalkID: String?
    public var source: SourceRef?

    public var hasMap: Bool { kind == .gps }
}

public enum WalkHistory {
    /// GPS walks plus Health walks, each walk once: Health entries that Blith saved itself, or
    /// that a GPS walk was merged into, or that overlap a GPS walk, are dropped.
    public static func entries(recorded: [RecordedWalk], workouts: [WorkoutRecord], ownSourceID: String,
                               calendar: Calendar = .current) -> [WalkHistoryEntry] {
        var out = recorded.map { w in
            WalkHistoryEntry(id: "gps-\(w.id)", kind: .gps, title: w.displayTitle(calendar: calendar), start: w.start,
                             movingTime: w.movingTime, distance: w.track.distance, recordedWalkID: w.id, source: nil)
        }
        let linked = Set(recorded.compactMap(\.healthWorkoutID))
        let intervals = recorded.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        for w in workouts where w.isWalking {
            if w.source.identifier == ownSourceID || linked.contains(w.id) { continue }
            let span = DateInterval(start: w.start, end: max(w.start, w.end))
            if intervals.contains(where: { WalkMerge.isSameWalk($0, span) }) { continue }
            out.append(WalkHistoryEntry(id: "health-\(w.id)", kind: .health, title: w.activity == "Hiking" ? "Hike" : "Outdoor walk",
                                        start: w.start, movingTime: w.duration, distance: w.distanceMeters, recordedWalkID: nil,
                                        source: w.source))
        }
        return out.sorted { $0.start > $1.start }
    }
}

// MARK: Same route

public struct RouteComparison: Sendable, Equatable {
    /// Earlier walks of the same route, newest first.
    public var previousCount: Int
    /// Median moving time of those walks.
    public var usualTime: TimeInterval
    /// This walk minus the usual: negative is quicker.
    public var difference: TimeInterval
    public var isFastest: Bool

    /// One plain sentence, or nil when there's nothing honest to say.
    public func sentence(routeName: String) -> String {
        let minutes = Int((abs(difference) / 60).rounded())
        if isFastest, previousCount >= 2, minutes >= 1 {
            return "Your fastest \(routeName), \(minutes) min quicker than your usual."
        }
        if minutes < 1 { return "About your usual time for \(routeName)." }
        return difference < 0 ? "\(minutes) min quicker than your usual \(routeName)." : "\(minutes) min slower than your usual \(routeName), and that's fine."
    }
}

public enum RouteMatch {
    /// Same route: starts and ends within 150 m of each other and covers a similar distance (±15%).
    public static func isSameRoute(_ a: RecordedWalk, _ b: RecordedWalk) -> Bool {
        let ta = a.track, tb = b.track
        guard let a0 = ta.segments.first?.first, let a1 = ta.segments.last?.last,
              let b0 = tb.segments.first?.first, let b1 = tb.segments.last?.last,
              ta.distance > 200, tb.distance > 200 else { return false }
        let ratio = ta.distance / tb.distance
        return Geo.distance(a0, b0) <= 150 && Geo.distance(a1, b1) <= 150 && ratio >= 0.85 && ratio <= 1.15
    }

    /// How this walk compares with earlier walks of the same route. Nil without any.
    public static func compare(_ walk: RecordedWalk, with others: [RecordedWalk]) -> RouteComparison? {
        let previous = others.filter { $0.id != walk.id && $0.start < walk.start && isSameRoute(walk, $0) }
        guard !previous.isEmpty, let usual = Stats.median(previous.map(\.movingTime)) else { return nil }
        let fastest = previous.allSatisfy { walk.movingTime < $0.movingTime }
        return RouteComparison(previousCount: previous.count, usualTime: usual, difference: walk.movingTime - usual, isFastest: fastest)
    }
}
