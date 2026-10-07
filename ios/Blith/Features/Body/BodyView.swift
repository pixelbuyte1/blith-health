import BlithCore
import SwiftUI

// MARK: - Body tab

struct BodyView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var controller: BodySceneController?
    @State private var layer: BodyLayer = .skin
    @State private var selectedRegion: BodyRegion?
    @State private var selectedMuscle: Body3DModel.Muscle?
    @State private var focusedNoteID: String?
    @State private var scrubDay: Double?
    @State private var editing: HealthEvent?
    @State private var showRegions = false
    @State private var visible = false
    @State private var showCoach = false
    @State private var coachPoint: CGPoint?
    @State private var panelRequest = 0
    @AppStorage("BlithBodyStyle") private var styleRaw = AnatomyStyle.radiant.rawValue
    @AppStorage("BlithBodyCoachVisits") private var coachVisits = 0

    var style: AnatomyStyle { AnatomyStyle(rawValue: styleRaw) ?? .radiant }

    var history: HealthHistory? { app.history }
    var notes: [HealthEvent] { history?.bodyNotes ?? [] }
    var today: LocalDate { LocalDate(AppClock.now(), calendar: .current) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        header
                        stage
                        regionPanel.id("bodyPanel")
                        timeline
                        historyList
                        Text("3D figure and muscles derived from BodyParts3D (© The Database Center for Life Science, CC BY-SA 2.1 JP) and Z-Anatomy (CC BY-SA 4.0). For orientation and notes, not a medical atlas.")
                            .font(Typo.geist(11, relativeTo: .caption2)).foregroundStyle(Palette.tertiaryInk)
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.section)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                .blithBackground(wash: Palette.signal.opacity(0.14))
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $editing) { note in
                    BodyNoteEditor(note: note, isNew: !notes.contains { $0.id == note.id }) { saved in
                        Task { await app.saveNote(saved) }
                    } onDelete: { id in
                        Task { await app.deleteNote(id: id) }
                    }
                }
                .sheet(isPresented: $showRegions) { regionList }
                .onAppear {
                    visible = true
                    setUp()
                    focusFromRouter()
                    startCoachIfNeeded()
                }
                .onDisappear {
                    visible = false
                    showCoach = false
                }
                .onChange(of: router.bodyFocusNoteID) { _, _ in focusFromRouter() }
                .onChange(of: markerKey) { _, _ in syncMarkers() }
                .onChange(of: panelRequest) { _, _ in
                    withAnimation(Motion.respecting(reduceMotion)) { proxy.scrollTo("bodyPanel", anchor: .top) }
                }
                .sensoryFeedback(.selection, trigger: selectedMuscle?.id ?? selectedRegion?.rawValue)
            }
        }
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: "Body map · \(notes.filter { $0.isActive(on: today) }.count) open notes", icon: "bl.body", color: Palette.cyan)
                    if app.isDemo { SampleDataBanner() }
                }
                Text("Body").font(Typo.pageTitle).foregroundStyle(Palette.ink)
                Text("Drag to turn · pinch to zoom · tap a muscle").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            }
            Spacer()
            AvatarButton(name: app.profile.name) { router.sheet = .profile }
        }
        .padding(.top, Space.s)
    }

    // MARK: Stage

    /// Notes whose markers show at the scrubbed date (active then), plus the focused note.
    var visibleNotes: [HealthEvent] {
        let day = scrubDay.map { LocalDate(dayNumber: Int($0.rounded())) } ?? today
        return notes.filter { $0.bodyRegion != nil && ($0.isActive(on: day) || $0.id == focusedNoteID || ($0.date == day)) }
    }

    var markerKey: String { visibleNotes.map(\.id).joined(separator: ",") + "|" + (focusedNoteID ?? "") }

    func setUp() {
        if controller == nil, let model = Body3DModel.shared { controller = BodySceneController(model: model) }
        guard let controller else { return }
        controller.onSelect = { [weak controller] region, muscle in
            withAnimation(Motion.respecting(reduceMotion, Motion.snappy)) {
                selectedRegion = region
                selectedMuscle = muscle
                focusedNoteID = nil
            }
            controller?.highlight(region, muscle: muscle)
        }
        controller.onMarker = { id in if let n = notes.first(where: { $0.id == id }) { focus(n) } }
        controller.onInteract = {
            guard showCoach else { return }
            withAnimation(Motion.respecting(reduceMotion)) { showCoach = false }
        }
        if let l = UserDefaults.standard.string(forKey: "BlithBodyLayer").flatMap(BodyLayer.init(rawValue:)) { layer = l }
        controller.setStyle(style)
        controller.setLayer(layer)
        if UserDefaults.standard.object(forKey: "BlithBodyYaw") != nil {
            controller.setYaw(Float(UserDefaults.standard.double(forKey: "BlithBodyYaw")) * .pi / 180, animated: false)
        }
        syncMarkers()
    }

    func syncMarkers() {
        controller?.setMarkers(visibleNotes, focused: focusedNoteID, today: today)
    }

    /// The first three visits show how to use the figure. Any drag, pinch or tap retires the hint for
    /// that visit; "Got it" retires it for good.
    func startCoachIfNeeded() {
        guard controller != nil, coachVisits < 3, !showCoach, !LaunchOptions.isScripted else { return }
        coachVisits += 1
        coachPoint = nil
        withAnimation(Motion.respecting(reduceMotion)) { showCoach = true }
    }

    @ViewBuilder
    var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(RadialGradient(colors: [BodyChamber.centre, BodyChamber.middle, BodyChamber.edge],
                                     center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 380))
            GridBackdrop().opacity(0.5).clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            if let controller {
                BodySceneView(controller: controller, animate: visible && !reduceMotion && scenePhase == .active)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .transition(.opacity)
            } else {
                EmptyStateView(symbol: "bl.body", title: "3D model unavailable", message: "The body model couldn't be loaded on this device.")
                    .padding()
            }
            controls
            if showCoach {
                BodyCoachOverlay(point: coachPoint) {
                    coachVisits = 3
                    withAnimation(Motion.respecting(reduceMotion)) { showCoach = false }
                }
                .transition(.opacity)
                .task {
                    // Wait for the figure to be laid out before placing the tap hint on the chest.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    coachPoint = controller?.screenPoint(of: .chest)
                }
            }
        }
        .frame(height: 540)
        .environment(\.colorScheme, .dark)
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D body map")
    }

    var controls: some View {
        VStack {
            HStack(alignment: .top) {
                HStack(spacing: 2) {
                    ForEach(BodyLayer.allCases) { l in
                        Button {
                            layer = l
                            controller?.setLayer(l)
                        } label: {
                            Text(l.title.uppercased()).font(Typo.eyebrow).tracking(1)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .foregroundStyle(layer == l ? Palette.canvas : Palette.ink)
                                .background(Capsule().fill(layer == l ? (l == .muscle ? Palette.anatomy : Palette.cyan) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(layer == l ? .isSelected : [])
                    }
                }
                .padding(3)
                .glassSurface(Capsule())
                Spacer()
                if layer == .muscle {
                    Menu {
                        Picker("Anatomy style", selection: Binding(get: { style }, set: { new in
                            styleRaw = new.rawValue
                            controller?.setStyle(new)
                        })) {
                            ForEach(AnatomyStyle.allCases) { s in Text(s.title).tag(s) }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled").font(Typo.geist(15, .semibold, relativeTo: .subheadline)).frame(width: 38, height: 38)
                    }
                    .foregroundStyle(Palette.ink)
                    .glassSurface(Circle(), interactive: true)
                    .accessibilityLabel("Anatomy style, \(style.title)")
                }
                Button { showRegions = true } label: {
                    Image(systemName: "list.bullet").font(Typo.geist(15, .semibold, relativeTo: .subheadline)).frame(width: 38, height: 38)
                }
                .foregroundStyle(Palette.ink)
                .glassSurface(Circle(), interactive: true)
                .accessibilityLabel("Body regions list")
            }
            Spacer()
            if let region = selectedRegion, !showCoach {
                selectionChip(region)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: .bottom) {
                HStack(spacing: 2) {
                    viewButton("Front", yaw: 0)
                    viewButton("Side", yaw: -.pi / 2)
                    viewButton("Back", yaw: .pi)
                }
                .padding(3)
                .glassSurface(Capsule())
                Spacer()
                HStack(spacing: 0) {
                    Button { controller?.zoom(by: 1 / 1.35, animated: true) } label: { Image(systemName: "minus").frame(width: 38, height: 36) }
                        .accessibilityLabel("Zoom out")
                    Button {
                        controller?.reset()
                        selectedRegion = nil
                        selectedMuscle = nil
                        focusedNoteID = nil
                    } label: { Image(systemName: "scope").frame(width: 38, height: 36) }
                        .accessibilityLabel("Reset view")
                    Button { controller?.zoom(by: 1.35, animated: true) } label: { Image(systemName: "plus").frame(width: 38, height: 36) }
                        .accessibilityLabel("Zoom in")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.ink)
                .glassSurface(Capsule(), interactive: true)
            }
        }
        .padding(Space.m)
    }

    /// The selected part, floating just above the view controls so it's visible without scrolling.
    /// Tapping it scrolls to the full card with notes.
    func selectionChip(_ region: BodyRegion) -> some View {
        Button { panelRequest += 1 } label: {
            HStack(spacing: Space.m) {
                BodyPartGlyph(region: glyphRegion(region), size: 24)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.anatomy.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectionTitle(region)).font(Typo.cardTitle).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(chipDetail(region)).font(Typo.caption).foregroundStyle(Palette.secondaryInk).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.raised))
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.bottom, Space.s)
        .accessibilityHint("Shows notes and details below")
    }

    /// The muscle shown in the card: only on the muscle layer.
    var shownMuscle: Body3DModel.Muscle? { layer == .muscle ? selectedMuscle : nil }

    func glyphRegion(_ region: BodyRegion) -> BodyRegion { shownMuscle?.bodyRegion ?? region }

    func selectionTitle(_ region: BodyRegion) -> String { shownMuscle?.name ?? region.displayName }

    /// "Chest, left side" for a muscle; nil for a region.
    var muscleWhere: String? {
        guard let m = shownMuscle else { return nil }
        let group = MuscleGuide.entry(for: m)?.group ?? m.bodyRegion?.displayName ?? "Muscle"
        return MuscleGuide.sideLabel(m).map { "\(group), \($0.lowercased())" } ?? group
    }

    func chipDetail(_ region: BodyRegion) -> String {
        if let m = shownMuscle {
            return [muscleWhere, MuscleGuide.entry(for: m)?.action].compactMap { $0 }.joined(separator: " · ")
        }
        let count = notes.filter { $0.bodyRegion == region }.count
        return count == 0 ? "No notes here yet" : "\(count) \(count == 1 ? "note" : "notes") here"
    }

    func viewButton(_ title: String, yaw: Float) -> some View {
        Button { controller?.setYaw(yaw) } label: {
            Text(title.uppercased()).font(Typo.eyebrow).tracking(1).padding(.horizontal, 10).padding(.vertical, 8)
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: Focus

    func focusFromRouter() {
        guard let id = router.bodyFocusNoteID, let note = notes.first(where: { $0.id == id }) else { return }
        focus(note)
        router.bodyFocusNoteID = nil
    }

    /// Turn toward the note's region, zoom to a useful framing, reveal the marker's date.
    func focus(_ note: HealthEvent) {
        if controller == nil { setUp() }
        focusedNoteID = note.id
        scrubDay = Double(note.date.dayNumber)
        guard let region = note.bodyRegion else { return }
        selectedRegion = region
        selectedMuscle = nil
        syncMarkers()
        controller?.focus(region, animated: !reduceMotion)
    }

    func focus(region: BodyRegion) {
        selectedRegion = region
        selectedMuscle = nil
        focusedNoteID = nil
        controller?.focus(region, animated: !reduceMotion)
    }

    // MARK: Region panel

    @ViewBuilder
    var regionPanel: some View {
        if let region = selectedRegion {
            let regionNotes = notes.filter { $0.bodyRegion == region }
            let tint = layer == .muscle ? Palette.anatomy : Palette.cyan
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    BodyPartGlyph(region: glyphRegion(region), size: 28, accent: tint)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Palette.raised))
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: shownMuscle != nil ? "Muscle · \(region.displayName)" : "Region", color: tint)
                        Text(selectionTitle(region))
                            .font(Typo.title).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let muscleWhere {
                            Text(muscleWhere).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                        }
                    }
                    Spacer()
                    Button {
                        selectedRegion = nil
                        selectedMuscle = nil
                        focusedNoteID = nil
                        controller?.reset()
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Palette.secondaryInk)
                            .frame(width: 30, height: 30).background(Circle().fill(Palette.raised))
                    }
                    .accessibilityLabel("Close region")
                }
                if let m = shownMuscle, let action = MuscleGuide.entry(for: m)?.action {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "What it does")
                        Text(action).font(Typo.body).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if regionNotes.isEmpty {
                    Text("No notes here yet.").font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                } else {
                    ForEach(regionNotes) { note in
                        NoteRow(note: note, today: today, focused: note.id == focusedNoteID) { focus(note) } onEdit: { editing = note }
                    }
                }
                HStack {
                    Button {
                        editing = HealthEvent(date: today, kind: .note, title: "", bodyRegion: region, createdAt: AppClock.now())
                    } label: {
                        Label("Add a note here", systemImage: "plus").font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                    }
                    .glassButton(prominent: true)
                    if let focused = regionNotes.first(where: { $0.id == focusedNoteID }) {
                        Button { router.open(.walkDay(focused.date), snapshot: app.snapshot) } label: {
                            Label("Activity that day", systemImage: "chart.bar").font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                        }
                        .glassButton()
                    }
                }
            }
            .card(tone: .tinted(tint))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Timeline

    @ViewBuilder
    var timeline: some View {
        if let first = notes.map(\.date).min() {
            let lower = Double(first.adding(days: -14).dayNumber)
            let upper = Double(today.dayNumber)
            let value = Binding(get: { scrubDay ?? upper }, set: { scrubDay = $0; focusedNoteID = nil })
            let day = LocalDate(dayNumber: Int((scrubDay ?? upper).rounded()))
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Eyebrow(text: "Timeline", icon: "bl.calendar", color: Palette.note)
                    Spacer()
                    Text(day == today ? "TODAY" : (Fmt.dayLabel(day) + ", \(day.year)").uppercased()).font(Typo.eyebrow).foregroundStyle(Palette.ink)
                }
                GeometryReader { geo in
                    ForEach(notes) { n in
                        let x = (Double(n.date.dayNumber) - lower) / max(1, upper - lower)
                        Capsule().fill(Palette.note).frame(width: 3, height: 12)
                            .position(x: geo.size.width * CGFloat(x), y: geo.size.height / 2)
                    }
                }
                .frame(height: 12)
                .allowsHitTesting(false)
                Slider(value: value, in: lower...upper, step: 1)
                    .tint(Palette.note)
                    .accessibilityValue(Fmt.dayLabel(day))
                Text("Markers show notes that were unresolved on this date. The figure itself doesn't change — Blith doesn't reconstruct your body for past dates.")
                    .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
            }
            .card()
        }
    }

    // MARK: History list

    var historyList: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Notes", subtitle: notes.isEmpty ? "Tap a region above to add your first note" : "Newest first by the date it happened",
                          trailing: "Add") {
                editing = HealthEvent(date: today, kind: .note, title: "", bodyRegion: selectedRegion, createdAt: AppClock.now())
            }
            if notes.isEmpty {
                EmptyStateView(symbol: "bl.bodynote", title: "No body notes yet",
                               message: "Keep a short record of things like a sore knee or a rolled ankle, with the date it happened. Blith shows them beside your activity, never as a diagnosis.")
            } else {
                VStack(spacing: Space.s) {
                    ForEach(notes) { note in
                        NoteRow(note: note, today: today, focused: note.id == focusedNoteID) { focus(note) } onEdit: { editing = note }
                    }
                }
            }
        }
    }

    var regionList: some View {
        NavigationStack {
            List {
                ForEach(BodyRegion.allCases.filter { $0 != .other }) { region in
                    Button {
                        showRegions = false
                        focus(region: region)
                    } label: {
                        HStack {
                            Text(region.displayName)
                            Spacer()
                            let count = notes.filter { $0.bodyRegion == region }.count
                            if count > 0 { Text("\(count) \(count == 1 ? "note" : "notes")").foregroundStyle(Palette.note) }
                        }
                    }
                    .foregroundStyle(Palette.ink)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Body regions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRegions = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Faint instrument grid behind the figure.
struct GridBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 28
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(p, with: .color(Palette.cobalt.opacity(0.12)), lineWidth: 0.5)
        }
        .mask(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 40, endRadius: 320))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Wraps glass buttons so they blend on iOS 26.
struct GlassEffectGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .padding(3)
            .glassSurface(Capsule())
    }
}

struct NoteRow: View {
    let note: HealthEvent
    let today: LocalDate
    var focused = false
    let onFocus: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onFocus) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(spacing: 0) {
                    Circle().fill(note.isActive(on: today) ? Palette.note : Palette.baseline).frame(width: 10, height: 10)
                        .padding(.top, 5)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title.isEmpty ? note.kindLabel : note.title).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                    Text("\(note.bodyRegion?.displayName ?? "General") · \(note.kindLabel)\(note.severity.map { " · " + ["mild", "moderate", "strong"][max(0, min(2, $0 - 1))] } ?? "")")
                        .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                    Text("Happened \(Fmt.dayLabel(note.date)), \(note.date.year) · written \(note.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(Typo.geist(11, relativeTo: .caption2)).foregroundStyle(Palette.secondaryInk)
                    if let r = note.resolvedDate {
                        Text("Resolved \(Fmt.shortDate(r))").font(.caption2.weight(.semibold)).foregroundStyle(Palette.sleep)
                    }
                    if note.isSample {
                        Text("Sample note").font(.caption2.weight(.semibold)).foregroundStyle(Palette.review)
                    }
                }
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil.circle").font(.title3).foregroundStyle(Palette.secondaryInk) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit note")
            }
            .padding(Space.m)
            .background(focused ? Palette.noteSoft : Palette.card, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(focused ? Palette.note.opacity(0.4) : Palette.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this note on the body")
    }
}

/// Add or edit a body note. The event date is when it happened; the entry date is kept separately.
struct BodyNoteEditor: View {
    @State var note: HealthEvent
    let isNew: Bool
    let onSave: (HealthEvent) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var resolved = false
    @State private var resolvedOn = Date()
    @State private var confirmDelete = false

    init(note: HealthEvent, isNew: Bool, onSave: @escaping (HealthEvent) -> Void, onDelete: @escaping (String) -> Void) {
        _note = State(initialValue: note)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened? (e.g. rolled my right ankle)", text: $note.title, axis: .vertical)
                    TextField("Details (optional)", text: Binding(get: { note.note ?? "" }, set: { note.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Your words stay as you wrote them. Blith won't turn a note into a diagnosis.")
                }
                Section("Where and what") {
                    Picker("Region", selection: Binding(get: { note.bodyRegion ?? .other }, set: { note.bodyRegion = $0 })) {
                        ForEach(BodyRegion.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Kind", selection: $note.kind) {
                        ForEach(HealthEvent.Kind.allCases, id: \.self) { k in
                            Text(HealthEvent(date: note.date, kind: k, title: "").kindLabel).tag(k)
                        }
                    }
                    Picker("How it felt", selection: Binding(get: { note.severity ?? 0 }, set: { note.severity = $0 == 0 ? nil : $0 })) {
                        Text("Not set").tag(0)
                        Text("Mild").tag(1)
                        Text("Moderate").tag(2)
                        Text("Strong").tag(3)
                    }
                }
                Section {
                    DatePicker("Happened on", selection: $date, in: ...AppClock.now(), displayedComponents: .date)
                    Toggle("Resolved", isOn: $resolved)
                    if resolved {
                        DatePicker("Resolved on", selection: $resolvedOn, in: date...AppClock.now().addingTimeInterval(1), displayedComponents: .date)
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text(isNew ? "Written today. The date it happened can be earlier." :
                            "Written \(note.createdAt.formatted(date: .abbreviated, time: .omitted)).")
                }
                if !isNew {
                    Section {
                        Button("Delete note", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New body note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var n = note
                        n.date = LocalDate(date, calendar: .current)
                        n.resolvedDate = resolved ? LocalDate(resolvedOn, calendar: .current) : nil
                        n.title = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        n.isSample = n.isSample && !isNew
                        onSave(n)
                        dismiss()
                    }
                    .disabled(note.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(note.id)
                    dismiss()
                }
            }
            .onAppear {
                date = note.date.startDate(in: .current)
                resolved = note.resolvedDate != nil
                resolvedOn = note.resolvedDate?.startDate(in: .current) ?? AppClock.now()
            }
        }
    }
}
