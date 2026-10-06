import BlithCore
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false
    @State private var goalWeightText = ""
    @State private var customKey = ""
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system.rawValue

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $app.profile.name)
                        .textContentType(.givenName)
                        .onSubmit { app.profileChanged() }
                } header: {
                    Text("You")
                } footer: {
                    Text("Used only for the greeting. Never sent to the AI provider.")
                }

                Section("Priorities") {
                    ForEach(UserGoal.allCases) { goal in
                        Toggle(isOn: Binding(get: { app.profile.goals.contains(goal) },
                                             set: { on in
                                                 if on { app.profile.goals.insert(goal) } else { app.profile.goals.remove(goal) }
                                                 app.profileChanged()
                                             })) {
                            Label(goal.title, systemImage: goal.symbol)
                        }
                    }
                }

                Section("Preferences") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Units", selection: $app.profile.units) {
                        Text("Metric").tag(UnitSystem.metric)
                        Text("Imperial").tag(UnitSystem.imperial)
                    }
                    .onChange(of: app.profile.units) { _, _ in app.profileChanged() }
                    Toggle("Daily step goal", isOn: Binding(get: { app.profile.dailyStepGoal != nil },
                                                            set: { app.profile.dailyStepGoal = $0 ? 8000 : nil; app.profileChanged() }))
                    if let goal = app.profile.dailyStepGoal {
                        Stepper("\(Fmt.int(Double(goal))) steps", value: Binding(get: { goal }, set: { app.profile.dailyStepGoal = $0; app.profileChanged() }),
                                in: 2000...25000, step: 500)
                    }
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        TextField(app.profile.units == .metric ? "kg" : "lb", text: $goalWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .onSubmit(saveGoalWeight)
                    }
                    Picker("Week starts on", selection: $app.profile.firstWeekday) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }
                    .onChange(of: app.profile.firstWeekday) { _, _ in app.profileChanged() }
                }

                dataSection
                aiSection

                Section {
                    Link("Privacy policy", destination: AppConfig.privacyPolicyURL)
                    Button("Delete all Blith data", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Your health history is stored on this iPhone, encrypted while your device is locked. Deleting removes Blith's copy and settings; it doesn't change anything in Apple Health.")
                }

                Section {
                    LabeledContent("Version", value: AppConfig.version)
                } footer: {
                    Text("Blith describes patterns in your own data. It is not a medical device and does not provide diagnoses. Talk to a clinician about symptoms or health concerns.")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveGoalWeight()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let kg = app.profile.goalWeightKg {
                    goalWeightText = Fmt.decimal(app.profile.units == .metric ? kg : kg * 2.204_622_6)
                }
            }
            .confirmationDialog("Delete all Blith data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    Task { await app.deleteAllData() }
                }
            } message: {
                Text("This removes your imported history, settings and conversations from Blith.")
            }
        }
    }

    func saveGoalWeight() {
        let trimmed = goalWeightText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty {
            app.profile.goalWeightKg = nil
        } else if let v = Double(trimmed), v > 20 {
            app.profile.goalWeightKg = app.profile.units == .metric ? v : v / 2.204_622_6
        }
        app.profileChanged()
    }

    // MARK: Data

    @ViewBuilder
    var dataSection: some View {
        Section {
            if app.isDemo {
                Label("Showing sample data", systemImage: "flask").foregroundStyle(Palette.warm)
                Picker("Sample scenario", selection: Binding(get: {
                    if case .demo(let s)? = Persistence.dataMode { return s }
                    return DemoScenario.balanced
                }, set: { s in Task { await app.useDemo(s) } })) {
                    ForEach(DemoScenario.allCases) { Text($0.title).tag($0) }
                }
                if app.healthKitAvailable {
                    Button("Use my Apple Health data") { Task { await app.switchToAppleHealth() } }
                }
            } else {
                LabeledContent("Source", value: "Apple Health")
                ForEach(HealthCategory.allCases) { category in
                    let connected = Persistence.connectedCategories.contains(category)
                    HStack {
                        Text(category.title)
                        Spacer()
                        if connected {
                            Text("Requested").foregroundStyle(Palette.secondaryInk)
                        } else {
                            Button("Connect") { Task { await app.connectMore([category]) } }
                        }
                    }
                }
                Button("Explore with sample data") { Task { await app.useDemo(.balanced) } }
            }
            NavigationLink("Sources and coverage") { SourcesView() }
            NavigationLink("Widgets") { WidgetGalleryView() }
            HStack {
                if let last = app.history?.sync.lastSync {
                    Text("Last updated \(last.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Palette.secondaryInk)
                } else {
                    Text("Not synced yet").foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
                if app.isSyncing { ProgressView() } else {
                    Button("Sync now") { Task { await app.refresh(force: true) } }
                }
            }
            if let error = app.history?.sync.lastError {
                Text(error).font(Typo.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Connected data")
        } footer: {
            Text("Apple Health doesn't tell apps which types you allowed. To review or revoke access: Settings › Health › Data Access & Devices › Blith.")
        }
    }

    // MARK: AI

    @ViewBuilder
    var aiSection: some View {
        Section {
            if AppConfig.aiConfigured {
                Toggle("AI answers in Ask", isOn: Binding(get: { Persistence.aiConsent == true }, set: { Persistence.aiConsent = $0 }))
                LabeledContent("Model", value: AppConfig.model)
            } else {
                Text("AI answers aren't configured in this build. Ask answers on this iPhone.").foregroundStyle(Palette.secondaryInk)
            }
            #if DEBUG
            SecureField("Developer: OpenRouter key", text: $customKey)
                .onSubmit { Keychain.write(customKey, account: "openrouter.apiKey") }
            #endif
        } header: {
            Text("AI assistant")
        } footer: {
            Text("When on, your question, the last few messages of the chat and the readings needed to answer (daily values, sleep, heart and body readings, your body notes, and the name of the device that recorded them) are sent through OpenRouter to an AI model. When off, Ask answers on this iPhone.")
        }
    }
}

/// Where each metric comes from, and its data state (available / no data / not connected /
/// unsupported / stale).
struct SourcesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if let h = app.history {
                let cal = Calendar.current
                let today = LocalDate(AppClock.now(), calendar: cal)
                ForEach([HealthMetric.steps, .distanceWalkingRunning, .weight], id: \.self) { metric in
                    if let shares = h.sources[metric], !shares.isEmpty {
                        let total = shares.reduce(0) { $0 + $1.value }
                        Section(metric == .weight ? "Weight readings" : "\(metric.displayName) · last 30 days") {
                            ForEach(shares.sorted { $0.value > $1.value }) { s in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(s.source.name)
                                        if let d = s.source.device { Text(d).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk) }
                                    }
                                    Spacer()
                                    Text(metric == .weight ? "\(Int(s.value))" : (total > 0 ? Fmt.percent(s.value / total) : "—"))
                                        .monospacedDigit().foregroundStyle(Palette.secondaryInk)
                                }
                            }
                        }
                    }
                }
                CompanionSyncSection(app: .huawei, status: app.huaweiSync)
                Section {
                    ForEach(HealthMetric.allCases, id: \.self) { metric in
                        let state = h.availability(metric, today: today, calendar: cal)
                        HStack {
                            Text(metric.displayName)
                            Spacer()
                            Label(label(state), systemImage: symbol(state))
                                .font(Typo.geist(15, relativeTo: .subheadline))
                                .foregroundStyle(state == .available ? Palette.accent : .secondary)
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Coverage")
                } footer: {
                    Text("Apple Health merges overlapping iPhone and Apple Watch samples before totals are calculated, so steps aren't double counted. Blith keeps where each reading came from.")
                }
            } else {
                Text("No data connected yet.").foregroundStyle(Palette.secondaryInk)
            }
        }
        .navigationTitle("Sources")
    }

    func label(_ s: MetricAvailability) -> String {
        switch s {
        case .available: "Available"
        case .noData: "No data"
        case .notAuthorized: "Not connected"
        case .unsupported: "Not recorded"
        case .stale: "Out of date"
        }
    }

    func symbol(_ s: MetricAvailability) -> String {
        switch s {
        case .available: "checkmark.circle.fill"
        case .noData: "circle.dashed"
        case .notAuthorized: "lock"
        case .unsupported: "nosign"
        case .stale: "clock.badge.exclamationmark"
        }
    }
}
