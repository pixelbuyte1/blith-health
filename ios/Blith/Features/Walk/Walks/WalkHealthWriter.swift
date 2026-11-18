import BlithCore
import CoreLocation
import Foundation
import HealthKit

/// Saves a GPS walk to Apple Health, once.
///
/// What it writes: one walking workout (outdoor) with its pause and resume events, one distance
/// sample per stretch of good GPS, and the route. It never writes steps or active energy: the
/// iPhone and Watch already record those, and Health's own deduplication keeps the distance
/// sample from counting twice in daily totals. If the Watch already recorded an overlapping walk,
/// nothing is written and Blith links to the Watch's workout instead.
struct WalkHealthWriter {
    let store: HKHealthStore
    let reader: AppleHealthProvider

    enum Outcome {
        /// Saved as a new workout with this id.
        case saved(String)
        /// The Watch's own walk covers this one; it was kept and nothing new was written.
        case merged(WorkoutRecord)
    }

    enum WriteError: LocalizedError {
        case notAllowed, failed

        var errorDescription: String? {
            switch self {
            case .notAllowed: "Blith isn't allowed to save workouts to Apple Health. You can turn this on in Settings › Health › Data Access › Blith."
            case .failed: "Apple Health didn't accept the walk. It's still saved on this iPhone."
            }
        }
    }

    static var ownSourceID: String { Bundle.main.bundleIdentifier ?? "blith" }

    var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKSeriesType.workoutRoute()]
    }

    /// Asked the first time a walk is saved, not at launch.
    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: shareTypes, read: [HKObjectType.workoutType()])
    }

    /// A walking workout from another source (usually the Watch) that covers this walk.
    func existingWalk(start: Date, end: Date) async -> WorkoutRecord? {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-3600), end: end.addingTimeInterval(3600), options: [])
        guard let workouts = try? await reader.workouts(predicate: predicate) else { return nil }
        return WalkMerge.existingWalk(for: DateInterval(start: start, end: max(start, end)), in: workouts, ownSourceID: Self.ownSourceID)
    }

    func save(_ walk: RecordedWalk) async throws -> Outcome {
        if let watch = await existingWalk(start: walk.start, end: walk.end) { return .merged(watch) }
        try await requestAccess()
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { throw WriteError.notAllowed }

        let track = walk.track
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: walk.start)

            // Distance only along good GPS: one sample per segment, so gaps and pauses add nothing.
            let distanceType = HKQuantityType(.distanceWalkingRunning)
            let samples: [HKSample] = track.segments.compactMap { segment in
                guard let first = segment.first, let last = segment.last, last.time > first.time else { return nil }
                let metres = TrackProcessor.process(segment).distance
                guard metres > 0 else { return nil }
                return HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: metres),
                                        start: first.time, end: last.time)
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }

            let events: [HKWorkoutEvent] = walk.events.map { e in
                HKWorkoutEvent(type: e.kind == .pause ? .pause : .resume,
                               dateInterval: DateInterval(start: e.time, duration: 0), metadata: nil)
            }
            if !events.isEmpty { try await builder.addWorkoutEvents(events) }
            try await builder.addMetadata([HKMetadataKeyIndoorWorkout: false, "BlithWalkID": walk.id])
            try await builder.endCollection(at: walk.end)
            guard let workout = try await builder.finishWorkout() else { throw WriteError.failed }

            let locations = track.segments.joined().map { p in
                CLLocation(coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                           altitude: p.altitude ?? 0, horizontalAccuracy: p.horizontalAccuracy,
                           verticalAccuracy: p.altitude == nil ? -1 : 10, timestamp: p.time)
            }
            if !locations.isEmpty {
                let route = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try await route.insertRouteData(locations)
                _ = try await route.finishRoute(with: workout, metadata: nil)
            }
            return .saved(workout.uuid.uuidString)
        } catch let error as WriteError {
            throw error
        } catch {
            throw WriteError.failed
        }
    }
}
