import BlithCore
import Foundation
import Observation
import SwiftUI
import WidgetKit

/// Which provider feeds the app. Demo is explicit and always labelled; it never silently
/// replaces real data.
enum DataMode: Equatable {
    case appleHealth
    case demo(DemoScenario)

    var origin: DataOrigin {
        switch self {
        case .appleHealth: .appleHealth
        case .demo(let s): .demo(s)
        }
    }

    var storageValue: String {
        switch self {
        case .appleHealth: "appleHealth"
        case .demo(let s): "demo:\(s.rawValue)"
        }
    }

    init?(storageValue: String) {
        if storageValue == "appleHealth" { self = .appleHealth; return }
        guard storageValue.hasPrefix("demo:"), let s = DemoScenario(rawValue: String(storageValue.dropFirst(5))) else { return nil }
        self = .demo(s)
    }

    var isDemo: Bool { if case .demo = self { true } else { false } }
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case launching, onboarding, importing, ready }

    var phase: Phase = .launching
    var profile: UserProfile { didSet { Persistence.saveProfile(profile) } }
    private(set) var mode: DataMode?
    private(set) var history: HealthHistory?
    private(set) var snapshot: HealthSnapshot?
    var importProgress: SyncProgress?
    var isSyncing = false
    var errorMessage: String?
    private(set) var engagement: Engagement = Persistence.loadEngagement()
    private(set) var achievements: [Achievement] = []

    let router = AppRouter()
    let ask = AskModel()
    let healthKit = AppleHealthProvider()
    let liveHeart = LiveHeartRate()
    private let store = LocalHealthStore(directory: LocalHealthStore.defaultDirectory())

    init() {
        profile = Persistence.loadProfile() ?? UserProfile(units: Locale.current.measurementSystem == .us ? .imperial : .metric,
                                                            firstWeekday: Calendar.current.firstWeekday)
    }

    var healthKitAvailable: Bool { healthKit.isAvailable }
    var isDemo: Bool { mode?.isDemo ?? false }

    // MARK: Lifecycle

    func start() async {
        LaunchOptions.applyIfPresent(to: self)
        checkIn()
        guard Persistence.onboardingComplete, let mode = Persistence.dataMode else {
            phase = .onboarding
            return
        }
        self.mode = mode
        if let saved = await store.load(mode.origin), saved.sync.initialImportCompleted != nil {
            history = saved
            await rebuildSnapshot()
            phase = .ready
            // Screenshot runs relaunch within seconds; force a sync so demo-only state is applied.
            await refresh(force: LaunchOptions.huaweiLag != nil)
        } else {
            await runImport(categories: Persistence.connectedCategories)
        }
        await LaunchOptions.applyAfterLaunch(to: self)
    }

    func provider(for mode: DataMode) -> any HealthDataProvider {
        switch mode {
        case .appleHealth:
            return healthKit
        case .demo(let s):
            return MockHealthProvider(scenario: s, now: { AppClock.now() }, huaweiLag: LaunchOptions.huaweiLag)
        }
    }

    // MARK: Connecting

    /// Ask HealthKit for the chosen categories, then import. Finishing the system sheet does
    /// not mean access was granted; the app finds out from what the queries return.
    func connectAppleHealth(categories: Set<HealthCategory>) async {
        errorMessage = nil
        do {
            try await healthKit.requestAuthorization(for: categories)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        Persistence.connectedCategories = categories
        mode = .appleHealth
        Persistence.dataMode = .appleHealth
        Task { await runImport(categories: categories) }
    }

    func useDemo(_ scenario: DemoScenario) async {
        mode = .demo(scenario)
        Persistence.dataMode = .demo(scenario)
        await runImport(categories: Set(HealthCategory.allCases))
    }

    func finishOnboarding() {
        Persistence.onboardingComplete = true
        phase = snapshot != nil && !isImporting ? .ready : .importing
    }

    var isImporting: Bool { importProgress != nil && importProgress?.stage != .done }

    func runImport(categories: Set<HealthCategory>) async {
        guard let mode else { return }
        let provider = provider(for: mode)
        var h = await store.load(mode.origin) ?? HealthHistory(origin: mode.origin)
        h.requestedCategories = categories
        importProgress = SyncProgress(stage: .connecting, fraction: 0.01, detail: "Starting")
        let engine = SyncEngine(provider: provider, calendar: .current, now: { AppClock.now() })
        do {
            let result = try await engine.initialImport(into: h) { progress in
                Task { @MainActor in self.importProgress = progress }
            }
            h = result
            if mode.isDemo, h.events.isEmpty, case .demo(.balanced) = mode {
                h.events = DemoNotes.make(today: LocalDate(AppClock.now(), calendar: .current), now: AppClock.now())
            }
            try? await store.save(h)
            history = h
            importProgress = SyncProgress(stage: .analyzing, fraction: 0.97, detail: "Calculating your baselines")
            await rebuildSnapshot()
            importProgress = SyncProgress(stage: .done, fraction: 1, detail: "Ready")
            if Persistence.onboardingComplete { phase = .ready }
        } catch {
            h.sync.status = .failed
            h.sync.lastError = error.localizedDescription
            history = h
            errorMessage = error.localizedDescription
            importProgress = nil
            await rebuildSnapshot()
            if Persistence.onboardingComplete { phase = .ready }
        }
    }

    /// Incremental sync; cheap and idempotent. Called on foreground and pull-to-refresh.
    func refresh(force: Bool = false) async {
        guard let mode, var h = history, !isSyncing, !isImporting else { return }
        if !force, let last = h.sync.lastSync, AppClock.now().timeIntervalSince(last) < 120 { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            h = try await SyncEngine(provider: provider(for: mode), calendar: .current, now: { AppClock.now() }).incrementalSync(h)
            try? await store.save(h)
            history = h
            await rebuildSnapshot()
        } catch {
            h.sync.status = .failed
            h.sync.lastError = error.localizedDescription
            history = h
        }
    }

    func rebuildSnapshot() async {
        guard let h = history else { snapshot = nil; achievements = []; return }
        let profile = profile
        let engagement = engagement
        let result = await Task.detached(priority: .userInitiated) { () -> (HealthSnapshot, [Achievement]) in
            let s = HealthSnapshot.build(history: h, profile: profile, now: AppClock.now(), calendar: .current)
            let a = AchievementEngine.evaluate(history: h, engagement: engagement, today: s.ctx.today,
                                               threshold: HealthAnalytics(s.ctx).activeThreshold())
            return (s, a)
        }.value
        snapshot = result.0
        achievements = result.1
        publishWidgets(result.0)
    }

    /// Hands the new numbers to the Home and Lock Screen widgets.
    func publishWidgets(_ s: HealthSnapshot) {
        WidgetStore.save(WidgetSnapshot(snapshot: s, companion: huaweiSync, isSample: isDemo))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Engagement

    var streak: CheckInStreak { CheckInStreak.compute(engagement.checkIns, today: LocalDate(AppClock.now(), calendar: .current)) }

    /// One check-in per day the app is opened. Gentle: missing a day never removes anything.
    func checkIn() {
        let today = LocalDate(AppClock.now(), calendar: .current)
        guard !engagement.checkIns.contains(today) else { return }
        engagement.checkIns.insert(today)
        Persistence.saveEngagement(engagement)
    }

    func recordQuestion() {
        engagement.questionsAsked += 1
        Persistence.saveEngagement(engagement)
    }

    // MARK: Body notes

    func saveNote(_ note: HealthEvent) async {
        guard var h = history else { return }
        var n = note
        n.updatedAt = h.events.contains { $0.id == note.id } ? AppClock.now() : nil
        h.upsert(n)
        history = h
        try? await store.save(h)
        await rebuildSnapshot()
    }

    func deleteNote(id: String) async {
        guard var h = history else { return }
        h.deleteNote(id: id)
        history = h
        try? await store.save(h)
        await rebuildSnapshot()
    }

    func profileChanged() {
        Task { await rebuildSnapshot() }
    }

    // MARK: Settings actions

    func connectMore(_ categories: Set<HealthCategory>) async {
        let all = Persistence.connectedCategories.union(categories)
        do { try await healthKit.requestAuthorization(for: all) } catch { errorMessage = error.localizedDescription; return }
        Persistence.connectedCategories = all
        if mode == .appleHealth {
            history?.requestedCategories = all
            await runImport(categories: all)
        }
    }

    func switchToAppleHealth() async {
        await connectAppleHealth(categories: Persistence.connectedCategories.isEmpty ? [.movement] : Persistence.connectedCategories)
    }

    func deleteAllData() async {
        await store.deleteAll()
        Persistence.reset()
        WidgetStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        history = nil
        snapshot = nil
        mode = nil
        importProgress = nil
        engagement = Engagement()
        achievements = []
        ask.clear()
        router.reset()
        phase = .onboarding
    }
}

// MARK: - Persistence of small settings

enum Persistence {
    private static let d = UserDefaults.standard

    static var onboardingComplete: Bool {
        get { d.bool(forKey: "onboardingComplete") }
        set { d.set(newValue, forKey: "onboardingComplete") }
    }

    static var dataMode: DataMode? {
        get { d.string(forKey: "dataMode").flatMap(DataMode.init(storageValue:)) }
        set { d.set(newValue?.storageValue, forKey: "dataMode") }
    }

    static var connectedCategories: Set<HealthCategory> {
        get { Set((d.stringArray(forKey: "connectedCategories") ?? []).compactMap(HealthCategory.init(rawValue:))) }
        set { d.set(newValue.map(\.rawValue).sorted(), forKey: "connectedCategories") }
    }

    /// nil = not asked yet.
    static var aiConsent: Bool? {
        get { d.object(forKey: "aiConsent") as? Bool }
        set { d.set(newValue, forKey: "aiConsent") }
    }

    static func loadProfile() -> UserProfile? {
        d.data(forKey: "profile").flatMap { try? JSONDecoder().decode(UserProfile.self, from: $0) }
    }

    static func saveProfile(_ p: UserProfile) {
        d.set(try? JSONEncoder().encode(p), forKey: "profile")
    }

    static func loadEngagement() -> Engagement {
        d.data(forKey: "engagement").flatMap { try? JSONDecoder().decode(Engagement.self, from: $0) } ?? Engagement()
    }

    static func saveEngagement(_ e: Engagement) {
        d.set(try? JSONEncoder().encode(e), forKey: "engagement")
    }

    static func reset() {
        for key in ["onboardingComplete", "dataMode", "connectedCategories", "aiConsent", "profile", "engagement"] { d.removeObject(forKey: key) }
    }
}
