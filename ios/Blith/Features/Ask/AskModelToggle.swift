import SwiftUI

/// Ask's two models under Blith's own names. The provider model ids live in `AppConfig`.
enum AskModelChoice: String, CaseIterable, Identifiable {
    case quick, deep

    /// How many AI answers in a chat use Quick before automatic mode moves to Deep.
    static let quickAnswers = 4

    var id: String { rawValue }

    var name: String {
        switch self {
        case .quick: "Quick"
        case .deep: "Deep"
        }
    }

    var blurb: String {
        switch self {
        case .quick: "Fastest for everyday questions"
        case .deep: "Most thorough for patterns and trends"
        }
    }

    var icon: String {
        switch self {
        case .quick: "bolt.fill"
        case .deep: "water.waves"
        }
    }

    var modelID: String {
        switch self {
        case .quick: AppConfig.quickModel
        case .deep: AppConfig.model
        }
    }
}

/// Two-model switch in the Ask composer: the selected side is a pill that slides across.
struct AskModelToggle: View {
    let selection: AskModelChoice
    let pick: (AskModelChoice) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AskModelChoice.allCases) { m in
                let on = selection == m
                Button {
                    // Tapping the side already shown still pins it, so automatic mode stops switching.
                    pick(m)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: m.icon).font(.system(size: 11, weight: .semibold))
                        Text(m.name).font(Typo.geist(14, .semibold, relativeTo: .subheadline))
                    }
                    .foregroundStyle(on ? Palette.canvas : Palette.secondaryInk)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 32)
                    .background {
                        if on {
                            Capsule().fill(Palette.signal).matchedGeometryEffect(id: "askModel", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.name)
                .accessibilityHint(m.blurb)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: selection)
        .padding(3)
        .background(Palette.raised, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
