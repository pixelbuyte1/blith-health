import BlithCore
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import Observation

/// Records a GPS walk: Core Location for the route, the iPhone's pedometer for steps, the
/// barometer for climb, and heart rate from Apple Health when a Watch provides it.
///
/// Raw fixes are kept as they arrive; what counts is decided by `TrackProcessor` in BlithCore.
/// The walk is checkpointed to disk while it runs, so if Blith is closed mid-walk it can be
/// resumed or saved on the next launch. Background location runs only while a walk is active.
@MainActor
@Observable
final class WalkRecorder {
    enum Phase: Equatable {
        case idle
        /// Start screen: GPS warming up, permissions explained.
        case ready
        case recording
        case paused
        /// Finish screen: the walk is held (paused) until it's saved, resumed or discarded.
        case finishing
        /// Summary after saving.
        case saved
    }

    enum LocationAccess: Equatable {
        case notDetermined, denied, restricted, approximate, allowed

        var canTrack: Bool { self == .allowed || self == .approximate }
    }

    var isPresented = false
    private(set) var phase: Phase = .idle
    private(set) var access: LocationAccess = .notDetermined
    /// Accuracy of the newest fix in metres (for "GPS ready · ±5 m").
    private(set) var latestAccuracy: Double?
    private(set) var lastFixTime: Date?

    private(set) var start: Date?
    private(set) var points: [TrackPoint] = []
    private(set) var events: [WalkEvent] = []
    private(set) var track = ProcessedTrack.empty
    private(set) var heart: [HeartSample] = []
    private(set) var heartSource: String?
    private(set) var isDemo = false
    private var walkID = UUID().uuidString
    private var completedSteps: Int?
    private var liveSteps: Int?
    private var climbCounter = ClimbCounter()
    private var climbBefore = 0.0

    let stepsAvailable = CMPedometer.isStepCountingAvailable()
    let climbAvailable = CMAltimeter.isRelativeAltitudeAvailable()

    /// The walk on the Finish screen.
    private(set) var finished: RecordedWalk?
    /// True when the walk on the Finish screen was recovered after Blith closed (sensors aren't running).
    private(set) var finishedIsRecovered = false
    /// A Watch walk that already covers the one being finished.
    private(set) var watchWalk: WorkoutRecord?
    private(set) var isSaving = false
    /// What happened when saving: shown on the summary.
    private(set) var saveMessage: String?
    private(set) var summaryWalk: RecordedWalk?

    /// Finished GPS walks on this iPhone, newest first.
    private(set) var walks: [RecordedWalk] = WalkStore.loadWalks()
    /// A walk that was still running when Blith last closed.
    var interrupted: WalkStore.Checkpoint?

    private let manager = CLLocationManager()
    private let bridge = LocationBridge()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let healthStore = HKHealthStore()
    private var heartQuery: HKAnchoredObjectQuery?
    private var backgroundSession: CLBackgroundActivitySession?
    private var lastCheckpoint = Date.distantPast

    init() {
        manager.delegate = bridge
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        bridge.onLocations = { [weak self] locations in self?.receive(locations) }
        bridge.onAuthorization = { [weak self] in self?.updateAccess() }
        updateAccess()
    }

    // MARK: Derived values for the screens

    var isActive: Bool { phase == .recording || phase == .paused || phase == .finishing }

    func pauses(at now: Date) -> [DateInterval] { WalkClock.pauses(events, end: now) }

    func movingTime(at now: Date) -> TimeInterval {
        guard let start else { return 0 }
        return WalkClock.movingTime(start: start, end: now, pauses: pauses(at: now))
    }

    /// When the current pause began.
    var pausedSince: Date? { phase == .paused ? events.last(where: { $0.kind == .pause })?.time : nil }

    /// Steps over the moving parts of the walk, or nil when the motion sensor isn't available or allowed.
    var steps: Int? {
        guard stepsAvailable, CMPedometer.authorizationStatus() != .denied, let completedSteps else { return nil }
        return completedSteps + (liveSteps ?? 0)
    }

    /// Metres climbed, from the barometer.
    var climb: Double? { climbAvailable ? climbBefore + climbCounter.gain : nil }

    /// The newest heart rate reading in the last two minutes, if any device is providing one.
    func heartRate(at now: Date) -> Double? {
        guard let last = heart.last, now.timeIntervalSince(last.date) <= 120 else { return nil }
        return last.bpm
    }

    /// True when no fix has arrived for a while during a running walk.
    func gpsLost(at now: Date) -> Bool {
        guard phase == .recording else { return false }
        guard let lastFixTime else { return now.timeIntervalSince(start ?? now) > 30 }
        return now.timeIntervalSince(lastFixTime) > 30
    }

    // MARK: Permissions

    func updateAccess() {
        switch manager.authorizationStatus {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        default: access = manager.accuracyAuthorization == .reducedAccuracy ? .approximate : .allowed
        }
        if phase == .ready, access.canTrack { manager.startUpdatingLocation() }
    }

    func requestLocation() {
        if access == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if access == .approximate {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WalkTracking")
        }
    }

    // MARK: Flow

    /// Opens the Start screen (or returns to the walk already running).
    func present(isDemo: Bool) {
        if phase == .idle || phase == .saved {
            self.isDemo = isDemo
            summaryWalk = nil
            finished = nil
            saveMessage = nil
            phase = .ready
            if access.canTrack {
                manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.startUpdatingLocation()
            } else {
                requestLocation()
            }
        }
        isPresented = true
    }

    /// Closes the Start screen without walking.
    func cancel() {
        guard phase == .ready else { return }
        manager.stopUpdatingLocation()
        phase = .idle
        isPresented = false
    }

    func startWalk() {
        let now = Date()
        walkID = UUID().uuidString
        start = now
        points = []
        events = []
        track = .empty
        heart = []
        heartSource = nil
        completedSteps = stepsAvailable ? 0 : nil
        liveSteps = nil
        climbCounter = ClimbCounter()
        climbBefore = 0
        phase = .recording
        beginSensors(stretchStart: now)
        checkpoint(force: true)
    }

    func pause() {
        guard phase == .recording else { return }
        events.append(WalkEvent(.pause, at: Date()))
        phase = .paused
        endStretch()
        // Battery: no route is drawn while paused, so coarse location is enough.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        refreshTrack()
        checkpoint(force: true)
    }

    func resume() {
        guard phase == .paused || (phase == .finishing && !finishedIsRecovered) else { return }
        let now = Date()
        events.append(WalkEvent(.resume, at: now))
        phase = .recording
        finished = nil
        watchWalk = nil
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        startPedometer(from: now)
        startAltimeter()
        checkpoint(force: true)
    }

    /// Holds the walk (paused) and opens the Finish screen.
    func finish(app: AppModel) async {
        guard let start, phase == .recording || phase == .paused else { return }
        if phase == .recording { pause() }
        let end = events.last(where: { $0.kind == .pause })?.time ?? Date()
        var walk = RecordedWalk(id: walkID, start: start, end: end, points: points, events: events,
                                climb: climb, heart: heart, heartSource: heartSource, isDemo: isDemo)
        // The final pause is the end of the walk, not a pause within it.
        walk.events = Array(walk.events.dropLast())
        walk.steps = await preciseSteps(for: walk) ?? steps
        finished = walk
        finishedIsRecovered = false
        phase = .finishing
        watchWalk = walk.isDemo ? nil : await writer(app).existingWalk(start: walk.start, end: walk.end)
    }

    func save(feel: WalkFeel?, note: String, app: AppModel) async {
        guard var walk = finished, !isSaving else { return }
        isSaving = true
        walk.feel = feel
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        walk.note = trimmed.isEmpty ? nil : trimmed
        if walk.isDemo {
            saveMessage = "Sample mode: this walk is kept on this iPhone and not saved to Apple Health."
        } else {
            do {
                switch try await writer(app).save(walk) {
                case .saved(let id):
                    walk.healthWorkoutID = id
                    saveMessage = "Saved to Apple Health as a walking workout with its route."
                case .merged(let watch):
                    walk.healthWorkoutID = watch.id
                    walk.mergedWithWatch = true
                    saveMessage = "Your Apple Watch recorded this walk too. Blith kept the Watch's walk, so nothing counts twice."
                }
            } catch {
                saveMessage = (error as? LocalizedError)?.errorDescription ?? "Apple Health didn't accept the walk. It's still saved on this iPhone."
            }
        }
        walks.insert(walk, at: 0)
        WalkStore.saveWalks(walks)
        endSession()
        isSaving = false
        summaryWalk = walk
        phase = .saved
        await app.refresh(force: true)
    }

    func discard() {
        endSession()
        phase = .idle
        isPresented = false
    }

    func closeSummary() {
        summaryWalk = nil
        saveMessage = nil
        phase = .idle
        isPresented = false
    }

    /// Profile › Delete all Blith data.
    func deleteAll() {
        if phase != .idle { endSession() }
        phase = .idle
        isPresented = false
        interrupted = nil
        summaryWalk = nil
        walks = []
        WalkStore.deleteAll()
    }

    // MARK: Interrupted walks

    func checkForInterruptedWalk() {
        guard phase == .idle, interrupted == nil, let checkpoint = WalkStore.loadCheckpoint() else { return }
        interrupted = checkpoint
    }

    /// Carries on recording. The time Blith wasn't running is unknown, so it's treated as a pause.
    func resumeInterrupted() {
        guard let cp = interrupted else { return }
        interrupted = nil
        let w = cp.walk
        let now = Date()
        walkID = w.id
        start = w.start
        points = w.points
        events = w.events
        if !cp.isPaused { events.append(WalkEvent(.pause, at: w.end)) }
        events.append(WalkEvent(.resume, at: now))
        heart = w.heart
        heartSource = w.heartSource
        isDemo = w.isDemo
        completedSteps = stepsAvailable ? (cp.completedSteps ?? 0) : nil
        liveSteps = nil
        climbCounter = ClimbCounter()
        climbBefore = w.climb ?? 0
        phase = .recording
        isPresented = true
        beginSensors(stretchStart: now)
        refreshTrack()
        checkpoint(force: true)
    }

    /// Finishes the walk as it was at the last checkpoint.
    func finishInterrupted(app: AppModel) async {
        guard let cp = interrupted else { return }
        interrupted = nil
        var walk = cp.walk
        walk.steps = await preciseSteps(for: walk)
        finished = walk
        finishedIsRecovered = true
        isDemo = walk.isDemo
        phase = .finishing
        isPresented = true
        watchWalk = walk.isDemo ? nil : await writer(app).existingWalk(start: walk.start, end: walk.end)
    }

    func discardInterrupted() {
        interrupted = nil
        WalkStore.clearCheckpoint()
    }

    // MARK: Sensors

    private func writer(_ app: AppModel) -> WalkHealthWriter {
        WalkHealthWriter(store: healthStore, reader: app.healthKit)
    }

    private func beginSensors(stretchStart: Date) {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        backgroundSession = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
        startPedometer(from: stretchStart)
        startAltimeter()
        startHeart(from: start ?? stretchStart)
    }

    /// Stops the per-stretch sensors at a pause and banks the stretch's steps.
    private func endStretch() {
        pedometer.stopUpdates()
        if let c = completedSteps { completedSteps = c + (liveSteps ?? 0) }
        liveSteps = nil
        altimeter.stopRelativeAltitudeUpdates()
        climbBefore += climbCounter.gain
        climbCounter = ClimbCounter()
    }

    private func endSession() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        if let heartQuery { healthStore.stop(heartQuery) }
        heartQuery = nil
        WalkStore.clearCheckpoint()
        start = nil
        points = []
        events = []
        track = .empty
        finished = nil
        watchWalk = nil
        finishedIsRecovered = false
    }

    private func startPedometer(from date: Date) {
        guard stepsAvailable else { return }
        liveSteps = 0
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let n = data?.numberOfSteps.intValue else { return }
            Task { @MainActor [weak self] in self?.liveSteps = n }
        }
    }

    private func startAltimeter() {
        guard climbAvailable else { return }
        climbCounter.resetReference()
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let metres = data?.relativeAltitude.doubleValue else { return }
            Task { @MainActor [weak self] in self?.addAltitude(metres) }
        }
    }

    private func addAltitude(_ metres: Double) {
        guard phase == .recording else { return }
        climbCounter.add(metres)
    }

    private func startHeart(from date: Date) {
        guard HKHealthStore.isHealthDataAvailable(), heartQuery == nil else { return }
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, added, _, _, _ in
            let samples = added as? [HKQuantitySample] ?? []
            let items = samples.map { HeartSample(date: $0.endDate, bpm: $0.quantity.doubleValue(for: unit)) }
            let fromWatch = samples.contains { s in
                (s.device?.model ?? s.sourceRevision.productType ?? "").lowercased().contains("watch")
            }
            Task { @MainActor [weak self] in self?.ingestHeart(items, fromWatch: fromWatch) }
        }
        let q = HKAnchoredObjectQuery(type: HKQuantityType(.heartRate), predicate: predicate, anchor: nil,
                                      limit: HKObjectQueryNoLimit, resultsHandler: handler)
        q.updateHandler = handler
        heartQuery = q
        healthStore.execute(q)
    }

    private func ingestHeart(_ items: [HeartSample], fromWatch: Bool) {
        guard !items.isEmpty else { return }
        heart = (heart + items).sorted { $0.date < $1.date }
        if fromWatch {
            heartSource = WalkSource.watch.rawValue
        } else if heartSource == nil {
            heartSource = WalkSource.health.rawValue
        }
    }

    /// Steps over each moving stretch, asked from the pedometer's own history (accurate after the fact).
    private func preciseSteps(for walk: RecordedWalk) async -> Int? {
        guard stepsAvailable, CMPedometer.authorizationStatus() != .denied else { return nil }
        var total = 0
        for interval in walk.movingIntervals {
            let n: Int? = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: interval.start, to: interval.end) { data, _ in
                    continuation.resume(returning: data?.numberOfSteps.intValue)
                }
            }
            guard let n else { return nil }
            total += n
        }
        return total
    }

    // MARK: Location

    private func receive(_ locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        latestAccuracy = newest.horizontalAccuracy >= 0 ? newest.horizontalAccuracy : nil
        lastFixTime = newest.timestamp
        guard phase == .recording, let start else { return }
        for l in locations where l.timestamp >= start {
            points.append(TrackPoint(time: l.timestamp, latitude: l.coordinate.latitude, longitude: l.coordinate.longitude,
                                     horizontalAccuracy: l.horizontalAccuracy, altitude: l.verticalAccuracy >= 0 ? l.altitude : nil))
        }
        refreshTrack()
        checkpoint(force: false)
    }

    private func refreshTrack() {
        track = TrackProcessor.process(points, pauses: pauses(at: Date()))
    }

    private func checkpoint(force: Bool) {
        guard let start, phase == .recording || phase == .paused else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCheckpoint) >= 15 else { return }
        lastCheckpoint = now
        let walk = RecordedWalk(id: walkID, start: start, end: now, points: points, events: events,
                                climb: climb, heart: heart, heartSource: heartSource, isDemo: isDemo)
        WalkStore.saveCheckpoint(WalkStore.Checkpoint(walk: walk, isPaused: phase == .paused, completedSteps: completedSteps))
    }
}

/// Core Location's delegate, forwarding to the recorder on the main actor.
private final class LocationBridge: NSObject, CLLocationManagerDelegate {
    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    var onAuthorization: (@MainActor () -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        deliver { [weak self] in self?.onLocations?(locations) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        deliver { [weak self] in self?.onAuthorization?() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func deliver(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    }
}
