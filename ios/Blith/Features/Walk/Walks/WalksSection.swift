import BlithCore
import SwiftUI

/// Activity › Walks: start a GPS walk, see the last one, open the history.
struct WalksSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let recorder = app.walks
        let units = app.profile.units
        let last = recorder.walks.first
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: "Walks · routes", icon: "bl.walk", color: Palette.signal)
            Text(sentence(recorder: recorder, last: last, units: units))
                .font(Typo.story).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            if let last, !recorder.isActive {
                NavigationLink(value: WalkRoute.summary(last.id)) {
                    HStack(spacing: Space.m) {
                        WalkThumbnail(segments: last.track.segments)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(last.displayTitle()).font(Typo.cardTitle).foregroundStyle(Palette.ink)
                            Text("\(Fmt.dayLabel(LocalDate(last.start, calendar: .current))) · \(Fmt.distance(last.track.distance, units: units)) · \(Fmt.duration(last.movingTime))")
                                .font(Typo.number(14)).foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer(minLength: Space.s)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.tertiaryInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Space.s) {
                Button { recorder.present(isDemo: app.isDemo) } label: {
                    Label(recorder.isActive ? "Back to your walk" : "Start walk", systemImage: recorder.isActive ? "figure.walk" : "play.fill")
                        .font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .glassButton(prominent: true)
                NavigationLink(value: WalkRoute.history) {
                    Text("Walk history").font(Typo.geist(15, .medium, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .glassButton()
            }
        }
        .card(padding: Space.l, tone: .tinted(Palette.signal))
    }

    func sentence(recorder: WalkRecorder, last: RecordedWalk?, units: UnitSystem) -> String {
        if recorder.isActive { return "A walk is being recorded." }
        guard let last else { return "Record a walk with GPS: your route, distance, pace, splits and climb." }
        let day = LocalDate(last.start, calendar: .current)
        let today = LocalDate(AppClock.now(), calendar: .current)
        let when = day == today ? "today" : "on \(Fmt.weekday(day))"
        return "Your last walk was \(Fmt.distance(last.track.distance, units: units)) \(when)."
    }
}
