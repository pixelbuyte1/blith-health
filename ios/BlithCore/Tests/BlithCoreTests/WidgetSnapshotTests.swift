import Foundation
import Testing
@testable import BlithCore

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    @Test func mirrorsTheTodaySnapshotAndRoundTrips() async throws {
        let provider = MockHealthProvider(scenario: .balanced, now: { T.now }, huaweiLag: 20 * 3600)
        let engine = SyncEngine(provider: provider, calendar: T.calendar, now: { T.now })
        var h = HealthHistory(origin: .demo(.balanced))
        h.requestedCategories = Set(HealthCategory.allCases)
        h = try await engine.initialImport(into: h)
        let snap = HealthSnapshot.build(history: h, profile: UserProfile(), now: T.now, calendar: T.calendar)
        let companion = CompanionSync.status(.huawei, history: h, now: T.now, calendar: T.calendar)
        let w = WidgetSnapshot(snapshot: snap, companion: companion, isSample: true)

        #expect(w.readiness == snap.readiness.score)
        #expect(w.readinessWeek.count == 7)
        #expect(w.readinessWeek.last == snap.readiness.score)
        #expect(w.sleepScore == snap.sleepScore?.score)
        #expect(w.steps == snap.todaySteps)
        #expect(w.companionName == "Huawei Health")
        #expect(w.isCurrent(at: T.now, calendar: T.calendar))
        #expect(!w.isCurrent(at: T.now.addingTimeInterval(12 * 3600), calendar: T.calendar))

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(w))
        #expect(decoded == w)
    }

    @Test func paceChangeNeedsAUsualValue() {
        var w = WidgetSnapshot.preview(now: T.now, calendar: T.calendar)
        #expect(abs((w.paceChange ?? 0) - (6_420.0 / 5_710 - 1)) < 1e-9)
        w.usualStepsByNow = nil
        #expect(w.paceChange == nil)
    }
}
