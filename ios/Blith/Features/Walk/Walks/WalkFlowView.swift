import BlithCore
import SwiftUI
import UIKit

/// The walk, full screen: Start → Recording ⇄ Paused → Finish → Summary.
struct WalkFlowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let recorder = app.walks
        Group {
            switch recorder.phase {
            case .idle, .ready:
                StartWalkView()
            case .recording, .paused:
                LiveWalkView()
            case .finishing:
                FinishWalkView()
            case .saved:
                if let walk = recorder.summaryWalk {
                    NavigationStack {
                        WalkSummaryView(walk: walk, saveMessage: recorder.saveMessage)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { recorder.closeSummary() }
                                }
                            }
                    }
                }
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
    }
}

/// One live number with its label and where it came from. Missing data says so.
struct WalkMetric: View {
    let value: String?
    let label: String
    let source: WalkSource?
    var size: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value {
                Text(value).font(Typo.number(size)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text("Not available").font(Typo.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.tertiaryInk)
            }
            Text(label).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            if let source, value != nil {
                Text(source.rawValue.uppercased()).font(Typo.eyebrow).tracking(0.9).foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum WalkFormat {
    static func distanceNumber(_ metres: Double, units: UnitSystem) -> String {
        Fmt.decimal(metres / WalkPace.unitLength(units), digits: 2)
    }

    static func unit(_ units: UnitSystem) -> String { units == .metric ? "km" : "mi" }

    /// Speed from a pace (seconds per unit), as km/h or mph.
    static func speed(pace: Double?, units: UnitSystem) -> String? {
        guard let pace, pace > 0 else { return nil }
        return Fmt.decimal(3600 / pace)
    }

    static func climb(_ metres: Double?, units: UnitSystem) -> String? {
        guard let metres else { return nil }
        return units == .metric ? "+\(Fmt.int(metres)) m" : "+\(Fmt.int(metres * 3.280_84)) ft"
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

// MARK: Start

struct StartWalkView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        let recorder = app.walks
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                WalkRouteMap(segments: [], followsUser: true)
                HStack {
                    Button { recorder.cancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .glassSurface(Circle(), interactive: true)
                    .accessibilityLabel("Close")
                    Spacer()
                    gpsStatus(recorder)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Eyebrow(text: "Start a walk", icon: "bl.walk", color: Palette.signal)
                        if recorder.isDemo || app.isDemo { SampleDataBanner() }
                    }
                    Text("Free walk").font(Typo.display).foregroundStyle(Palette.ink)
                    Text("GPS draws your route and measures distance, pace and splits.")
                        .font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                }
                permission(recorder)
                VStack(spacing: 0) {
                    row(icon: "bl.heart", title: "Heart rate", detail: "From Apple Watch, if you wear one", tint: Palette.heart)
                    row(icon: "bl.steps", title: "Steps", detail: recorder.stepsAvailable ? "iPhone motion sensor" : "Not available on this iPhone", tint: Palette.signal)
                    row(icon: "bl.stairs", title: "Climb", detail: recorder.climbAvailable ? "Barometer" : "Not available on this iPhone", tint: Palette.signal)
                    row(icon: "lock", title: "Keeps tracking when locked", detail: "While a walk is running", tint: Palette.signal)
                }
                if app.isDemo {
                    Text("Sample mode: the walk uses your real GPS but isn't saved to Apple Health.")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
                Button { recorder.startWalk() } label: {
                    Label("Start walk", systemImage: "play.fill")
                        .font(Typo.geist(18, .semibold, relativeTo: .headline))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .glassButton(prominent: true)
                .disabled(!recorder.access.canTrack)
            }
            .padding(Space.xl)
            .background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
        }
        .ignoresSafeArea(edges: .top)
    }

    func gpsStatus(_ r: WalkRecorder) -> some View {
        let (text, color): (String, Color) = {
            guard r.access.canTrack else { return ("Location off", Palette.secondaryInk) }
            guard let acc = r.latestAccuracy else { return ("Finding GPS…", Palette.secondaryInk) }
            if acc <= 20 { return ("GPS ready · ±\(Int(acc.rounded())) m", Palette.signal) }
            return ("Weak GPS · ±\(Int(acc.rounded())) m", Palette.secondaryInk)
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text.uppercased()).font(Typo.eyebrow).tracking(0.9)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassSurface(Capsule())
        .frame(minHeight: 44)
    }

    @ViewBuilder
    func permission(_ r: WalkRecorder) -> some View {
        switch r.access {
        case .notDetermined:
            permissionCard(text: "Blith needs your location while you walk to draw the route and measure distance. It stays on this iPhone and in Apple Health.",
                           button: "Allow location") { r.requestLocation() }
        case .denied, .restricted:
            permissionCard(text: "Location is off for Blith, so a walk can't be recorded. Turn on \"While Using the App\" in Settings › Privacy & Security › Location Services › Blith.",
                           button: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .approximate:
            permissionCard(text: "Precise Location is off, so distance and the route would be rough.",
                           button: "Use precise location") { r.requestLocation() }
        case .allowed:
            EmptyView()
        }
    }

    func permissionCard(text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(text).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.signal)
                .frame(minHeight: 44)
        }
        .card(padding: Space.m, tone: .tinted(Palette.signal))
    }

    func row(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: Space.m) {
            BLIcon(name: icon, size: 18).foregroundStyle(tint)
            Text(title).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
            Spacer()
            Text(detail).font(Typo.caption).foregroundStyle(Palette.secondaryInk).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Recording and paused

struct LiveWalkView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let r = app.walks
        let units = app.profile.units
        let track = r.track
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                WalkRouteMap(segments: track.segments, markers: WalkSplits.markers(track, units: units), followsUser: true)
                    .opacity(r.phase == .paused ? 0.7 : 1)
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    VStack(spacing: Space.s) {
                        status(r, now: tl.date)
                        if r.gpsLost(at: tl.date) {
                            note("Searching for GPS. Time keeps running; distance picks up again when GPS returns.")
                        } else if track.gapSeconds >= 1 {
                            note("GPS dropped for \(Int(track.gapSeconds.rounded())) s. That stretch isn't drawn or counted.")
                        }
                    }
                    .padding(.top, Space.xl + Space.l)
                    .padding(.horizontal, Space.l)
                }
            }
            .frame(maxHeight: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { tl in
                panel(r, units: units, track: track, now: tl.date)
            }
        }
        .ignoresSafeArea(edges: .top)
        .sensoryFeedback(.impact, trigger: r.phase)
    }

    func status(_ r: WalkRecorder, now: Date) -> some View {
        HStack {
            if r.phase == .paused {
                let since = r.pausedSince.map { WalkPace.clock(now.timeIntervalSince($0)) } ?? ""
                StatusLabel(symbol: "pause.fill", text: "Paused · \(since)", color: Palette.secondaryInk)
            } else {
                StatusLabel(symbol: "record.circle", text: "Recording", color: Palette.signal)
            }
            Spacer()
            if r.isDemo { SampleDataBanner() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassSurface(Capsule())
    }

    func note(_ text: String) -> some View {
        Text(text).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func panel(_ r: WalkRecorder, units: UnitSystem, track: ProcessedTrack, now: Date) -> some View {
        let moving = r.movingTime(at: now)
        let pace = r.phase == .recording ? WalkPace.current(track, now: now, units: units) : nil
        let average = WalkPace.average(distance: track.distance, movingTime: moving, units: units)
        let unitName = units == .metric ? "/km" : "/mi"
        return VStack(alignment: .leading, spacing: Space.l) {
            if r.phase == .paused {
                Text("Paused. Time and distance are on hold.").font(Typo.story).foregroundStyle(Palette.ink)
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Distance · GPS", color: Palette.signal)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(WalkFormat.distanceNumber(track.distance, units: units))
                            .font(Typo.score(r.phase == .paused ? 64 : 80)).foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text(WalkFormat.unit(units)).font(Typo.geist(22, .medium, relativeTo: .title3)).foregroundStyle(Palette.secondaryInk)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Eyebrow(text: "Moving")
                    Text(WalkPace.clock(moving)).font(Typo.score(36, weight: .regular)).foregroundStyle(Palette.ink)
                }
            }
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 3), alignment: .leading, spacing: Space.l) {
                WalkMetric(value: pace.map { WalkPace.format($0) }, label: "Pace \(unitName)", source: .gps)
                WalkMetric(value: average.map { WalkPace.format($0) }, label: "Avg pace", source: .gps)
                WalkMetric(value: WalkFormat.speed(pace: pace, units: units), label: units == .metric ? "km/h" : "mph", source: .gps)
                WalkMetric(value: r.steps.map { Fmt.int(Double($0)) }, label: "Steps", source: .iPhone)
                WalkMetric(value: WalkFormat.climb(r.climb, units: units), label: "Climb", source: .barometer)
                WalkMetric(value: r.heartRate(at: now).map { Fmt.int($0) }, label: "bpm",
                           source: r.heartSource.flatMap(WalkSource.init(rawValue:)))
            }
            .padding(.top, Space.s)
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
            controls(r)
        }
        .padding(Space.xl)
        .background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
    }

    @ViewBuilder
    func controls(_ r: WalkRecorder) -> some View {
        if r.phase == .paused {
            VStack(spacing: Space.s) {
                Button { r.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(Typo.geist(18, .semibold, relativeTo: .headline))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .glassButton(prominent: true)
                Button { Task { await r.finish(app: app) } } label: {
                    Text("Finish walk").font(Typo.geist(16, .medium, relativeTo: .body))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .glassButton()
            }
        } else {
            HStack {
                Spacer()
                Button { r.pause() } label: {
                    Image(systemName: "pause.fill").font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Palette.canvas)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Palette.ink))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause walk")
                Spacer()
            }
        }
    }
}

// MARK: Finish

struct FinishWalkView: View {
    @Environment(AppModel.self) private var app
    @State private var feel: WalkFeel?
    @State private var note = ""
    @State private var confirmDiscard = false

    var body: some View {
        let r = app.walks
        let units = app.profile.units
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let walk = r.finished {
                    let track = walk.track
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow(text: "\(walk.displayTitle()) · \(WalkFormat.time(walk.start))", icon: "bl.walk", color: Palette.signal)
                        Text("Finish this walk?").font(Typo.display).foregroundStyle(Palette.ink)
                    }
                    HStack(alignment: .top) {
                        WalkMetric(value: "\(WalkFormat.distanceNumber(track.distance, units: units)) \(WalkFormat.unit(units))", label: "Distance", source: .gps, size: 26)
                        WalkMetric(value: WalkPace.clock(walk.movingTime), label: "Moving", source: nil, size: 26)
                        WalkMetric(value: WalkPace.average(distance: track.distance, movingTime: walk.movingTime, units: units).map { WalkPace.format($0) },
                                   label: units == .metric ? "Avg / km" : "Avg / mi", source: .gps, size: 26)
                    }
                    .card(padding: Space.l, tone: .hero)
                    if r.finishedIsRecovered {
                        info("Recovered after Blith closed. The walk ends at the last point saved, \(WalkFormat.time(walk.end)).")
                    }
                    if r.watchWalk != nil {
                        info("Your Apple Watch recorded this walk too. Blith keeps one walk and takes heart rate from the Watch, so nothing counts twice.")
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "How did it feel · optional")
                        HStack(spacing: Space.s) {
                            ForEach(WalkFeel.allCases, id: \.self) { f in
                                Button { feel = feel == f ? nil : f } label: {
                                    Text(f.title).font(Typo.geist(15, .medium, relativeTo: .subheadline))
                                        .foregroundStyle(feel == f ? Palette.canvas : Palette.ink)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(Capsule().fill(feel == f ? Palette.ink : Palette.raised))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(feel == f ? .isSelected : [])
                            }
                        }
                        TextField("A note about this walk", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .font(Typo.body)
                            .padding(Space.m)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    VStack(spacing: Space.s) {
                        Button { Task { await r.save(feel: feel, note: note, app: app) } } label: {
                            Group {
                                if r.isSaving { ProgressView() } else { Text("Save walk") }
                            }
                            .font(Typo.geist(17, .semibold, relativeTo: .headline))
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .glassButton(prominent: true)
                        .disabled(r.isSaving)
                        HStack(spacing: Space.s) {
                            if !r.finishedIsRecovered {
                                Button { r.resume() } label: {
                                    Text("Keep walking").frame(maxWidth: .infinity, minHeight: 46)
                                }
                                .glassButton()
                            }
                            Button(role: .destructive) { confirmDiscard = true } label: {
                                Text("Discard").frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .glassButton()
                        }
                        .font(Typo.geist(15, .medium, relativeTo: .subheadline))
                        .disabled(r.isSaving)
                    }
                }
            }
            .padding(Space.xl)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Discard this walk?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard walk", role: .destructive) { r.discard() }
        } message: {
            Text("It won't be saved on this iPhone or in Apple Health.")
        }
    }

    func info(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "info.circle").foregroundStyle(Palette.secondaryInk)
            Text(text).font(Typo.geist(14, relativeTo: .footnote)).foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Space.m)
    }
}
