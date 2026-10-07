import BlithCore
import SwiftUI
import UIKit

// MARK: - Color

/// Blith "Redesign 2" palette: paper, ink and teal; rust only for outside-usual (see docs/DESIGN.md). Every token adapts to light and dark.
/// Neutrals carry the hierarchy; blue is the brand and the data; warm colour is rare and means
/// something: amber = worth a look / the person's own notes, coral = heart and genuine alerts.
enum Palette {
    // Neutrals
    static let canvas = Color(light: 0xEEF0EA, dark: 0x0E1211)
    static let surface = Color(light: 0xFBFBF8, dark: 0x161B1A)
    static let raised = Color(light: 0xF2F3EE, dark: 0x1E2423)
    static let sunken = Color(light: 0xDADED6, dark: 0x262D2B)
    static let hairline = Color(light: 0x14181B, lightOpacity: 0.09, dark: 0xFFFFFF, darkOpacity: 0.08)
    static let topLight = Color(light: 0xFFFFFF, lightOpacity: 0, dark: 0xFFFFFF, darkOpacity: 0.07)

    static let ink = Color(light: 0x14181B, dark: 0xEEF1EC)
    static let secondaryInk = Color(light: 0x4A524F, dark: 0xA9B2AD)
    static let tertiaryInk = Color(light: 0x6B736F, dark: 0x7E8883)
    static let quiet = Color(light: 0xBCC3BD, dark: 0x3A4340)

    // Brand blue family
    static let signal = Color(light: 0x0F6B6F, dark: 0x5EC4C0)
    static let signalBright = Color(light: 0x0B585B, dark: 0x8ED8D4)
    static let ice = Color(light: 0xD6ECEA, dark: 0xBDE8E5)
    static let deep = Color(light: 0x0A4547, dark: 0x1F4E4C)
    static let cyan = Color(light: 0x0E8A8F, dark: 0x6ED3CF)
    /// Selection on the 3D body's muscle layer: soft blue, matching the selected-muscle glow.
    static let anatomy = Color(light: 0x3D5FD6, dark: 0x9DB4FF)

    // Physiological palette
    static let sleep = Color(light: 0x4A4FA8, dark: 0x9EA3F2)
    static let recovery = Color(light: 0x0F6B6F, dark: 0x5EC4C0)
    static let heart = Color(light: 0xB83A35, dark: 0xF07A6E)
    static let weight = Color(light: 0x5B63D3, dark: 0xA3ADFF)
    static let note = Color(light: 0xB8481A, dark: 0xF08A4B)
    static let review = note

    // Semantic aliases used across features.
    static let background = canvas
    static let card = surface
    static let cardRaised = raised
    static let stroke = hairline
    static let separator = hairline
    static let baseline = quiet
    static let accent = signal
    static let cobalt = signal
    static let cobaltDeep = deep
    static let warm = note
    static let amber = note
    static let coral = heart
    static let mint = recovery
    static let navy = deep

    static let accentSoft = signal.opacity(0.14)
    static let noteSoft = note.opacity(0.14)
    static let sleepSoft = sleep.opacity(0.14)
    static let reviewSoft = note.opacity(0.14)
    static let weightSoft = weight.opacity(0.14)

    /// The usual-range band behind charts: translucent brand blue.
    static let usualBand = Color(light: 0x0F6B6F, lightOpacity: 0.12, dark: 0x5EC4C0, darkOpacity: 0.14)

    // Sleep stages: one indigo ramp, deep darkest → REM lightest; awake is the only warm stage.
    static let sleepAwake = Color(light: 0xD9783F, dark: 0xF2A07B)
    static let sleepREM = Color(light: 0xA6AEE8, dark: 0xB4BEFF)
    static let sleepCore = Color(light: 0x6A70C9, dark: 0x7D84FF)
    static let sleepDeep = Color(light: 0x2F3488, dark: 0x4B45C9)

    static let heroGradient = LinearGradient(colors: [Color(light: 0xFBFBF8, dark: 0x161B1A), Color(light: 0xF4F5F0, dark: 0x121716)],
                                             startPoint: .top, endPoint: .bottom)
    static let askGradient = LinearGradient(colors: [signal, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradientTop = signal.opacity(0.16)

    /// Scores share one blue luminance ramp: low is deep and dim, high is bright. In light mode the
    /// ramp inverts (high = most saturated) so the most important value keeps the most contrast.
    static func band(_ band: ScoreBand?) -> Color {
        switch band {
        case .high: Color(light: 0x0F6B6F, dark: 0x5EC4C0)
        case .moderate: Color(light: 0x4C8E90, dark: 0x3E8E8B)
        case .low: Color(light: 0xA9C3C2, dark: 0x2A4E4C)
        case nil: tertiaryInk
        }
    }

    /// The glyph that says the band in shape, so status never depends on colour alone.
    static func bandSymbol(_ band: ScoreBand?) -> String {
        switch band {
        case .high: "arrow.up.right"
        case .moderate: "minus"
        case .low: "arrow.down.right"
        case nil: "ellipsis"
        }
    }

    static func sleep(_ stage: SleepStageStyle) -> Color {
        switch stage {
        case .awake: sleepAwake
        case .rem: sleepREM
        case .core: sleepCore
        case .deep: sleepDeep
        }
    }
}

enum SleepStageStyle: CaseIterable { case awake, rem, core, deep }

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }

    /// An adaptive colour: `light` in light appearance, `dark` in dark appearance.
    init(light: UInt32, lightOpacity: Double = 1, dark: UInt32, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

// MARK: - Spacing, radius, motion

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let section: CGFloat = 32
    static let page: CGFloat = 18
}

enum Radius {
    static let card: CGFloat = 24
    static let inner: CGFloat = 16
    static let chip: CGFloat = 10
}

enum Motion {
    /// iOS sheet easing.
    static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.45)
    static let snappy = Animation.snappy(duration: 0.25)
    static let reveal = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.9)
    /// A slow, breathing rhythm for "something is being understood" states.
    static let breathe = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)

    static func respecting(_ reduceMotion: Bool, _ animation: Animation = standard) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Typography

/// Geist for numerals and UI, Geist Mono for data labels, New York for the sentences that
/// interpret. Everything scales with Dynamic Type except the numerals inside instruments.
enum Typo {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .ultraLight, .thin, .light: "Geist-Light"
        case .medium: "Geist-Medium"
        case .semibold: "Geist-SemiBold"
        case .bold, .heavy, .black: "Geist-Bold"
        default: "Geist-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium", size: size, relativeTo: style)
    }

    /// Large calm numerals for scores and hero values (fixed size: they live inside instruments).
    static func score(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .custom(weight == .light || weight == .thin || weight == .ultraLight ? "Geist-Light" : "Geist-Regular", fixedSize: size)
            .monospacedDigit()
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        geist(size, weight, relativeTo: .title3).monospacedDigit()
    }

    static let display = Font.system(.largeTitle, design: .serif, weight: .regular)
    static let story = Font.system(.title3, design: .serif, weight: .regular)
    static let storySmall = Font.system(.body, design: .serif, weight: .regular)
    static let pageTitle = geist(32, .semibold, relativeTo: .largeTitle)
    static let title = geist(22, .semibold, relativeTo: .title2)
    static let sectionTitle = geist(17, .semibold, relativeTo: .headline)
    static let cardTitle = geist(15, .semibold, relativeTo: .subheadline)
    static let body = geist(16, .regular, relativeTo: .body)
    static let metric = geist(22, .medium, relativeTo: .title2).monospacedDigit()
    static let caption = geist(13, .regular, relativeTo: .footnote)
    static let eyebrow = mono(11, .medium, relativeTo: .caption2)
}

// MARK: - Surfaces

enum CardTone {
    case plain
    case tinted(Color)
    case hero
}

/// Cards: in dark mode depth comes from a luminance step and a 1 px top highlight; in light mode
/// from a short soft shadow. Tints are washes, never solid fills.
struct CardBackground: ViewModifier {
    var padding: CGFloat = Space.l
    var tone: CardTone = .plain
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background(shape) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Palette.topLight, borderColor], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .shadow(color: scheme == .dark ? .clear : Color(hex: 0x0B1220, opacity: 0.06), radius: 14, y: 6)
    }

    @ViewBuilder func background(_ shape: RoundedRectangle) -> some View {
        switch tone {
        case .plain: shape.fill(Palette.surface)
        case .tinted(let c):
            shape.fill(Palette.surface)
                .overlay(shape.fill(LinearGradient(colors: [c.opacity(scheme == .dark ? 0.12 : 0.07), c.opacity(0)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)))
        case .hero:
            shape.fill(Palette.heroGradient)
                .overlay(alignment: .top) {
                    RadialGradient(colors: [Palette.signal.opacity(scheme == .dark ? 0.32 : 0.10), .clear],
                                   center: .top, startRadius: 0, endRadius: 300)
                        .clipShape(shape)
                }
        }
    }

    var borderColor: Color {
        switch tone {
        case .hero: Palette.signal.opacity(0.22)
        case .tinted(let c): c.opacity(0.18)
        case .plain: Palette.hairline
        }
    }
}

extension View {
    func card(padding: CGFloat = Space.l, tone: CardTone = .plain) -> some View {
        modifier(CardBackground(padding: padding, tone: tone))
    }

    /// Liquid Glass on iOS 26+, a material fallback before that.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Glass button style on iOS 26+, bordered fallback before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// The canvas with a faint atmospheric glow at the top in the screen's signal colour, plus a
    /// barely visible measurement grid that fades out — the instrument's "glass".
    func blithBackground(wash: Color = Palette.heroGradientTop) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                Palette.canvas
                RadialGradient(colors: [wash, wash.opacity(0)], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 440)
                    .frame(height: 520)
                InstrumentGrid()
                    .frame(height: 360)
                    .mask(LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
    }
}

/// A faint 24 pt measurement grid, the only texture in Blith.
struct InstrumentGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 24
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Palette.hairline), lineWidth: 0.5)
        }
        .opacity(0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Chart helpers

extension LocalDate {
    /// Noon on this day in the current calendar — a safe x value for charts across DST.
    var chartDate: Date { startDate(in: .current).addingTimeInterval(12 * 3600) }
}
