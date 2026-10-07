import BlithCore
import SwiftUI

/// Something the person tagged with @ in the Ask composer, so Ask knows exactly what the
/// question is about instead of guessing from the words.
enum AskTag: Hashable, Identifiable {
    case body(BodyRegion)
    case sleep
    case heartRate
    case day(LocalDate)

    static let limit = 3

    var id: String {
        switch self {
        case .body(let r): "body.\(r.rawValue)"
        case .sleep: "sleep"
        case .heartRate: "heartRate"
        case .day(let d): "day.\(d)"
        }
    }

    var label: String {
        switch self {
        case .body(let r): r.displayName
        case .sleep: "Sleep"
        case .heartRate: "Heart rate"
        case .day(let d): d.startDate(in: .current).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    /// What the AI model is told the tag means.
    var context: String {
        switch self {
        case .body(let r): "body area \(r.displayName.lowercased()) (region \(r.rawValue))"
        case .sleep: "sleep"
        case .heartRate: "heart rate"
        case .day(let d): "the day \(d)"
        }
    }
}

/// The small picture on a tag chip: the app's body glyph for a body part, a symbol otherwise.
struct AskTagIcon: View {
    let tag: AskTag
    var size: CGFloat = 20

    var body: some View {
        switch tag {
        case .body(let r): BodyPartGlyph(region: r, size: size)
        case .sleep: symbol("moon.fill", Palette.sleep)
        case .heartRate: symbol("waveform.path.ecg", Palette.heart)
        case .day: symbol("calendar", Palette.signal)
        }
    }

    private func symbol(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.6, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}

/// A tag in the composer (removable) or on a sent question.
struct AskTagChip: View {
    let tag: AskTag
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.xs) {
            AskTagIcon(tag: tag)
            Text(tag.label).font(Typo.geist(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.secondaryInk)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(tag.label)")
            }
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, remove == nil ? Space.m : Space.xxs)
        .frame(minHeight: 30)
        .background(Palette.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// The panel the @ button opens: Body (with the body picture), Sleep, Heart rate and A day.
struct AskTagPanel: View {
    let tagged: [AskTag]
    let pick: (AskTag) -> Void
    @State private var section: Part?
    @State private var region: BodyRegion?
    @State private var day = Date()

    enum Part { case body, day }

    private var full: Bool { tagged.count >= AskTag.limit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(full ? "Up to \(AskTag.limit) tags per question" : "Tag what you're asking about")
                    .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                row("Body", detail: "A spot on your body", icon: .body(region ?? .chest), expanded: section == .body) {
                    section = section == .body ? nil : .body
                }
                if section == .body { bodyPicker }
                row("Sleep", detail: "A night", icon: .sleep, expanded: false) { pick(.sleep) }
                row("Heart rate", detail: "Readings", icon: .heartRate, expanded: false) { pick(.heartRate) }
                row("A day", detail: "Everything that day", icon: .day(LocalDate(Date(), calendar: .current)), expanded: section == .day) {
                    section = section == .day ? nil : .day
                }
                if section == .day { dayPicker }
            }
            .padding(Space.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 340)
        .fixedSize(horizontal: false, vertical: section == nil)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .disabled(full)
    }

    private func row(_ title: String, detail: String, icon: AskTag, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                AskTagIcon(tag: icon, size: 26)
                    .frame(width: 36, height: 36)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(Typo.geist(16, .medium, relativeTo: .body)).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                Text(detail).font(Typo.caption).foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(expanded ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(expanded ? [.isButton, .isSelected] : .isButton)
    }

    /// The body picture grows with the part you tap; tapping a part tags it.
    private var bodyPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                BodyPartGlyph(region: region, size: 88)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Pick where it is. Left and right are your own sides.")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                    if let region {
                        Text(region.displayName).font(Typo.geist(16, .semibold, relativeTo: .body)).foregroundStyle(Palette.ink)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(BodyRegion.allCases.filter { $0 != .other }) { r in
                        Button {
                            region = r
                            pick(.body(r))
                            section = nil
                        } label: {
                            HStack(spacing: Space.xs) {
                                BodyPartGlyph(region: r, size: 22)
                                Text(r.displayName).font(Typo.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            }
                            .padding(.horizontal, Space.s)
                            .frame(minHeight: 36)
                            .background(Palette.raised, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
    }

    private var dayPicker: some View {
        HStack {
            DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Spacer()
            Button("Tag") {
                pick(.day(LocalDate(day, calendar: .current)))
                section = nil
            }
            .font(Typo.geist(15, .semibold, relativeTo: .subheadline))
            .buttonStyle(.borderedProminent)
            .tint(Palette.signal)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
    }
}
