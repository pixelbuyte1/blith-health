import BlithCore
import SwiftUI
import WidgetKit

/// Profile › Widgets: the Home and Lock Screen widgets drawn with today's numbers, and how to add them.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var app

    var data: WidgetSnapshot {
        guard let s = app.snapshot else { return .preview() }
        return WidgetSnapshot(snapshot: s, companion: app.huaweiSync, isSample: app.isDemo)
    }

    var body: some View {
        let now = AppClock.now()
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Eyebrow(text: "Home Screen")
                HStack(spacing: Space.m) {
                    tile(ReadinessWidgetView(snapshot: data, date: now, family: .systemSmall), width: 158)
                    tile(MovementWidgetView(snapshot: data, date: now, family: .systemSmall), width: 158)
                }
                tile(ReadinessWidgetView(snapshot: data, date: now, family: .systemMedium), width: 330)

                Eyebrow(text: "Lock Screen").padding(.top, Space.s)
                HStack(spacing: Space.m) {
                    lock(ReadinessWidgetView(snapshot: data, date: now, family: .accessoryCircular), width: 64, height: 64, circle: true)
                    lock(ReadinessWidgetView(snapshot: data, date: now, family: .accessoryRectangular), width: 160, height: 64)
                }
                lock(MovementWidgetView(snapshot: data, date: now, family: .accessoryRectangular), width: 160, height: 64)

                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Add a widget").font(Typo.cardTitle).foregroundStyle(Palette.ink)
                    step(1, "Touch and hold an empty part of your Home Screen or Lock Screen.")
                    step(2, "Tap Edit, then Add Widget (on the Lock Screen, tap Customize).")
                    step(3, "Search for Blith and pick Readiness or Steps.")
                    Text("Widgets update each time Blith syncs, and show \"Open Blith\" after midnight until today's numbers are in.")
                        .font(Typo.caption).foregroundStyle(Palette.tertiaryInk).padding(.top, Space.xs)
                }
                .card()
                .padding(.top, Space.s)
            }
            .padding(Space.page)
        }
        .blithBackground()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    func tile(_ content: some View, width: CGFloat) -> some View {
        content
            .padding(14)
            .frame(width: width, height: 158)
            .background(WidgetBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    func lock(_ content: some View, width: CGFloat, height: CGFloat, circle: Bool = false) -> some View {
        content
            .foregroundStyle(.white)
            .padding(circle ? 4 : 8)
            .frame(width: width, height: height)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: circle ? height / 2 : 14, style: .continuous))
            .environment(\.colorScheme, .dark)
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("\(n)").font(Typo.mono(13, .medium)).foregroundStyle(Palette.signal)
            Text(text).font(Typo.body).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }
}
