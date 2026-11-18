import BlithCore
import SwiftUI

/// Every walk once: GPS walks recorded in Blith, plus walks that only exist in Apple Health
/// (tagged "Health", no map).
struct WalkHistoryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let units = app.profile.units
        let entries = WalkHistory.entries(recorded: app.walks.walks, workouts: app.history?.workouts ?? [],
                                          ownSourceID: WalkHealthWriter.ownSourceID)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Eyebrow(text: "Activity · walks", icon: "bl.walk", color: Palette.signal)
                        if app.isDemo { SampleDataBanner() }
                    }
                    Text("Walk history").font(Typo.display).foregroundStyle(Palette.ink)
                }
                if entries.isEmpty {
                    EmptyStateView(symbol: "bl.walk", title: "No walks yet",
                                   message: "Walks you record with GPS in Blith appear here, with walks your Apple Watch or other apps save to Apple Health.")
                } else {
                    month(entries, units: units)
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            if let id = entry.recordedWalkID {
                                NavigationLink(value: WalkRoute.summary(id)) { row(entry, units: units) }
                                    .buttonStyle(.plain)
                            } else {
                                row(entry, units: units)
                            }
                        }
                    }
                    .card(padding: Space.m)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.section)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .blithBackground(wash: Palette.signal.opacity(0.14))
        .navigationTitle("Walk history")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// This calendar month: distance where it's known, walks and moving time.
    func month(_ entries: [WalkHistoryEntry], units: UnitSystem) -> some View {
        let calendar = Calendar.current
        let now = AppClock.now()
        let thisMonth = entries.filter { calendar.isDate($0.start, equalTo: now, toGranularity: .month) }
        let distances = thisMonth.compactMap(\.distance)
        let time = thisMonth.reduce(0) { $0 + $1.movingTime }
        return VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(text: now.formatted(.dateTime.month(.wide)), color: Palette.signal)
            HStack(alignment: .lastTextBaseline) {
                if distances.isEmpty {
                    Text("No distance recorded yet").font(Typo.storySmall).foregroundStyle(Palette.secondaryInk)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(WalkFormat.distanceNumber(distances.reduce(0, +), units: units)).font(Typo.score(52)).foregroundStyle(Palette.ink)
                        Text(WalkFormat.unit(units)).font(Typo.geist(18, .medium, relativeTo: .title3)).foregroundStyle(Palette.secondaryInk)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(thisMonth.count) \(thisMonth.count == 1 ? "walk" : "walks")")
                    Text(Fmt.duration(time))
                }
                .font(Typo.number(15)).foregroundStyle(Palette.secondaryInk)
            }
            if distances.count < thisMonth.count {
                Text("\(thisMonth.count - distances.count) of these have no distance in Apple Health, so it isn't added.")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            }
        }
        .card(padding: Space.l, tone: .hero)
    }

    func row(_ entry: WalkHistoryEntry, units: UnitSystem) -> some View {
        let walk = entry.recordedWalkID.flatMap { id in app.walks.walks.first { $0.id == id } }
        let day = LocalDate(entry.start, calendar: .current)
        let today = LocalDate(AppClock.now(), calendar: .current)
        let when = day == today ? "Today" : Fmt.dayLabel(day)
        let distance = entry.distance.map { Fmt.distance($0, units: units) } ?? "no distance"
        let detail = "\(when) · \(distance) · \(Fmt.duration(entry.movingTime))\(entry.hasMap ? "" : " · no map")"
        return HStack(spacing: Space.m) {
            WalkThumbnail(segments: walk?.track.segments)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                Text(detail).font(Typo.number(14)).foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: Space.s)
            MonoPill(text: entry.kind == .gps ? "GPS" : "Health", color: entry.kind == .gps ? Palette.signal : Palette.secondaryInk)
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Opens a recorded walk by id (from history or Activity).
struct WalkSummaryDestination: View {
    let id: String
    @Environment(AppModel.self) private var app

    var body: some View {
        if let walk = app.walks.walks.first(where: { $0.id == id }) {
            WalkSummaryView(walk: walk)
        } else {
            EmptyStateView(symbol: "bl.walk", title: "Walk not found", message: "This walk is no longer on this iPhone.")
                .padding(Space.page)
        }
    }
}
