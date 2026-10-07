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
    @State private var selectedMuscle: String?
    @State private var focusedNoteID: String?
    @State private var scrubDay: Double?
    @State private var editing: HealthEvent?
    @State private var showRegions = false
    @State private var visible = false

    var history: HealthHistory? { app.history }
    var notes: [HealthEvent] { history?.bodyNotes ?? [] }
    var today: LocalDate { LocalDate(AppClock.now(), calendar: .current) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    stage
                    regionPanel
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
            }
            .onDisappear { visible = false }
            .onChange(of: router.bodyFocusNoteID) { _, _ in focusFromRouter() }
            .onChange(of: markerKey) { _, _ in syncMarkers() }
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
                Text("Drag to turn · pinch to zoom · tap a region").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
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
                selectedMuscle = muscle?.name
                focusedNoteID = nil
            }
            controller?.highlight(region, muscle: muscle)
        }
        controller.onMarker = { id in if let n = notes.first(where: { $0.id == id }) { focus(n) } }
        if let l = UserDefaults.standard.string(forKey: "BlithBodyLayer").flatMap(BodyLayer.init(rawValue:)) { layer = l }
        controller.setLayer(layer)
        if UserDefaults.standard.object(forKey: "BlithBodyYaw") != nil {
            controller.setYaw(Float(UserDefaults.standard.double(forKey: "BlithBodyYaw")) * .pi / 180, animated: false)
        }
        syncMarkers()
    }

    func syncMarkers() {
        controller?.setMarkers(visibleNotes, focused: focusedNoteID, today: today)
    }

    @ViewBuilder
    var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0x122044), Color(hex: 0x080B10)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 380))
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
                                .background(Capsule().fill(layer == l ? (l == .muscle ? Palette.coral : Palette.cyan) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(layer == l ? .isSelected : [])
                    }
                }
                .padding(3)
                .glassSurface(Capsule())
                Spacer()
                Button { showRegions = true } label: {
                    Image(systemName: "list.bullet").font(Typo.geist(15, .semibold, relativeTo: .subheadline)).frame(width: 38, height: 38)
                }
                .foregroundStyle(Palette.ink)
                .glassSurface(Circle(), interactive: true)
                .accessibilityLabel("Body regions list")
            }
            Spacer()
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
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: layer == .muscle && selectedMuscle != nil ? "Muscle · \(region.displayName)" : "Region", icon: "bl.bodynote",
                                color: layer == .muscle ? Palette.coral : Palette.cyan)
                        Text(layer == .muscle ? (selectedMuscle ?? region.displayName) : region.displayName)
                            .font(Typo.title).foregroundStyle(Palette.ink)
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
            .card(tone: .tinted(layer == .muscle ? Palette.coral : Palette.cyan))
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
