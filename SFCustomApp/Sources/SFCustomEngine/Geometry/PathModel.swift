import Foundation

// MARK: - Point

/// A 2D point / vector in SVG user space (y grows downward).
public struct Point: Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(0, 0)

    public static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
    public static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
    public static func * (a: Point, s: Double) -> Point { Point(a.x * s, a.y * s) }
    public static func * (s: Double, a: Point) -> Point { Point(a.x * s, a.y * s) }
    public static func / (a: Point, s: Double) -> Point { Point(a.x / s, a.y / s) }
    public static prefix func - (a: Point) -> Point { Point(-a.x, -a.y) }

    public var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector, or `nil` when the vector is (numerically) zero.
    public var normalized: Point? {
        let l = length
        return l > 1e-12 ? self / l : nil
    }

    /// Perpendicular vector rotated +90° in math orientation: (-y, x).
    /// Used consistently as the "left" side by the stroker.
    public var perpendicular: Point { Point(-y, x) }

    public func dot(_ o: Point) -> Double { x * o.x + y * o.y }
    public func cross(_ o: Point) -> Double { x * o.y - y * o.x }
    public func distance(to o: Point) -> Double { (self - o).length }

    public func lerp(to o: Point, _ t: Double) -> Point { self + (o - self) * t }

    public var description: String { "(\(x), \(y))" }
}

// MARK: - Segment

/// One cubic Bézier segment. Every segment in the engine is cubic: lines are
/// stored as cubics with collinear handles at 1/3 and 2/3. That makes the
/// command sequence of a path independent of whether a piece is "straight",
/// which is one of the conditions for SF Symbol interpolation (handles count
/// as points; an `L` in one weight against a `C` in another breaks it).
public struct Segment: Hashable, Sendable {
    public var p0: Point
    public var p1: Point
    public var p2: Point
    public var p3: Point

    public init(_ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    /// A straight line expressed as a cubic.
    public static func line(_ a: Point, _ b: Point) -> Segment {
        Segment(a, a.lerp(to: b, 1.0 / 3.0), a.lerp(to: b, 2.0 / 3.0), b)
    }

    /// Quadratic → cubic (exact).
    public static func quadratic(_ a: Point, _ c: Point, _ b: Point) -> Segment {
        Segment(a, a + (c - a) * (2.0 / 3.0), b + (c - b) * (2.0 / 3.0), b)
    }

    public func point(at t: Double) -> Point {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return p0 * a + p1 * b + p2 * c + p3 * d
    }

    public func derivative(at t: Double) -> Point {
        let mt = 1 - t
        return (p1 - p0) * (3 * mt * mt) + (p2 - p1) * (6 * mt * t) + (p3 - p2) * (3 * t * t)
    }

    public func secondDerivative(at t: Double) -> Point {
        (p2 - p1 * 2 + p0) * (6 * (1 - t)) + (p3 - p2 * 2 + p1) * (6 * t)
    }

    /// Signed curvature (math orientation: positive = bending toward the
    /// left normal `tangent.perpendicular`). `nil` where the speed is zero.
    public func curvature(at t: Double) -> Double? {
        let d1 = derivative(at: t)
        let speed = d1.length
        guard speed > 1e-9 else { return nil }
        return d1.cross(secondDerivative(at: t)) / (speed * speed * speed)
    }

    /// Unit tangent at t = 0, robust against coincident handles.
    public var startTangent: Point? {
        (p1 - p0).normalized ?? (p2 - p0).normalized ?? (p3 - p0).normalized
    }

    /// Unit tangent at t = 1, robust against coincident handles.
    public var endTangent: Point? {
        (p3 - p2).normalized ?? (p3 - p1).normalized ?? (p3 - p0).normalized
    }

    /// Unit tangent anywhere, falling back to the end tangents at degenerate spots.
    public func tangent(at t: Double) -> Point? {
        if let d = derivative(at: t).normalized { return d }
        if t < 0.5 { return startTangent }
        return endTangent
    }

    /// True when all four points coincide (zero-length segment).
    public var isDegenerate: Bool {
        let eps = 1e-9
        return p0.distance(to: p1) < eps && p0.distance(to: p2) < eps && p0.distance(to: p3) < eps
    }

    /// De Casteljau split.
    public func split(at t: Double) -> (Segment, Segment) {
        let a = p0.lerp(to: p1, t), b = p1.lerp(to: p2, t), c = p2.lerp(to: p3, t)
        let d = a.lerp(to: b, t), e = b.lerp(to: c, t)
        let f = d.lerp(to: e, t)
        return (Segment(p0, a, d, f), Segment(f, e, c, p3))
    }

    public func reversed() -> Segment { Segment(p3, p2, p1, p0) }

    public func transformed(by m: AffineTransform2D) -> Segment {
        Segment(m.apply(p0), m.apply(p1), m.apply(p2), m.apply(p3))
    }

    /// Total absolute turning of the tangent along the segment (radians),
    /// sampled. Depends only on geometry, never on stroke width.
    public var totalTurning: Double {
        var total = 0.0
        var prev: Point? = startTangent
        let steps = 16
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            guard let cur = tangent(at: t) else { continue }
            if let p = prev {
                total += abs(atan2(p.cross(cur), p.dot(cur)))
            }
            prev = cur
        }
        return total
    }
}

// MARK: - Subpath / PathModel

/// A contiguous run of cubic segments, optionally closed.
public struct Subpath: Hashable, Sendable {
    public var segments: [Segment]
    public var isClosed: Bool

    public init(segments: [Segment], isClosed: Bool) {
        self.segments = segments
        self.isClosed = isClosed
    }

    public var start: Point? { segments.first?.p0 }
    public var end: Point? { segments.last?.p3 }

    public func reversed() -> Subpath {
        Subpath(segments: segments.reversed().map { $0.reversed() }, isClosed: isClosed)
    }

    /// Signed area (shoelace on the control polygon of a fine sampling).
    /// Positive = counter-clockwise in math orientation.
    public var signedArea: Double {
        var pts: [Point] = []
        for s in segments {
            for i in 0..<8 { pts.append(s.point(at: Double(i) / 8)) }
        }
        guard pts.count > 2 else { return 0 }
        var a = 0.0
        for i in 0..<pts.count {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    /// Mean of the sampled points — cheap centroid used for subpath matching.
    public var centroid: Point {
        var sum = Point.zero
        var n = 0
        for s in segments {
            for i in 0..<4 { sum = sum + s.point(at: Double(i) / 4); n += 1 }
        }
        return n > 0 ? sum / Double(n) : .zero
    }

    public var bounds: Rect {
        Rect.enclosing(segments.flatMap { [$0.p0, $0.p1, $0.p2, $0.p3] })
    }
}

/// A full path: an ordered list of subpaths. This is the unit the SF Symbol
/// interpolation rules apply to (same subpaths, same order, same segment
/// counts, same start points across Ultralight / Regular / Black).
public struct PathModel: Hashable, Sendable {
    public var subpaths: [Subpath]

    public init(subpaths: [Subpath] = []) {
        self.subpaths = subpaths
    }

    public var isEmpty: Bool { subpaths.allSatisfy { $0.segments.isEmpty } }

    public mutating func append(_ other: PathModel) {
        subpaths.append(contentsOf: other.subpaths)
    }

    public func transformed(by m: AffineTransform2D) -> PathModel {
        PathModel(subpaths: subpaths.map {
            Subpath(segments: $0.segments.map { $0.transformed(by: m) }, isClosed: $0.isClosed)
        })
    }

    /// Structural fingerprint: one entry per subpath, `M` + one `C` per
    /// segment + `Z` when closed. Two paths with equal signatures have the
    /// same command sequence and can be interpolated point-for-point.
    public func signature() -> [[Character]] {
        subpaths.map { sp in
            var s: [Character] = ["M"]
            s.append(contentsOf: Array(repeating: "C", count: sp.segments.count))
            if sp.isClosed { s.append("Z") }
            return s
        }
    }

    public var bounds: Rect {
        Rect.enclosing(subpaths.flatMap { sp in sp.segments.flatMap { [$0.p0, $0.p1, $0.p2, $0.p3] } })
    }
}

// MARK: - Rect

public struct Rect: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { max(0, maxX - minX) }
    public var height: Double { max(0, maxY - minY) }
    public var center: Point { Point((minX + maxX) / 2, (minY + maxY) / 2) }

    public static let null = Rect(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    public static func enclosing(_ pts: [Point]) -> Rect {
        var r = Rect.null
        for p in pts {
            r.minX = min(r.minX, p.x); r.minY = min(r.minY, p.y)
            r.maxX = max(r.maxX, p.x); r.maxY = max(r.maxY, p.y)
        }
        return r
    }
}

// MARK: - Tight bounds

extension Segment {
    /// Exact bounding box of the curve (not the control polygon), from the
    /// roots of the derivative.
    public var tightBounds: Rect {
        var pts = [p0, p3]
        for t in Self.extremaT(p0.x, p1.x, p2.x, p3.x) + Self.extremaT(p0.y, p1.y, p2.y, p3.y) {
            pts.append(point(at: t))
        }
        return Rect.enclosing(pts)
    }

    /// Parameter values in (0,1) where the 1-D cubic's derivative is zero.
    static func extremaT(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> [Double] {
        // B'(t)/3 = (b-a)(1-t)² + 2(c-b)(1-t)t + (d-c)t² = A t² + B t + C
        let qa = (b - a) - 2 * (c - b) + (d - c)
        let qb = 2 * ((c - b) - (b - a))
        let qc = b - a
        var roots: [Double] = []
        if abs(qa) < 1e-12 {
            if abs(qb) > 1e-12 { roots.append(-qc / qb) }
        } else {
            let disc = qb * qb - 4 * qa * qc
            if disc >= 0 {
                let r = disc.squareRoot()
                roots.append((-qb + r) / (2 * qa))
                roots.append((-qb - r) / (2 * qa))
            }
        }
        return roots.filter { $0 > 0 && $0 < 1 }
    }
}

extension Rect {
    public func union(_ o: Rect) -> Rect {
        Rect(minX: min(minX, o.minX), minY: min(minY, o.minY), maxX: max(maxX, o.maxX), maxY: max(maxY, o.maxY))
    }

    public var isNull: Bool { minX > maxX || minY > maxY }
}

extension PathModel {
    /// Exact bounds of the drawn geometry.
    public var tightBounds: Rect {
        var r = Rect.null
        for sp in subpaths { for s in sp.segments { r = r.union(s.tightBounds) } }
        return r
    }
}
