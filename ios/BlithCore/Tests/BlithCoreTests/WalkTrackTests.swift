import Foundation
import Testing
@testable import BlithCore

/// A walk heading north at `speed` m/s with a fix every `every` seconds.
private func line(from start: Date, seconds: Int, every: Int = 5, speed: Double = 1.4, accuracy: Double = 5,
                  lat0: Double = 51.5, lon: Double = -0.1) -> [TrackPoint] {
    let metresPerDegree = Geo.earthRadius * .pi / 180
    var points: [TrackPoint] = []
    for t in stride(from: 0, through: seconds, by: every) {
        let latitude: Double = lat0 + speed * Double(t) / metresPerDegree
        points.append(TrackPoint(time: start.addingTimeInterval(Double(t)), latitude: latitude,
                                 longitude: lon, horizontalAccuracy: accuracy))
    }
    return points
}

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

@Suite("Walk tracking")
struct WalkTrackTests {
    @Test func steadyWalkDistanceMatchesSpeedTimesTime() {
        let track = TrackProcessor.process(line(from: t0, seconds: 600))
        #expect(abs(track.distance - 840) < 5)
        #expect(track.segments.count == 1)
        #expect(track.gaps.isEmpty)
        #expect(track.rejected == 0)
    }

    @Test func inaccurateFixesAndJumpsAreIgnored() {
        var pts = line(from: t0, seconds: 300)
        // A 60 m-accuracy fix and a 400 m teleport in the middle.
        pts[10].horizontalAccuracy = 60
        pts[20].latitude += 400 / (Geo.earthRadius * .pi / 180)
        pts.append(TrackPoint(time: t0.addingTimeInterval(150.5), latitude: 51.5, longitude: -0.1, horizontalAccuracy: -1))
        let track = TrackProcessor.process(pts)
        #expect(track.rejected == 3)
        #expect(abs(track.distance - 420) < 8)
    }

    @Test func standingStillDoesNotAddDistance() {
        // Ten minutes of fixes wobbling around one spot by a metre or two.
        var pts: [TrackPoint] = []
        for i in 0...120 {
            let time: Date = t0.addingTimeInterval(Double(i * 5))
            let latitude: Double = 51.5 + Double(i % 3) * 0.000_01
            let longitude: Double = -0.1 + Double(i % 2) * 0.000_01
            pts.append(TrackPoint(time: time, latitude: latitude, longitude: longitude, horizontalAccuracy: 8))
        }
        #expect(TrackProcessor.process(pts).distance < 5)
    }

    @Test func gpsGapIsMarkedNotDrawnAndNotCounted() {
        let a = line(from: t0, seconds: 120)
        // 90 s with no fixes, then the walk continues 500 m further north (as if a tunnel).
        let resumeLat = a.last!.latitude + 500 / (Geo.earthRadius * .pi / 180)
        let b = line(from: t0.addingTimeInterval(210), seconds: 120, lat0: resumeLat)
        let track = TrackProcessor.process(a + b)
        #expect(track.segments.count == 2)
        #expect(track.gaps.count == 1)
        #expect(abs(track.gapSeconds - 90) < 1)
        #expect(abs(track.distance - 2 * 168) < 5)
        // The timer keeps running through the gap.
        #expect(WalkClock.movingTime(start: t0, end: t0.addingTimeInterval(330), pauses: []) == 330)
    }

    @Test func pausedTimeAndFixesAreExcluded() {
        let events = [WalkEvent(.pause, at: t0.addingTimeInterval(300)), WalkEvent(.resume, at: t0.addingTimeInterval(420))]
        let end = t0.addingTimeInterval(720)
        let pauses = WalkClock.pauses(events, end: end)
        #expect(pauses == [DateInterval(start: t0.addingTimeInterval(300), end: t0.addingTimeInterval(420))])
        #expect(WalkClock.movingTime(start: t0, end: end, pauses: pauses) == 600)
        #expect(WalkClock.movingIntervals(start: t0, end: end, pauses: pauses).count == 2)
        // Fixes keep arriving while paused (the person drifts); they don't count.
        let track = TrackProcessor.process(line(from: t0, seconds: 720), pauses: pauses)
        #expect(track.segments.count == 2)
        #expect(track.gaps.isEmpty)
        #expect(abs(track.distance - 1.4 * 590) < 15)
    }

    @Test func unresumedPauseRunsToTheEnd() {
        let events = [WalkEvent(.pause, at: t0.addingTimeInterval(100))]
        #expect(WalkClock.movingTime(start: t0, end: t0.addingTimeInterval(400), pauses: WalkClock.pauses(events, end: t0.addingTimeInterval(400))) == 100)
    }

    @Test func splitsUseMovingTime() {
        let pauses = [DateInterval(start: t0.addingTimeInterval(400), end: t0.addingTimeInterval(700))]
        let pts = line(from: t0, seconds: 2000, speed: 1.25)
        let track = TrackProcessor.process(pts, pauses: pauses)
        let splits = WalkSplits.compute(track, start: t0, pauses: pauses, units: .metric)
        #expect(splits.count == 3)
        // 1 km at 1.25 m/s = 800 s; the 300 s pause must not show up in any split.
        #expect(splits.allSatisfy { $0.distance < 1001 })
        #expect(abs(splits[0].duration - 800) < 15)
        #expect(abs(splits[1].duration - 800) < 15)
        #expect(splits.allSatisfy { !$0.includesGap })
        #expect(WalkPace.format(splits[0].pace(.metric)) == "13′20″" || WalkPace.format(splits[0].pace(.metric)).hasPrefix("13′"))
    }

    @Test func kilometreMarkers() {
        let track = TrackProcessor.process(line(from: t0, seconds: 2500, speed: 1.4))
        #expect(WalkSplits.markers(track, units: .metric).count == 3)
        #expect(WalkSplits.markers(track, units: .imperial).count == 2)
    }

    @Test func paceNeedsFreshGPS() {
        let pts = line(from: t0, seconds: 300)
        let track = TrackProcessor.process(pts)
        let now = pts.last!.time
        let pace = WalkPace.current(track, now: now, units: .metric)
        #expect(pace != nil)
        let expected: Double = 1000 / 1.4
        let error: Double = abs((pace ?? 0) - expected)
        #expect(error < 20)
        #expect(WalkPace.current(track, now: now.addingTimeInterval(60), units: .metric) == nil)
        #expect(WalkPace.average(distance: 20, movingTime: 30, units: .metric) == nil)
        #expect(WalkPace.clock(3909) == "1:05:09")
        #expect(WalkPace.clock(1601) == "26:41")
    }

    @Test func climbIgnoresBarometerNoise() {
        var c = ClimbCounter()
        for v in [0.0, 0.4, -0.3, 0.5, 0.2] { c.add(v) }
        #expect(c.gain == 0)
        for v in [1.5, 3.0, 2.0, 6.0] { c.add(v) }
        #expect(abs(c.gain - 7.0) < 0.01)
    }

    @Test func heartSummaryOnlyCountsMovingTime() {
        let moving = [DateInterval(start: t0, duration: 600)]
        let samples = (0..<10).map { HeartSample(date: t0.addingTimeInterval(Double($0 * 60)), bpm: 100 + Double($0)) }
            + [HeartSample(date: t0.addingTimeInterval(900), bpm: 160)]
        let s = WalkHeart.summary(samples, within: moving)
        #expect(s?.maximum == 109)
        #expect(s?.count == 10)
        #expect(WalkHeart.summary(Array(samples.prefix(2)), within: moving) == nil)
    }
}

@Suite("Walks counted once")
struct WalkMergeTests {
    let own = "com.blith.health"
    let watch = SourceRef(provider: .appleHealth, name: "Zen's Apple Watch", identifier: "com.apple.health.watch", device: "Watch")

    func workout(_ id: String, start: Double, minutes: Double, activity: String = "Walking", source: SourceRef? = nil) -> WorkoutRecord {
        WorkoutRecord(id: id, activity: activity, start: t0.addingTimeInterval(start), end: t0.addingTimeInterval(start + minutes * 60),
                      energyKcal: nil, distanceMeters: 2000, source: source ?? watch)
    }

    @Test func watchWalkOverlappingIsKeptInsteadOfSavingAgain() {
        let walk = DateInterval(start: t0, duration: 50 * 60)
        let workouts = [workout("run", start: 0, minutes: 50, activity: "Running"),
                        workout("watch", start: 120, minutes: 45),
                        workout("earlier", start: -7200, minutes: 30)]
        #expect(WalkMerge.existingWalk(for: walk, in: workouts, ownSourceID: own)?.id == "watch")
        #expect(WalkMerge.existingWalk(for: DateInterval(start: t0.addingTimeInterval(-4000), duration: 600), in: workouts, ownSourceID: own) == nil)
        let mine = SourceRef(provider: .appleHealth, name: "Blith", identifier: own)
        #expect(WalkMerge.existingWalk(for: walk, in: [workout("mine", start: 0, minutes: 50, source: mine)], ownSourceID: own) == nil)
    }

    @Test func historyListsEachWalkOnce() {
        let pts = line(from: t0, seconds: 600)
        let gps = RecordedWalk(id: "a", start: t0, end: t0.addingTimeInterval(600), points: pts, healthWorkoutID: "saved")
        let merged = RecordedWalk(id: "b", start: t0.addingTimeInterval(86_400), end: t0.addingTimeInterval(86_400 + 600),
                                  points: line(from: t0.addingTimeInterval(86_400), seconds: 600), healthWorkoutID: "watch2", mergedWithWatch: true)
        let mine = SourceRef(provider: .appleHealth, name: "Blith", identifier: own)
        let workouts = [
            workout("saved", start: 0, minutes: 10, source: mine),       // Blith's own save of walk a
            workout("watch2", start: 86_400, minutes: 10),               // the Watch walk b was merged into
            workout("overlap", start: 60, minutes: 8),                   // a stray Watch copy of walk a
            workout("solo", start: -86_400, minutes: 34),                // a Health-only walk
            workout("gym", start: -40_000, minutes: 30, activity: "Strength"),
        ]
        let entries = WalkHistory.entries(recorded: [gps, merged], workouts: workouts, ownSourceID: own)
        #expect(entries.map(\.id) == ["gps-b", "gps-a", "health-solo"])
        #expect(entries[2].hasMap == false)
        #expect(entries[2].kind == .health)
    }

    @Test func sameRouteComparison() {
        func walk(_ id: String, day: Double, speed: Double) -> RecordedWalk {
            let start = t0.addingTimeInterval(day * 86_400)
            let seconds = Int((1200 / speed).rounded())
            return RecordedWalk(id: id, title: "Riverside Loop", start: start, end: start.addingTimeInterval(Double(seconds)),
                                points: line(from: start, seconds: seconds, speed: speed))
        }
        let earlier = [walk("1", day: 0, speed: 1.3), walk("2", day: 1, speed: 1.35), walk("3", day: 2, speed: 1.3)]
        let today = walk("4", day: 3, speed: 1.5)
        let result = RouteMatch.compare(today, with: earlier)
        #expect(result?.previousCount == 3)
        #expect(result?.isFastest == true)
        #expect(result?.sentence(routeName: "Riverside Loop").hasPrefix("Your fastest Riverside Loop") == true)
        // A different route (twice as long) doesn't match.
        let other = RecordedWalk(id: "x", start: t0, end: t0.addingTimeInterval(1800), points: line(from: t0, seconds: 1800, speed: 1.4))
        #expect(RouteMatch.compare(today, with: [other]) == nil)
    }
}
