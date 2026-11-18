import BlithCore
import SwiftUI

/// Pushed inside Activity: Walk history and a walk's summary.
enum WalkRoute: Hashable {
    case history
    case summary(String)
}

/// A finished GPS walk: the route, the numbers with their sources, splits, heart rate, and how it
/// compares with earlier walks of the same route.
struct WalkSummaryView: View {
    let walk: RecordedWalk
    var saveMessage: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        let units = app.profile.units
        let track = walk.track
        let splits = WalkSplits.compute(track, start: walk.start, pauses: walk.pauses, units: units)
        let heart = WalkHeart.summary(walk.heart, within: walk.movingIntervals)
        let comparison = RouteMatch.compare(walk, with: app.walks.walks)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                WalkRouteMap(segments: track.segments, markers: WalkSplits.markers(track, units: units))
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel("Map of the route")
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Eyebrow(text: "Walk · \(walk.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(WalkFormat.time(walk.start))",
                                icon: "bl.walk", color: Palette.signal)
                        if walk.isDemo { SampleDataBanner() }
                    }
                    Text(walk.displayTitle()).font(Typo.display).foregroundStyle(Palette.ink)
                }
                hero(track: track, units: units, comparison: comparison)
                if !splits.isEmpty { splitsCard(splits, units: units) }
                if let heart { heartCard(heart) }
                if track.gapSeconds >= 1 {
                    Text("GPS dropped for \(Fmt.duration(track.gapSeconds)) in total. Those stretches aren't drawn or counted; the time still is.")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
                if walk.feel != nil || walk.note != nil {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Your note")
                        if let feel = walk.feel { MonoPill(text: feel.title, color: Palette.signal) }
                        if let note = walk.note { Text(note).font(Typo.storySmall).foregroundStyle(Palette.ink) }
                    }
                    .card()
                }
                if let saveMessage {
                    Label(saveMessage, systemImage: "heart.text.square")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                } else if walk.mergedWithWatch {
                    Label("Kept as your Apple Watch walk in Apple Health, so nothing counts twice.", systemImage: "applewatch")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                } else if walk.healthWorkoutID != nil {
                    Label("Saved in Apple Health as a walking workout with its route.", systemImage: "heart.text.square")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.section)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .blithBackground(wash: Palette.signal.opacity(0.14))
        .navigationTitle(walk.displayTitle())
        .navigationBarTitleDisplayMode(.inline)
    }

    func hero(track: ProcessedTrack, units: UnitSystem, comparison: RouteComparison?) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(sentence(track: track, units: units, comparison: comparison))
                .font(Typo.story).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 3), alignment: .leading, spacing: Space.l) {
                WalkMetric(value: "\(WalkFormat.distanceNumber(track.distance, units: units)) \(WalkFormat.unit(units))", label: "Distance", source: .gps)
                WalkMetric(value: WalkPace.clock(walk.movingTime), label: "Moving", source: nil)
                WalkMetric(value: WalkPace.average(distance: track.distance, movingTime: walk.movingTime, units: units).map { WalkPace.format($0) },
                           label: units == .metric ? "Avg / km" : "Avg / mi", source: .gps)
                WalkMetric(value: walk.steps.map { Fmt.int(Double($0)) }, label: "Steps", source: .iPhone)
                WalkMetric(value: WalkFormat.climb(walk.climb, units: units), label: "Climb", source: .barometer)
            }
            Text("Steps, distance and Load on Today come from Apple Health, where this walk counts once.")
                .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
        }
        .card(padding: Space.l, tone: .hero)
    }

    func sentence(track: ProcessedTrack, units: UnitSystem, comparison: RouteComparison?) -> String {
        if let comparison { return comparison.sentence(routeName: walk.displayTitle()) }
        let minutes = Int((walk.movingTime / 60).rounded())
        return "\(Fmt.distance(track.distance, units: units)) in \(minutes) min of walking."
    }

    func splitsCard(_ splits: [WalkSplit], units: UnitSystem) -> some View {
        let paces = splits.compactMap { $0.pace(units) }
        let fastest = paces.min()
        let slowest = paces.max() ?? 1
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow(text: units == .metric ? "Splits · per km" : "Splits · per mile")
                Spacer()
                Eyebrow(text: "Brightest = fastest", color: Palette.tertiaryInk)
            }
            ForEach(splits) { split in
                let pace = split.pace(units)
                HStack(spacing: Space.m) {
                    Text("\(split.index)").font(Typo.number(13)).foregroundStyle(Palette.tertiaryInk).frame(width: 18, alignment: .leading)
                    GeometryReader { g in
                        Capsule()
                            .fill(pace != nil && pace == fastest ? Palette.signal : Palette.signal.opacity(0.4))
                            .frame(width: g.size.width * CGFloat(min(1, max(0.15, (pace ?? 0) / max(slowest, 1)))), height: 8)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(WalkPace.format(pace)).font(Typo.number(14)).foregroundStyle(Palette.ink)
                        if split.includesGap { Text("GPS gap").font(Typo.geist(11, relativeTo: .caption2)).foregroundStyle(Palette.tertiaryInk) }
                    }
                    .frame(width: 64, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Split \(split.index): \(WalkPace.format(pace))\(split.includesGap ? ", includes a GPS gap" : "")")
            }
            if let last = splits.last, last.distance < WalkPace.unitLength(units) - 1 {
                Text("The last split is \(Fmt.distance(last.distance, units: units)); its pace is for that part.")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            }
        }
        .card()
    }

    func heartCard(_ heart: WalkHeartSummary) -> some View {
        let values = walk.heart.filter { s in walk.movingIntervals.contains { $0.contains(s.date) } }.map(\.bpm)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow(text: "Heart rate", icon: "bl.heart", color: Palette.heart)
                Spacer()
                Eyebrow(text: walk.heartSource ?? WalkSource.health.rawValue, color: Palette.tertiaryInk)
            }
            if values.count >= 3 {
                MiniSpark(values: values, color: Palette.heart).frame(height: 40)
            }
            HStack(spacing: Space.xl) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.int(heart.average)).font(Typo.number(20)).foregroundStyle(Palette.ink)
                    Text("avg").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.int(heart.maximum)).font(Typo.number(20)).foregroundStyle(Palette.ink)
                    Text("max bpm").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .card()
    }
}
