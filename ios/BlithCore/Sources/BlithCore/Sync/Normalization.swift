import Foundation

/// Groups raw sleep segments into nights and picks one source per night, so a phone and a
/// watch that both logged the same night are never added together.
public enum SleepAssembler {
    /// Segments ending after 6 PM belong to the next day's night.
    public static let dayBoundaryHour: Double = 18

    public static func nights(from segments: [SleepSegment], calendar: Calendar) -> [SleepNight] {
        var byNight: [LocalDate: [SleepSegment]] = [:]
        for s in segments where s.duration > 0 {
            let shifted = s.end.addingTimeInterval(-dayBoundaryHour * 3600)
            let date = LocalDate(shifted, calendar: calendar).adding(days: 1)
            byNight[date, default: []].append(s)
        }
        return byNight.compactMap { date, segs -> SleepNight? in
            let bySource = Dictionary(grouping: segs, by: { $0.source })
            let candidates = bySource.map { SleepNight(date: date, segments: $0.value, source: $0.key) }
            // Prefer a source with stage data, then the one that recorded the most sleep.
            let best = candidates.max { a, b in
                if a.hasStages != b.hasStages { return !a.hasStages }
                return a.asleepDuration < b.asleepDuration
            }
            guard let best, best.asleepDuration >= 30 * 60 else { return nil }
            return best
        }
        .sorted { $0.date < $1.date }
    }
}

/// Combines batches from several providers without double counting.
///
/// Rule: the same walk is usually recorded by more than one provider (a Huawei watch syncing
/// to Apple Health *and* read directly from Huawei), so cumulative totals from different
/// providers are never summed. Per hour (or per day when hours are unknown) the larger value
/// wins; discrete metrics are averaged weighted by sample count; point samples that match in
/// time (±2 min) and value are kept once.
public enum SourceMerger {
    public static func merge(_ batches: [ProviderBatch]) -> ProviderBatch {
        guard batches.count > 1 else { return batches.first ?? ProviderBatch() }
        var out = ProviderBatch()

        // Hourly steps: max per hour.
        var hourly: [LocalDate: HourlyBuckets] = [:]
        for b in batches {
            for (date, buckets) in b.hourlySteps {
                let existing = hourly[date]?.values ?? Array(repeating: 0, count: 24)
                hourly[date] = HourlyBuckets(values: zip(existing, buckets.values).map { max($0, $1) })
            }
        }
        out.hourlySteps = hourly

        // Daily aggregates.
        let metrics = Set(batches.flatMap { $0.daily.keys })
        for metric in metrics {
            var byDate: [LocalDate: [DailyAggregate]] = [:]
            for b in batches { for agg in b.daily[metric] ?? [] { byDate[agg.date, default: []].append(agg) } }
            out.daily[metric] = byDate.map { date, aggs in
                switch metric.aggregation {
                case .cumulative:
                    var best = aggs.max { $0.value < $1.value }!
                    if metric == .steps, let h = hourly[date], h.total > best.value { best.value = h.total }
                    return best
                case .discrete:
                    let n = aggs.reduce(0) { $0 + max(1, $1.sampleCount) }
                    let mean = aggs.reduce(0) { $0 + $1.value * Double(max(1, $1.sampleCount)) } / Double(n)
                    return DailyAggregate(date: date, metric: metric, value: mean,
                                          min: aggs.compactMap(\.min).min(), max: aggs.compactMap(\.max).max(), sampleCount: n)
                }
            }
            .sorted { $0.date < $1.date }
        }

        out.weights = dedupeSamples(batches.flatMap(\.weights), tolerance: 0.05)
        out.bodyFat = dedupeSamples(batches.flatMap(\.bodyFat), tolerance: 0.002)
        out.sleepSegments = batches.flatMap(\.sleepSegments) // SleepAssembler picks one source per night
        out.workouts = dedupeWorkouts(batches.flatMap(\.workouts))
        for b in batches {
            for (metric, shares) in b.sources { out.sources[metric, default: []].append(contentsOf: shares) }
            out.sourceRecency.merge(b.sourceRecency) { a, b in (a.lastSeen ?? .distantPast) >= (b.lastSeen ?? .distantPast) ? a : b }
        }
        out.unsupported = batches.map(\.unsupported).reduce(Set(HealthMetric.allCases)) { $0.intersection($1) }
        return out
    }

    /// Keep one of any samples recorded within 2 minutes of each other with near-equal values.
    public static func dedupeSamples(_ samples: [HealthSample], tolerance: Double) -> [HealthSample] {
        let sorted = samples.sorted { $0.start < $1.start }
        var out: [HealthSample] = []
        var seenIDs = Set<String>()
        for s in sorted {
            if seenIDs.contains(s.id) { continue }
            if let dup = out.last(where: { abs($0.start.timeIntervalSince(s.start)) <= 120 }),
               abs(dup.value - s.value) <= tolerance {
                continue
            }
            out.append(s)
            seenIDs.insert(s.id)
        }
        return out
    }

    static func dedupeWorkouts(_ workouts: [WorkoutRecord]) -> [WorkoutRecord] {
        let sorted = workouts.sorted { $0.start < $1.start }
        var out: [WorkoutRecord] = []
        for w in sorted {
            let overlaps = out.contains { o in
                o.id == w.id || (abs(o.start.timeIntervalSince(w.start)) < 300 && abs(o.duration - w.duration) < 600)
            }
            if !overlaps { out.append(w) }
        }
        return out
    }
}
