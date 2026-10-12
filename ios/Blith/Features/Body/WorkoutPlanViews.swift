import BlithCore
import SwiftUI

/// Where the weekly training split is kept (on this iPhone only).
enum WorkoutPlanStore {
    static let key = "BlithWorkoutPlan"
}

/// Weekdays in display order, Monday first (1 = Sunday … 7 = Saturday).
private let weekOrder = [2, 3, 4, 5, 6, 7, 1]

/// Today's planned session on the Body screen: the groups glowing on the figure, a tick to mark it
/// done, and the last seven days. With no plan it invites the person to set one up.
struct WorkoutTodayCard: View {
    @Binding var planRaw: String
    let today: LocalDate
    var onEdit: () -> Void

    var plan: WorkoutPlan { WorkoutPlan.decode(planRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Eyebrow(text: "Today · \(Fmt.weekday(today))", icon: "bl.body", color: Palette.anatomy)
                Spacer()
                Button(plan.isEmpty ? "Set up" : "Edit plan", action: onEdit)
                    .font(Typo.geist(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.signal)
            }
            if plan.isEmpty {
                Text("Plan your training week").font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                Text("Pick what you train each day, like chest on Monday. Today's muscles glow on the figure and you tick the session off when it's done.")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            } else if let title = plan.title(on: today) {
                WorkoutTickRow(planRaw: $planRaw, today: today, title: title)
                weekStrip
                let a = plan.adherence(endingOn: today)
                if a.planned > 0 {
                    Text("\(a.done) of the last \(a.planned) planned sessions done")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            } else {
                Text("Rest day").font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                Text(nextSession.map { "Next: \($0)" } ?? "Nothing planned this week.")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                weekStrip
            }
        }
        .card(tone: .tinted(Palette.anatomy))
    }

    var nextSession: String? {
        for offset in 1...7 {
            let d = today.adding(days: offset)
            if let t = plan.title(on: d) { return "\(Fmt.weekday(d)), \(t.lowercased())" }
        }
        return nil
    }

    /// The last seven days, oldest first: filled = done, outlined = planned but not ticked, dot = rest.
    var weekStrip: some View {
        HStack(spacing: Space.s) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let d = today.adding(days: -offset)
                let planned = plan.isTrainingDay(d)
                let done = plan.isDone(d)
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(done ? Palette.anatomy : Color.clear)
                        Circle().strokeBorder(planned ? Palette.anatomy : Palette.hairline, lineWidth: planned ? 1.5 : 1)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.canvas)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(String(Fmt.weekday(d).prefix(1)))
                        .font(Typo.eyebrow).foregroundStyle(offset == 0 ? Palette.ink : Palette.tertiaryInk)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Fmt.weekday(d)): \(planned ? (done ? "done" : "planned, not done") : "rest")")
            }
        }
    }
}

/// "Chest day" with a tick circle. Used on Body and on Today.
struct WorkoutTickRow: View {
    @Binding var planRaw: String
    let today: LocalDate
    let title: String

    var body: some View {
        let done = WorkoutPlan.decode(planRaw).isDone(today)
        Button {
            var p = WorkoutPlan.decode(planRaw)
            p.toggle(today)
            withAnimation(Motion.snappy) { planRaw = p.encoded() }
        } label: {
            HStack(spacing: Space.m) {
                ZStack {
                    Circle().fill(done ? Palette.anatomy : Color.clear)
                    Circle().strokeBorder(Palette.anatomy, lineWidth: 1.5)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.canvas)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                        .strikethrough(done, color: Palette.tertiaryInk)
                    Text(done ? "Done. Nice work." : "Tap to mark done")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .accessibilityLabel("\(title), \(done ? "done" : "not done")")
        .accessibilityHint(done ? "Marks it not done" : "Marks it done")
    }
}

/// Today screen: a compact row for today's session, only when there is one.
struct WorkoutTodayRow: View {
    @AppStorage(WorkoutPlanStore.key) private var planRaw = ""
    @Environment(AppRouter.self) private var router
    let today: LocalDate

    var body: some View {
        if let title = WorkoutPlan.decode(planRaw).title(on: today) {
            HStack(spacing: Space.m) {
                WorkoutTickRow(planRaw: $planRaw, today: today, title: title)
                Button { router.tab = .body } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Body")
            }
            .card(tone: .tinted(Palette.anatomy))
        }
    }
}

/// Edits the weekly split: a preset to start from, then the groups for each day.
struct WorkoutPlanEditor: View {
    @Binding var planRaw: String
    @Environment(\.dismiss) private var dismiss
    @State private var plan = WorkoutPlan()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        ForEach(WorkoutPlan.presets.indices, id: \.self) { i in
                            Button(WorkoutPlan.presets[i].name) {
                                plan.days = WorkoutPlan.presets[i].plan.days
                            }
                        }
                    } label: {
                        Label("Start from a preset", systemImage: "square.grid.2x2")
                    }
                } footer: {
                    Text("A preset replaces the days below. Your ticks are kept.")
                }
                ForEach(weekOrder, id: \.self) { weekday in
                    Section(Fmt.weekdayNames[weekday - 1]) {
                        groupChips(weekday)
                    }
                }
                if !plan.isEmpty {
                    Section {
                        Button("Clear plan", role: .destructive) { plan.days = [:] }
                    }
                }
            }
            .navigationTitle("Training week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        planRaw = plan.encoded()
                        dismiss()
                    }
                }
            }
            .onAppear { plan = WorkoutPlan.decode(planRaw) }
        }
    }

    func groupChips(_ weekday: Int) -> some View {
        let selected = plan.days[weekday] ?? []
        return ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(MuscleGroup.allCases) { group in
                    let on = selected.contains(group)
                    Button {
                        var list = selected
                        if on { list.removeAll { $0 == group } } else { list.append(group) }
                        plan.days[weekday] = list.isEmpty ? nil : list
                    } label: {
                        Text(group.displayName)
                            .font(Typo.geist(14, .medium, relativeTo: .subheadline))
                            .foregroundStyle(on ? Palette.canvas : Palette.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(on ? Palette.anatomy : Palette.sunken))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
