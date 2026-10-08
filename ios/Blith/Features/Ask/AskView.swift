import BlithCore
import SwiftUI

struct AskView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @FocusState private var focused: Bool
    @State private var showTags = false

    static let suggestions: [(String, String)] = [
        ("What's my readiness today, and why?", "bl.readiness"), ("How have I been walking?", "bl.steps"),
        ("Why was my walking lower last Tuesday?", "bl.calendar"),
        ("Show my sleep last night.", "bl.sleep"), ("How has my weight changed?", "bl.weight"),
        ("What changed recently?", "bl.sparkle"), ("Show my body notes.", "bl.bodynote"),
    ]

    var body: some View {
        let ask = app.ask
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xl) {
                        askHeader(responding: ask.isResponding)
                        if ask.messages.isEmpty {
                            emptyState
                        }
                        ForEach(ask.messages) { message in
                            MessageView(message: message) { link in router.open(link, snapshot: app.snapshot) }
                                .id(message.id)
                        }
                        if ask.isResponding {
                            HStack(spacing: Space.s) {
                                AssistantOrb(active: true, size: 30)
                                Text(ask.progress ?? "Thinking").font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                                    .contentTransition(.opacity)
                            }
                            .id("progress")
                            .accessibilityElement(children: .combine)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.l)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: ask.messages.count) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: ask.isResponding) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .blithBackground(wash: Palette.cyan.opacity(0.12))
            .safeAreaInset(edge: .bottom) { composer }
            // Like Today, Activity and Body: no empty bar above the title. New chat lives in the header.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: Binding(get: { ask.pendingQuestion != nil },
                                        set: { if !$0 && ask.pendingQuestion != nil { ask.resolveConsent(false, app: app) } })) {
                AIConsentSheet { allowed in ask.resolveConsent(allowed, app: app) }
            }
        }
    }

    func askHeader(responding: Bool) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: "Your health, explained", icon: "bl.sparkle", color: Palette.cyan)
                    if app.isDemo { SampleDataBanner() }
                }
                Text("Ask Blith").font(Typo.pageTitle).foregroundStyle(Palette.ink)
            }
            Spacer()
            if app.ask.messages.isEmpty {
                AssistantOrb(active: responding, size: 54)
            } else {
                Button { app.ask.clear() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .glassButton()
                .buttonBorderShape(.circle)
                .accessibilityLabel("New conversation")
            }
        }
    }

    var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Ask about your walking, sleep, weight or body notes. Every answer is computed from your records and comes with the evidence behind it.")
                .font(Typo.story)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                Text("TRY ASKING").font(Typo.eyebrow).tracking(0.9).foregroundStyle(Palette.tertiaryInk)
                    .padding(.horizontal, Space.l).padding(.top, Space.m).padding(.bottom, Space.xs)
                ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { i, s in
                    Button {
                        Task { await app.ask.send(s.0, app: app) }
                    } label: {
                        HStack(spacing: Space.m) {
                            SignalGlyph(symbol: s.1, tint: Palette.signal, size: 32)
                            Text(s.0).font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: Space.s)
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiaryInk)
                        }
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < Self.suggestions.count - 1 {
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, Space.l + 44)
                    }
                }
            }
            .card(padding: 0)
            if !AppConfig.aiConfigured || Persistence.aiConsent == false {
                Label("Answers are generated on this iPhone.", systemImage: "iphone")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    var composer: some View {
        @Bindable var ask = app.ask
        let model = ask.currentModel
        let usesAI = AppConfig.aiConfigured && Persistence.aiConsent != false
        return VStack(spacing: Space.s) {
            if showTags {
                AskTagPanel(tagged: ask.tags) { tag in
                    app.ask.toggleTag(tag)
                    showTags = false
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: Space.m) {
                if !ask.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.xs) {
                            ForEach(ask.tags) { tag in
                                AskTagChip(tag: tag) { app.ask.toggleTag(tag) }
                            }
                        }
                    }
                }
                TextField("Ask about your health…", text: $ask.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { submit() }
                    .padding(.horizontal, Space.xs)
                HStack(spacing: Space.s) {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { showTags.toggle() }
                    } label: {
                        Text("@")
                            .font(Typo.geist(19, .semibold, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 38, height: 38)
                            .background(showTags ? Palette.accentSoft : Palette.raised, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showTags ? "Close tags" : "Tag a body part, sleep, heart rate or a day")
                    if usesAI {
                        AskModelToggle(selection: model) { app.ask.pickedModel = $0 }
                    }
                    Spacer(minLength: 0)
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .frame(width: 28, height: 28)
                    }
                    .glassButton(prominent: true)
                    .buttonBorderShape(.circle)
                    .disabled(ask.draft.trimmingCharacters(in: .whitespaces).isEmpty || ask.isResponding)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
            // Glass doesn't hit-test on iOS 26: make the whole field focus the text box.
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture { focused = true }
            if usesAI {
                Text("\(Text(model.name).foregroundStyle(Palette.signal)) · \(model.blurb)")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }

    func submit() {
        let text = app.ask.draft
        Task { await app.ask.send(text, app: app) }
    }
}

struct MessageView: View {
    let message: ChatMessage
    let open: (DeepLink) -> Void
    @State private var showEvidence = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: Space.xs) {
                    if let tags = message.tags, !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(Typo.mono(11, .medium))
                            .foregroundStyle(Palette.signal)
                    }
                    Text(message.text)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .font(Typo.body)
                .foregroundStyle(Palette.ink)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(message.text)")
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.s) {
                    SignalGlyph(symbol: "bl.sparkle", tint: Palette.cyan, size: 30)
                    Text(attributed(message.text))
                        .font(Typo.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                ForEach(message.blocks) { block in
                    ChatBlockView(block: block, open: open)
                }
                if let model = message.modelName, !message.isLocal {
                    Text("Answered by \(model)")
                        .font(Typo.mono(11, .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.leading, 30 + Space.s)
                }
                if !message.evidence.isEmpty {
                    WhyButton { showEvidence = true }
                }
            }
            .sheet(isPresented: $showEvidence) { AnswerEvidenceSheet(message: message) }
        }
    }

    func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// What an answer was computed from.
struct AnswerEvidenceSheet: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(message.evidence) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.label).font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                            Text(e.detail).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                        }
                    }
                } header: {
                    Text("Records used")
                } footer: {
                    Text(message.isLocal
                         ? "Answered on this iPhone from your records. Numbers are computed by Blith, not estimated."
                         : "Numbers were computed on this iPhone and only minimized summaries were sent to the AI model to phrase the answer.")
                }
                if !message.toolsUsed.isEmpty {
                    Section("Calculations run") {
                        ForEach(Array(Set(message.toolsUsed)).sorted(), id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).font(Typo.geist(15, relativeTo: .subheadline))
                        }
                    }
                }
                Section {
                    Text("Relationships between records are patterns, not causes. Blith doesn't diagnose.").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
            .navigationTitle("Why you're seeing this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Shown once before any question leaves the device. Declining keeps Ask fully on-device.
struct AIConsentSheet: View {
    let decide: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Palette.accent)
                    Text("Use AI to answer your questions?").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("To answer in conversation, Blith sends your question and the health readings needed to answer it to an AI model, through OpenRouter. You choose; you can change this any time in Profile.")
                    VStack(alignment: .leading, spacing: Space.m) {
                        point("checkmark.circle", "Sent: your question, the last few messages of this chat, and the readings it needs: daily or weekly values (up to 120 per measure), sleep, heart and body readings, and your body notes.")
                        point("exclamationmark.circle", "Readings can include the name of the device that recorded them, such as an Apple Watch name, which may contain your name. Location and contacts are never sent.")
                        point("checkmark.shield", "OpenRouter and the AI provider process it to write the answer. Blith doesn't use it for advertising.")
                        point("iphone", "Prefer not to? Ask still answers common questions on this iPhone.")
                    }
                    .font(Typo.geist(15, relativeTo: .subheadline))
                    Text("Blith is not a medical device and doesn't give diagnoses.").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                    VStack(spacing: Space.m) {
                        Button {
                            decide(true)
                        } label: { Text("Allow AI answers").font(Typo.geist(17, .semibold, relativeTo: .headline)).frame(maxWidth: .infinity) }
                            .glassButton(prominent: true)
                        Button {
                            decide(false)
                        } label: { Text("Keep answers on this iPhone").frame(maxWidth: .infinity) }
                            .glassButton()
                    }
                    .controlSize(.large)
                }
                .padding(Space.xxl)
            }
            .interactiveDismissDisabled()
        }
    }

    func point(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Palette.accent) }
    }
}


/// The assistant's mark: a small instrument ring that turns while it's working.
struct AssistantOrb: View {
    var active: Bool
    var size: CGFloat = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Calm intelligence, not a spinner: concentric light that breathes while Blith is working.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active || reduceMotion)) { tl in
            let t = active && !reduceMotion ? tl.date.timeIntervalSinceReferenceDate : 0
            let breath = 0.5 + 0.5 * sin(t * 1.6)
            ZStack {
                Circle().fill(RadialGradient(colors: [Palette.cyan.opacity(0.28 + 0.12 * breath), .clear], center: .center,
                                             startRadius: 0, endRadius: size * 0.62))
                Circle().strokeBorder(Palette.cyan.opacity(0.18 + 0.2 * breath), lineWidth: 1)
                    .scaleEffect(0.78 + 0.1 * breath)
                Circle().strokeBorder(Palette.signal.opacity(0.35), lineWidth: 1)
                    .scaleEffect(0.52)
                Circle().fill(Palette.surface).frame(width: size * 0.42, height: size * 0.42)
                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                BLIcon(name: "bl.sparkle", size: size * 0.22).foregroundStyle(Palette.cyan)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
