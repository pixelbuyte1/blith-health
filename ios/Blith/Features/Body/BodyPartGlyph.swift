import BlithCore
import SwiftUI

/// A small front-view figure with one part filled: the icon for a selected muscle or region.
/// Drawn in code so it follows the side (the person's right is on the viewer's left) and the
/// palette, and never glows.
struct BodyPartGlyph: View {
    let region: BodyRegion?
    var size: CGFloat = 26
    var accent: Color = Palette.anatomy
    var base: Color = Palette.quiet

    var body: some View {
        Canvas { ctx, canvas in
            let s = min(canvas.width, canvas.height) / 24
            ctx.translateBy(x: (canvas.width - 24 * s) / 2, y: (canvas.height - 24 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            for part in GlyphPart.figure { part.draw(in: ctx, color: base) }
            for part in GlyphPart.parts(for: region) { part.draw(in: ctx, color: accent) }
            if region == .upperBack || region == .lowerBack {
                // A spine line tells the back from the chest and abdomen.
                var spine = Path()
                spine.move(to: CGPoint(x: 12, y: region == .upperBack ? 6.8 : 10.6))
                spine.addLine(to: CGPoint(x: 12, y: region == .upperBack ? 9.6 : 13.0))
                ctx.stroke(spine, with: .color(base), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Parts of the glyph figure on a 24-point grid. `R` parts are the person's right (viewer's left).
private enum GlyphPart {
    case head, neck, chest, abdomen, hipR, hipL
    case shoulderR, shoulderL, upperArmR, upperArmL, elbowR, elbowL, forearmR, forearmL
    case wristR, wristL, handR, handL
    case thighR, thighL, kneeR, kneeL, lowerLegR, lowerLegL, ankleR, ankleL, footR, footL

    /// The resting silhouette (joints are only drawn when they are the selected part).
    static let figure: [GlyphPart] = [.head, .neck, .chest, .abdomen, .hipR, .hipL, .shoulderR, .shoulderL,
                                      .upperArmR, .upperArmL, .forearmR, .forearmL, .handR, .handL,
                                      .thighR, .thighL, .lowerLegR, .lowerLegL, .footR, .footL]

    static func parts(for region: BodyRegion?) -> [GlyphPart] {
        guard let region else { return [] }
        switch region {
        case .head: return [.head]
        case .neck: return [.neck]
        case .rightShoulder: return [.shoulderR]
        case .leftShoulder: return [.shoulderL]
        case .chest, .upperBack: return [.chest]
        case .abdomen, .lowerBack: return [.abdomen]
        case .rightUpperArm: return [.upperArmR]
        case .leftUpperArm: return [.upperArmL]
        case .rightElbow: return [.elbowR]
        case .leftElbow: return [.elbowL]
        case .rightForearm: return [.forearmR]
        case .leftForearm: return [.forearmL]
        case .rightWrist: return [.wristR]
        case .leftWrist: return [.wristL]
        case .rightHand: return [.handR]
        case .leftHand: return [.handL]
        case .hips: return [.hipR, .hipL]
        case .rightHip: return [.hipR]
        case .leftHip: return [.hipL]
        case .rightThigh: return [.thighR]
        case .leftThigh: return [.thighL]
        case .rightKnee: return [.kneeR]
        case .leftKnee: return [.kneeL]
        case .rightShin, .rightCalf: return [.lowerLegR]
        case .leftShin, .leftCalf: return [.lowerLegL]
        case .rightAnkle: return [.ankleR]
        case .leftAnkle: return [.ankleL]
        case .rightFoot: return [.footR]
        case .leftFoot: return [.footL]
        case .other: return []
        }
    }

    func draw(in ctx: GraphicsContext, color: Color) {
        switch self {
        case .head:
            ctx.fill(Path(ellipseIn: CGRect(x: 9.95, y: 1.0, width: 4.1, height: 4.3)), with: .color(color))
        case .neck:
            ctx.fill(Path(roundedRect: CGRect(x: 11.05, y: 5.0, width: 1.9, height: 1.5), cornerRadius: 0.5), with: .color(color))
        case .chest:
            ctx.fill(Self.polygon([(8.7, 6.3), (15.3, 6.3), (14.9, 10.0), (9.1, 10.0)]), with: .color(color))
        case .abdomen:
            ctx.fill(Self.polygon([(9.15, 10.25), (14.85, 10.25), (14.45, 13.3), (9.55, 13.3)]), with: .color(color))
        case .hipR:
            ctx.fill(Self.polygon([(9.5, 13.55), (11.9, 13.55), (11.9, 15.2), (9.2, 15.2)]), with: .color(color))
        case .hipL:
            ctx.fill(Self.polygon([(12.1, 13.55), (14.5, 13.55), (14.8, 15.2), (12.1, 15.2)]), with: .color(color))
        case .shoulderR: Self.dot(ctx, 8.05, 7.2, 1.35, color)
        case .shoulderL: Self.dot(ctx, 15.95, 7.2, 1.35, color)
        case .upperArmR: Self.limb(ctx, (7.3, 8.3), (6.5, 11.6), 2.1, color)
        case .upperArmL: Self.limb(ctx, (16.7, 8.3), (17.5, 11.6), 2.1, color)
        case .elbowR: Self.dot(ctx, 6.45, 11.85, 1.15, color)
        case .elbowL: Self.dot(ctx, 17.55, 11.85, 1.15, color)
        case .forearmR: Self.limb(ctx, (6.4, 12.2), (5.7, 15.2), 1.8, color)
        case .forearmL: Self.limb(ctx, (17.6, 12.2), (18.3, 15.2), 1.8, color)
        case .wristR: Self.dot(ctx, 5.65, 15.45, 0.9, color)
        case .wristL: Self.dot(ctx, 18.35, 15.45, 0.9, color)
        case .handR: Self.dot(ctx, 5.5, 16.5, 1.05, color)
        case .handL: Self.dot(ctx, 18.5, 16.5, 1.05, color)
        case .thighR: Self.limb(ctx, (10.5, 15.6), (10.25, 19.0), 2.5, color)
        case .thighL: Self.limb(ctx, (13.5, 15.6), (13.75, 19.0), 2.5, color)
        case .kneeR: Self.dot(ctx, 10.2, 19.3, 1.25, color)
        case .kneeL: Self.dot(ctx, 13.8, 19.3, 1.25, color)
        case .lowerLegR: Self.limb(ctx, (10.2, 19.9), (10.3, 22.2), 2.0, color)
        case .lowerLegL: Self.limb(ctx, (13.8, 19.9), (13.7, 22.2), 2.0, color)
        case .ankleR: Self.dot(ctx, 10.3, 22.45, 0.85, color)
        case .ankleL: Self.dot(ctx, 13.7, 22.45, 0.85, color)
        case .footR: Self.limb(ctx, (10.3, 23.0), (9.2, 23.1), 1.3, color)
        case .footL: Self.limb(ctx, (13.7, 23.0), (14.8, 23.1), 1.3, color)
        }
    }

    static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    static func dot(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    static func limb(_ ctx: GraphicsContext, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ width: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: a.0, y: a.1))
        p.addLine(to: CGPoint(x: b.0, y: b.1))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
