import BlithCore
import Foundation
import HealthKit

/// HealthKit → normalized BlithCore types. Read-only.
///
/// Cumulative metrics use statistics collection queries, which merge overlapping iPhone and
/// Apple Watch samples by source priority — the same deduplication Apple Health uses — so
/// totals are never double counted. Discrete metrics use daily averages. Weight, sleep and
/// workouts keep per-sample provenance.
final class AppleHealthProvider: HealthDataProvider, @unchecked Sendable {
    let store = HKHealthStore()

    var kind: ProviderKind { .appleHealth }
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func quantityType(for metric: HealthMetric) -> HKQuantityType? {
        switch metric {
        case .steps: HKQuantityType(.stepCount)
        case .distanceWalkingRunning: HKQuantityType(.distanceWalkingRunning)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .exerciseMinutes: HKQuantityType(.appleExerciseTime)
        case .flightsClimbed: HKQuantityType(.flightsClimbed)
        case .walkingSpeed: HKQuantityType(.walkingSpeed)
        case .walkingStepLength: HKQuantityType(.walkingStepLength)
        case .walkingAsymmetry: HKQuantityType(.walkingAsymmetryPercentage)
        case .walkingDoubleSupport: HKQuantityType(.walkingDoubleSupportPercentage)
        case .weight: HKQuantityType(.bodyMass)
        case .bodyFat: HKQuantityType(.bodyFatPercentage)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .walkingHeartRate: HKQuantityType(.walkingHeartRateAverage)
        case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .oxygenSaturation: HKQuantityType(.oxygenSaturation)
        case .wristTemperature: HKQuantityType(.appleSleepingWristTemperature)
        case .vo2Max: HKQuantityType(.vo2Max)
        case .sleepDuration: nil
        }
    }

    static func unit(for metric: HealthMetric) -> HKUnit {
        switch metric {
        case .steps, .flightsClimbed: .count()
        case .distanceWalkingRunning, .walkingStepLength: .meter()
        case .activeEnergy: .kilocalorie()
        case .exerciseMinutes: .minute()
        case .walkingSpeed: HKUnit.meter().unitDivided(by: .second())
        case .walkingAsymmetry, .walkingDoubleSupport, .bodyFat: .percent()
        case .weight: .gramUnit(with: .kilo)
        case .restingHeartRate, .walkingHeartRate: HKUnit.count().unitDivided(by: .minute())
        case .hrv: .secondUnit(with: .milli)
        case .respiratoryRate: HKUnit.count().unitDivided(by: .minute())
        case .oxygenSaturation: .percent()
        case .wristTemperature: .degreeCelsius()
        case .vo2Max: HKUnit(from: "ml/kg*min")
        case .sleepDuration: .second()
        }
    }

    /// Only the types the product uses, grouped by what the user chose to connect.
    static func readTypes(for categories: Set<HealthCategory>) -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for category in categories {
            for metric in category.metrics {
                if let t = quantityType(for: metric) { types.insert(t) }
            }
            if category == .sleep { types.insert(HKCategoryType(.sleepAnalysis)) }
            if category == .movement { types.insert(HKObjectType.workoutType()) }
            if category == .heart { types.insert(HKQuantityType(.heartRate)) }
        }
        return types
    }

    func requestAuthorization(for categories: Set<HealthCategory>) async throws {
        guard isAvailable else { throw HealthProviderError.unavailable }
        do {
            try await store.requestAuthorization(toShare: Set<HKSampleType>(), read: Self.readTypes(for: categories))
        } catch {
            throw HealthProviderError.authorizationFailed(error.localizedDescription)
        }
    }

    /// Whether HealthKit would still show its permission sheet for these categories.
    func needsAuthorizationRequest(for categories: Set<HealthCategory>) async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: Set<HKSampleType>(), read: Self.readTypes(for: categories))
        return status == .shouldRequest
    }

    func earliestDataDate() async -> Date? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.stepCount))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 1)
        return try? await descriptor.result(for: store).first?.startDate
    }

    func fetch(_ request: ProviderFetch, calendar: Calendar) async throws -> ProviderBatch {
        var batch = ProviderBatch()
        let interval = request.span.dateInterval(in: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])

        for metric in request.metrics {
            do {
                batch.daily[metric] = try await daily(metric, span: request.span, calendar: calendar)
            } catch let error as HKError where error.code == .errorDatabaseInaccessible {
                // Device is locked: stop and let the sync engine retry later.
                throw HealthProviderError.queryFailed("Health data is locked while your iPhone is locked.")
            } catch {
                // Not authorized or not available for this metric: leave it empty.
                continue
            }
        }

        if request.includeHourlySteps {
            batch.hourlySteps = (try? await hourlySteps(span: request.span, calendar: calendar)) ?? [:]
        }
        if request.includeBody {
            batch.weights = (try? await samples(.weight, predicate: predicate)) ?? []
            batch.bodyFat = (try? await samples(.bodyFat, predicate: predicate)) ?? []
        }
        if request.includeSleep {
            let sleepInterval = request.sleepInterval(calendar: calendar)
            let sleepPredicate = HKQuery.predicateForSamples(withStart: sleepInterval.start, end: sleepInterval.end, options: [])
            batch.sleepSegments = (try? await sleepSegments(predicate: sleepPredicate)) ?? []
        }
        if request.includeWorkouts {
            batch.workouts = (try? await workouts(predicate: predicate)) ?? []
        }
        if request.includeSources {
            let sourceStart = max(interval.start, interval.end.addingTimeInterval(-Double(SyncEngine.sourceWindowDays) * 86_400))
            let sourcePredicate = HKQuery.predicateForSamples(withStart: sourceStart, end: interval.end, options: [])
            for metric in [HealthMetric.steps, .distanceWalkingRunning] {
                if let shares = try? await sourceShares(metric, predicate: sourcePredicate), !shares.isEmpty {
                    batch.sources[metric] = shares
                }
            }
            let weightSources = Dictionary(grouping: batch.weights, by: \.source).map { SourceShare(source: $0.key, value: Double($0.value.count)) }
            if !weightSources.isEmpty { batch.sources[.weight] = weightSources }
            batch.sourceRecency = await companionRecency(predicate: sourcePredicate)
        }
        return batch
    }

    /// The newest sample each companion app (Huawei Health) wrote to Apple Health, per metric.
    /// One source query per metric, then a single newest-sample query only when the app is present.
    func companionRecency(predicate: NSPredicate) async -> [String: SourceRecency] {
        var out: [String: SourceRecency] = [:]
        let now = Date()
        for app in CompanionApp.allCases {
            var latest: [HealthMetric: Date] = [:]
            for metric in app.watchMetrics {
                let type: HKSampleType
                if metric == .sleepDuration {
                    type = HKCategoryType(.sleepAnalysis)
                } else if let quantity = Self.quantityType(for: metric) {
                    type = quantity
                } else {
                    continue
                }
                let sourceQuery = HKSourceQueryDescriptor(predicate: .sample(type: type, predicate: predicate))
                guard let sources = try? await sourceQuery.result(for: store) else { continue }
                let mine = sources.filter {
                    CompanionApp.matching(SourceRef(provider: .appleHealth, name: $0.name, identifier: $0.bundleIdentifier)) == app
                }
                guard !mine.isEmpty else { continue }
                let fromApp = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, HKQuery.predicateForObjects(from: Set(mine))])
                let newest = HKSampleQueryDescriptor(
                    predicates: [.sample(type: type, predicate: fromApp)],
                    sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                    limit: 1)
                if let sample = try? await newest.result(for: store).first {
                    latest[metric] = sample.endDate
                }
            }
            if !latest.isEmpty {
                out[app.rawValue] = SourceRecency(app: app, latest: latest, checkedAt: now)
            }
        }
        return out
    }

    // MARK: Queries

    func daily(_ metric: HealthMetric, span: DateSpan, calendar: Calendar) async throws -> [DailyAggregate] {
        guard let type = Self.quantityType(for: metric) else { return [] }
        let interval = span.dateInterval(in: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let cumulative = metric.aggregation == .cumulative
        let options: HKStatisticsOptions = cumulative ? .cumulativeSum : [.discreteAverage, .discreteMin, .discreteMax]
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: span.start.startDate(in: calendar),
            intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        let unit = Self.unit(for: metric)
        var out: [DailyAggregate] = []
        for stats in collection.statistics() {
            let date = LocalDate(stats.startDate, calendar: calendar)
            guard span.contains(date) else { continue }
            if cumulative {
                if let sum = stats.sumQuantity() {
                    out.append(DailyAggregate(date: date, metric: metric, value: sum.doubleValue(for: unit)))
                }
            } else if let avg = stats.averageQuantity() {
                out.append(DailyAggregate(date: date, metric: metric, value: avg.doubleValue(for: unit),
                                          min: stats.minimumQuantity()?.doubleValue(for: unit),
                                          max: stats.maximumQuantity()?.doubleValue(for: unit), sampleCount: 1))
            }
        }
        return out
    }

    func hourlySteps(span: DateSpan, calendar: Calendar) async throws -> [LocalDate: HourlyBuckets] {
        let interval = span.dateInterval(in: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: span.start.startDate(in: calendar),
            intervalComponents: DateComponents(hour: 1))
        let collection = try await descriptor.result(for: store)
        var out: [LocalDate: [Double]] = [:]
        for stats in collection.statistics() {
            guard let sum = stats.sumQuantity() else { continue }
            let date = LocalDate(stats.startDate, calendar: calendar)
            let hour = calendar.component(.hour, from: stats.startDate)
            var values = out[date] ?? Array(repeating: 0, count: 24)
            values[hour] += sum.doubleValue(for: .count())
            out[date] = values
        }
        return out.mapValues { HourlyBuckets(values: $0) }
    }

    func samples(_ metric: HealthMetric, predicate: NSPredicate) async throws -> [HealthSample] {
        guard let type = Self.quantityType(for: metric) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let results = try await descriptor.result(for: store)
        let unit = Self.unit(for: metric)
        let now = Date()
        return results.map { s in
            HealthSample(id: s.uuid.uuidString, metric: metric, value: s.quantity.doubleValue(for: unit),
                         start: s.startDate, end: s.endDate, source: Self.source(of: s), syncedAt: now)
        }
    }

    func sleepSegments(predicate: NSPredicate) async throws -> [SleepSegment] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let results = try await descriptor.result(for: store)
        return results.map { s in
            let stage: SleepStage
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .inBed?: stage = .inBed
            case .awake?: stage = .awake
            case .asleepCore?: stage = .core
            case .asleepDeep?: stage = .deep
            case .asleepREM?: stage = .rem
            default: stage = .asleepUnspecified
            }
            return SleepSegment(start: s.startDate, end: s.endDate, stage: stage, source: Self.source(of: s))
        }
    }

    func workouts(predicate: NSPredicate) async throws -> [WorkoutRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let results = try await descriptor.result(for: store)
        return results.map { w in
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            return WorkoutRecord(id: w.uuid.uuidString, activity: Self.name(of: w.workoutActivityType),
                                 start: w.startDate, end: w.endDate, energyKcal: energy, distanceMeters: distance,
                                 source: Self.source(of: w))
        }
    }

    func sourceShares(_ metric: HealthMetric, predicate: NSPredicate) async throws -> [SourceShare] {
        guard let type = Self.quantityType(for: metric) else { return [] }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum, .separateBySource])
        let stats: HKStatistics? = try await descriptor.result(for: store)
        guard let stats else { return [] }
        let unit = Self.unit(for: metric)
        return (stats.sources ?? []).compactMap { source in
            guard let q = stats.sumQuantity(for: source) else { return nil }
            let ref = SourceRef(provider: .appleHealth, name: source.name, identifier: source.bundleIdentifier,
                                device: source.bundleIdentifier.lowercased().contains("watch") ? "Watch" : nil)
            return SourceShare(source: ref, value: q.doubleValue(for: unit))
        }
    }

    static func source(of sample: HKSample) -> SourceRef {
        let src = sample.sourceRevision.source
        return SourceRef(provider: .appleHealth, name: src.name, identifier: src.bundleIdentifier,
                         device: sample.device?.model ?? sample.sourceRevision.productType)
    }

    static func name(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Walking"
        case .running: "Running"
        case .hiking: "Hiking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .dance, .cardioDance, .socialDance: "Dance"
        case .pilates: "Pilates"
        case .stairClimbing, .stairs: "Stairs"
        default: "Workout"
        }
    }
}
