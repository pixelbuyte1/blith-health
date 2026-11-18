import BlithCore
import SwiftUI

@main
struct BlithApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.router)
                .tint(Palette.accent)
                .preferredColorScheme(AppearancePreference(rawValue: appearance)?.scheme)
                .task { await app.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, app.phase == .ready { app.checkIn(); Task { await app.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch app.phase {
            case .launching:
                Palette.canvas.ignoresSafeArea()
                    .overlay(SignalPulse(size: 72))
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .importing:
                ImportProgressView()
                    .transition(.opacity)
            case .ready:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.respecting(reduceMotion), value: app.phase)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var interruptedMessage: String {
        guard let walk = app.walks.interrupted?.walk else { return "" }
        return "A walk you started at \(WalkFormat.time(walk.start)) was still recording when Blith closed. Resume it, or save it as it was at \(WalkFormat.time(walk.end))."
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var walks = app.walks
        TabView(selection: $router.tab) {
            Tab("Today", image: "bl.today", value: AppTab.today) {
                TodayView()
            }
            Tab("Activity", image: "bl.activity", value: AppTab.walk) {
                WalkView()
            }
            Tab("Sleep", image: "bl.sleep", value: AppTab.sleep) {
                SleepView()
            }
            Tab("Body", image: "bl.body", value: AppTab.body) {
                BodyView()
            }
            Tab("Ask", image: "bl.ask", value: AppTab.ask) {
                AskView()
            }
        }
        .modifier(LiquidGlassTabBar())
        .sheet(item: $router.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(app)
                .environment(router)
        }
        .fullScreenCover(isPresented: $walks.isPresented) {
            WalkFlowView()
                .environment(app)
                .environment(router)
        }
        .task { app.walks.checkForInterruptedWalk() }
        .alert("Unfinished walk", isPresented: Binding(get: { app.walks.interrupted != nil && !app.walks.isPresented }, set: { _ in })) {
            Button("Resume walk") { app.walks.resumeInterrupted() }
            Button("Save it") { Task { await app.walks.finishInterrupted(app: app) } }
            Button("Discard", role: .destructive) { app.walks.discardInterrupted() }
        } message: {
            Text(interruptedMessage)
        }
    }
}

/// On iOS 26 the system tab bar is Liquid Glass; let it shrink while scrolling content.
private struct LiquidGlassTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct SheetHost: View {
    let sheet: AppRouter.Sheet
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var body: some View {
        switch sheet {
        case .profile:
            ProfileView()
        case .sleep:
            SleepView(standalone: true)
        case .weight:
            WeightDetailView()
        case .sources:
            NavigationStack { SourcesView() }
        case .readiness(let date):
            ReadinessDetailView(date: date)
        case .vital(let metric):
            VitalDetailView(metric: metric)
                .presentationDetents([.medium, .large])
        case .insight(let insight):
            InsightExplanationSheet(
                insight: insight,
                updated: app.history?.sync.lastSync,
                onAsk: { question in
                    router.tab = .ask
                    Task { await app.ask.send(question, app: app) }
                },
                onOpen: { link in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        router.open(link, snapshot: app.snapshot)
                    }
                })
            .presentationDetents([.medium, .large])
        }
    }
}
