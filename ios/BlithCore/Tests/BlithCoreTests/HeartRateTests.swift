import Foundation
import Testing
@testable import BlithCore

struct HeartRateTests {
    static func samples(_ pairs: [(TimeInterval, Double)], now: Date = T.now) -> [HeartSample] {
        pairs.map { HeartSample(date: now.addingTimeInterval(-$0.0), bpm: $0.1) }
    }

    @Test func zonesFollowIntensityAboveTheOwnRestingRate() {
        #expect(HeartZone.zone(bpm: 62, resting: 60) == .resting)
        #expect(HeartZone.zone(bpm: 100, resting: 60) == .warm)
        #expect(HeartZone.zone(bpm: 125, resting: 60) == .elevated)
        #expect(HeartZone.zone(bpm: 150, resting: 60) == .hard)
        #expect(HeartZone.zone(bpm: 180, resting: 60) == .peak)
        // A higher resting rate raises the bar for each zone.
        #expect(HeartZone.zone(bpm: 100, resting: 80) < HeartZone.zone(bpm: 100, resting: 55) || HeartZone.zone(bpm: 100, resting: 80) == .resting)
        #expect(HeartZone.intensity(bpm: 300, resting: 60) == 1)
        #expect(HeartZone.intensity(bpm: 30, resting: 60) == 0)
    }

    @Test func freshnessIsLiveRecentOrStale() {
        let live = LiveHeartSummary.make(samples: Self.samples([(30, 72)]), now: T.now, resting: 58, calendar: T.calendar)
        let recent = LiveHeartSummary.make(samples: Self.samples([(12.0 * 60, 72)]), now: T.now, resting: 58, calendar: T.calendar)
        let stale = LiveHeartSummary.make(samples: Self.samples([(3.0 * 3600, 72)]), now: T.now, resting: 58, calendar: T.calendar)
        let none = LiveHeartSummary.make(samples: [], now: T.now, resting: 58, calendar: T.calendar)
        #expect(live.freshness == .live)
        #expect(recent.freshness == .recent)
        #expect(stale.freshness == .stale)
        #expect(none.freshness == .none && none.bpm == nil)
    }

    @Test func summaryTracksLatestRangeAndDropsImplausibleReadings() {
        let s = LiveHeartSummary.make(samples: Self.samples([(10, 150), (600, 95), (1200, 62), (1800, 400), (2400, 5)]),
                                      now: T.now, resting: 60, calendar: T.calendar)
        #expect(s.bpm == 150)
        #expect(s.minToday == 62)
        #expect(s.maxToday == 150)
        #expect(s.zone == .hard)
        #expect(s.aboveResting == 90)
        #expect(s.lastHour.count == 3)
        #expect(s.lastHour.first?.bpm == 62) // oldest first
    }

    @Test func waveformIsPeriodicWithTheRSpikeAndLubTogether() {
        #expect(abs(HeartWaveform.ecg(phase: 0.31) - HeartWaveform.ecg(phase: 1.31)) < 1e-9)
        let peak = stride(from: 0.0, to: 1.0, by: 0.005).max { HeartWaveform.ecg(phase: $0) < HeartWaveform.ecg(phase: $1) }!
        #expect(abs(peak - HeartWaveform.lubPhase) < 0.01)
        let thumpPeak = stride(from: 0.0, to: 1.0, by: 0.005).max { HeartWaveform.thump(phase: $0) < HeartWaveform.thump(phase: $1) }!
        #expect(abs(thumpPeak - HeartWaveform.lubPhase) < 0.01)
        #expect(HeartWaveform.thump(phase: 0.9) < 0.05) // rests between beats
        #expect(HeartWaveform.thump(phase: HeartWaveform.dubPhase) > 0.5)
    }
}
