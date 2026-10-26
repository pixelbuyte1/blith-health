import SwiftUI

/// Width-adaptive page layout. iPhone and iPhone Duo's outer display are compact width; Duo's inner
/// display is regular width (and ignores the app's supported orientations), so a page shows more of
/// the same hierarchy side by side there instead of stretching one column across the screen.

/// One column on compact width; `primary` and `secondary` side by side on regular width.
/// On compact width the views join the parent stack directly, so scroll ids and spacing stay as they were.
struct AdaptiveColumns<Primary: View, Secondary: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let spacing: CGFloat
    private let primary: Primary
    private let secondary: Secondary

    init(spacing: CGFloat = Space.l, @ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.spacing = spacing
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: spacing) { primary }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: spacing) { secondary }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Group {
                primary
                secondary
            }
        }
    }
}

/// Caps a single-column page at a readable width on regular width and centres it.
private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? 680 : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// See `ReadableWidth`.
    func readableWidth() -> some View { modifier(ReadableWidth()) }
}
