import Foundation
import Testing
@testable import BlithCore

@Suite("Companion app sync")
struct CompanionSyncTests {
    func history(latest: [HealthMetric: Date]) -> HealthHistory {
        var h = T.history(steps: T.constant(6000, days: 0...10))
        h.sourceRecency["huawei"] = SourceRecency(app: .huawei, latest: latest, checkedAt: T.now)
        return h
    }

    @Test func noCompanionMeansNoStatus() {
        #expect(CompanionSync.status(.huawei, history: T.history(steps: [0: 100]), now: T.now, calendar: T.calendar) == nil)
    }

    @Test func freshnessFollowsTheNewestSample() throws {
        let hour: TimeInterval = 3600
        let current = try #require(CompanionSync.status(.huawei, history: history(latest: [.steps: T.now.addingTimeInterval(-2 * hour)]), now: T.now, calendar: T.calendar))
        #expect(current.freshness == .current)

        // Sleep from this morning is old, but steps from an hour ago mean the link is working.
        let mixed = history(latest: [.sleepDuration: T.now.addingTimeInterval(-20 * hour), .steps: T.now.addingTimeInterval(-hour)])
        let status = try #require(CompanionSync.status(.huawei, history: mixed, now: T.now, calendar: T.calendar))
        #expect(status.freshness == .current)
        #expect(status.arriving.first?.metric == .steps)

        let behind = try #require(CompanionSync.status(.huawei, history: history(latest: [.steps: T.now.addingTimeInterval(-13 * hour)]), now: T.now, calendar: T.calendar))
        #expect(behind.freshness == .behind)

        let stopped = try #require(CompanionSync.status(.huawei, history: history(latest: [.steps: T.now.addingTimeInterval(-4 * 86_400)]), now: T.now, calendar: T.calendar))
        #expect(stopped.freshness == .stopped)
        #expect(stopped.lastSync == T.now.addingTimeInterval(-4 * 86_400))
    }

    @Test func missingListsOnlyMetricsNothingDelivers() throws {
        let status = try #require(CompanionSync.status(.huawei, history: history(latest: [.restingHeartRate: T.now]), now: T.now, calendar: T.calendar))
        // Steps arrive from another source (the iPhone), so they are not missing.
        #expect(!status.missing.contains(.steps))
        #expect(!status.missing.contains(.restingHeartRate))
        #expect(status.missing.contains(.hrv))
        #expect(status.missing.contains(.sleepDuration))
    }

    @Test func recencySurvivesMergeAndDecoding() throws {
        var a = ProviderBatch()
        a.sourceRecency["huawei"] = SourceRecency(app: .huawei, latest: [.steps: T.now.addingTimeInterval(-7200)], checkedAt: T.now)
        var b = ProviderBatch()
        b.sourceRecency["huawei"] = SourceRecency(app: .huawei, latest: [.steps: T.now], checkedAt: T.now)
        let merged = SourceMerger.merge([a, b])
        #expect(merged.sourceRecency["huawei"]?.lastSeen == T.now)

        let h = history(latest: [.steps: T.now])
        let decoded = try JSONDecoder().decode(HealthHistory.self, from: JSONEncoder().encode(h))
        #expect(decoded.sourceRecency["huawei"]?.latest[.steps] == T.now)
    }

    @Test func agoReadsPlainly() {
        #expect(Fmt.ago(T.now.addingTimeInterval(-30), now: T.now) == "just now")
        #expect(Fmt.ago(T.now.addingTimeInterval(-25 * 60), now: T.now) == "25 min ago")
        #expect(Fmt.ago(T.now.addingTimeInterval(-3700), now: T.now) == "1 hour ago")
        #expect(Fmt.ago(T.now.addingTimeInterval(-14 * 3600), now: T.now) == "14 hours ago")
        #expect(Fmt.ago(T.now.addingTimeInterval(-3 * 86_400), now: T.now) == "3 days ago")
    }

    @Test func huaweiSourcesAreRecognised() {
        #expect(CompanionApp.matching(SourceRef(provider: .appleHealth, name: "Huawei Health", identifier: "com.huawei.iossporthealth")) == .huawei)
        #expect(CompanionApp.matching(T.source) == nil)
    }
}
