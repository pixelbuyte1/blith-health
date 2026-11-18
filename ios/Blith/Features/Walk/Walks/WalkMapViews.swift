import BlithCore
import CoreLocation
import MapKit
import SwiftUI

extension TrackPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// A walk's route on the map. Each stretch of good GPS is drawn on its own, so a GPS gap is never
/// bridged by a straight line. Markers sit where each km (or mile) was reached.
struct WalkRouteMap: View {
    let segments: [[TrackPoint]]
    var markers: [TrackPoint] = []
    /// Live walk: keep the person in view and show the location button.
    var followsUser = false
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        if followsUser {
            map.mapControls { MapUserLocationButton() }
                .onAppear { position = .userLocation(fallback: .automatic) }
        } else {
            map
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate))
                    .stroke(Palette.signal, lineWidth: 5)
            }
            ForEach(Array(markers.enumerated()), id: \.offset) { index, point in
                Annotation("\(index + 1)", coordinate: point.coordinate) {
                    Text("\(index + 1)")
                        .font(Typo.number(11, weight: .semibold))
                        .foregroundStyle(Palette.canvas)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Palette.ink))
                }
                .annotationTitles(.hidden)
            }
            if let first = segments.first?.first {
                Annotation("Start", coordinate: first.coordinate) {
                    Circle().strokeBorder(Palette.signal, lineWidth: 3)
                        .background(Circle().fill(Palette.canvas))
                        .frame(width: 14, height: 14)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }
}

/// A small drawing of a walk's shape for lists (no map tiles). Gaps stay open.
struct TrackShape: Shape {
    let segments: [[TrackPoint]]

    func path(in rect: CGRect) -> Path {
        let all = segments.joined()
        guard let minLat = all.map(\.latitude).min(), let maxLat = all.map(\.latitude).max(),
              let minLon = all.map(\.longitude).min(), let maxLon = all.map(\.longitude).max() else { return Path() }
        let k = cos((minLat + maxLat) / 2 * .pi / 180)
        let w = max((maxLon - minLon) * k, 1e-9), h = max(maxLat - minLat, 1e-9)
        let scale = min(rect.width / w, rect.height / h)
        let ox = rect.midX - w * scale / 2, oy = rect.midY + h * scale / 2
        var path = Path()
        for segment in segments where segment.count > 1 {
            let step = max(1, segment.count / 120)
            var first = true
            for (i, p) in segment.enumerated() where i % step == 0 || i == segment.count - 1 {
                let pt = CGPoint(x: ox + (p.longitude - minLon) * k * scale, y: oy - (p.latitude - minLat) * scale)
                if first {
                    path.move(to: pt)
                    first = false
                } else {
                    path.addLine(to: pt)
                }
            }
        }
        return path
    }
}

/// The route thumbnail used in lists: the walk's shape, or a walking glyph when there's no map.
struct WalkThumbnail: View {
    let segments: [[TrackPoint]]?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.raised)
            if let segments, !segments.isEmpty {
                TrackShape(segments: segments)
                    .stroke(Palette.signal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .padding(9)
            } else {
                BLIcon(name: "bl.walk", size: 20).foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }
}
