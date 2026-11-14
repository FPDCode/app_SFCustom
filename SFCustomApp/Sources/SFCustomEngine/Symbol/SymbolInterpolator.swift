import Foundation

/// Point-for-point interpolation between compatible anchors — the same
/// thing SF Symbols does to produce Thin, Light, Medium … from
/// Ultralight / Regular / Black.
public enum SymbolInterpolator {

    /// The 9 SF weights, as positions on the 0…2 anchor axis
    /// (0 = Ultralight, 1 = Regular, 2 = Black).
    public static let weightPositions: [(name: String, position: Double)] = [
        ("Ultralight", 0), ("Thin", 1.0 / 3), ("Light", 2.0 / 3), ("Regular", 1),
        ("Medium", 1.2), ("Semibold", 1.4), ("Bold", 1.6), ("Heavy", 1.8), ("Black", 2),
    ]

    /// Linear blend; `nil` when the paths aren't compatible.
    public static func lerp(_ a: PathModel, _ b: PathModel, _ t: Double) -> PathModel? {
        guard a.signature() == b.signature() else { return nil }
        return PathModel(subpaths: zip(a.subpaths, b.subpaths).map { sa, sb in
            Subpath(segments: zip(sa.segments, sb.segments).map { x, y in
                Segment(x.p0.lerp(to: y.p0, t), x.p1.lerp(to: y.p1, t), x.p2.lerp(to: y.p2, t), x.p3.lerp(to: y.p3, t))
            }, isClosed: sa.isClosed)
        })
    }

    /// Blend along Ultralight (0) → Regular (1) → Black (2).
    public static func interpolate(ultralight: PathModel, regular: PathModel, black: PathModel,
                                   at position: Double) -> PathModel? {
        let p = min(max(position, 0), 2)
        return p <= 1 ? lerp(ultralight, regular, p) : lerp(regular, black, p - 1)
    }

    public static func interpolate(_ a: Double, _ b: Double, _ c: Double, at position: Double) -> Double {
        let p = min(max(position, 0), 2)
        return p <= 1 ? a + (b - a) * p : b + (c - b) * (p - 1)
    }
}
