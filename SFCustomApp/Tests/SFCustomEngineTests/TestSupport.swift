import Foundation
@testable import SFCustomEngine

enum Fixtures {
    /// Repo root (…/app_SFCustom), resolved from this file's location.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent() // SFCustomEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SFCustomApp
            .deletingLastPathComponent() // app_SFCustom
    }

    static var appleSamplesDir: URL {
        repoRoot.appendingPathComponent("SF Samples/SF Symbol_Template/more SF Symbol Samples")
    }

    static func appleSamples() throws -> [(name: String, svg: String)] {
        let files = try FileManager.default.contentsOfDirectory(atPath: appleSamplesDir.path)
            .filter { $0.hasSuffix(".svg") }
            .sorted()
        return try files.map { f in
            (f, try String(contentsOf: appleSamplesDir.appendingPathComponent(f), encoding: .utf8))
        }
    }

    /// Hand-made stroked sources that exercise every structural branch:
    /// sharp miters, miter-limit bevels, round joins/caps, square caps,
    /// tight curves (inner collapse at Black), closed shapes and arcs.
    static let strokedSources: [(name: String, d: String, style: StrokeStyle)] = [
        ("zigzag-miter", "M10 60 L30 20 L50 60 L70 20 L90 60", StrokeStyle(width: 7, join: .miter, cap: .butt)),
        ("spike-beyond-miter-limit", "M10 60 L50 10 L90 60", StrokeStyle(width: 7, join: .miter, cap: .square, miterLimit: 1.5)),
        ("zigzag-round", "M10 60 L30 20 L50 60 L70 20", StrokeStyle(width: 7, join: .round, cap: .round)),
        ("heart-ish", "M50 85 C10 55 5 30 25 18 C38 10 48 18 50 28 C52 18 62 10 75 18 C95 30 90 55 50 85 Z",
         StrokeStyle(width: 7, join: .round, cap: .round)),
        ("tight-s-curve", "M20 80 C20 20 80 80 80 20", StrokeStyle(width: 7, join: .miter, cap: .round)),
        ("small-circle-arc", "M45 50 A5 5 0 1 1 55 50 A5 5 0 1 1 45 50 Z", StrokeStyle(width: 7, join: .round, cap: .butt)),
        ("rounded-rect", "M20 10 H80 A10 10 0 0 1 90 20 V80 A10 10 0 0 1 80 90 H20 A10 10 0 0 1 10 80 V20 A10 10 0 0 1 20 10 Z",
         StrokeStyle(width: 7, join: .miter, cap: .butt)),
        ("bevel-triangle", "M10 80 L50 15 L90 80 Z", StrokeStyle(width: 7, join: .bevel, cap: .butt)),
        ("quad-and-smooth", "M10 50 Q30 10 50 50 T90 50", StrokeStyle(width: 7, join: .miter, cap: .square)),
    ]

    /// Talk recipe: Ultralight 2 · Regular 7 · Black 13 — plus extremes.
    static let widths: [Double] = [0.5, 2, 7, 13, 30]
}

// MARK: - Geometry helpers for coverage tests

enum Coverage {
    /// Flatten a path into polylines.
    static func polylines(_ p: PathModel, steps: Int = 24) -> [[Point]] {
        p.subpaths.map { sp in
            var pts: [Point] = []
            for s in sp.segments {
                for i in 0..<steps { pts.append(s.point(at: Double(i) / Double(steps))) }
            }
            if let last = sp.segments.last { pts.append(last.p3) }
            return pts
        }
    }

    /// Non-zero winding number of `q` against all closed contours.
    static func winding(_ q: Point, in path: PathModel) -> Int {
        var w = 0
        for poly in polylines(path) where poly.count > 2 {
            for i in 0..<poly.count {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                if a.y <= q.y {
                    if b.y > q.y, (b - a).cross(q - a) > 0 { w += 1 }
                } else if b.y <= q.y, (b - a).cross(q - a) < 0 {
                    w -= 1
                }
            }
        }
        return w
    }

    static func distanceToCenterline(_ q: Point, _ source: PathModel) -> Double {
        var best = Double.infinity
        for poly in polylines(source, steps: 64) {
            for i in 0..<(poly.count - 1) {
                best = min(best, distance(q, poly[i], poly[i + 1]))
            }
        }
        return best
    }

    static func distance(_ q: Point, _ a: Point, _ b: Point) -> Double {
        let ab = b - a
        let len2 = ab.dot(ab)
        guard len2 > 0 else { return q.distance(to: a) }
        let t = min(1, max(0, (q - a).dot(ab) / len2))
        return q.distance(to: a + ab * t)
    }
}
