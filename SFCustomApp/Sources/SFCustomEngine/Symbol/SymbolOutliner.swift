import Foundation

/// What a subpath of an anchor represents. Used to give every contour the
/// right winding so overlapping parts union correctly under the non-zero
/// fill rule that SF Symbols uses.
public enum ContourRole: Hashable, Sendable {
    /// A filled source shape. `shape` groups subpaths of one element.
    case fill(shape: Int, evenOdd: Bool)
    /// Outline of an open stroked path (one contour).
    case strokeOpen(shape: Int)
    /// One of the two contours of a closed stroked path.
    case strokeClosed(shape: Int, pair: Int)
}

/// Turns a whole icon (flattened shapes) into a single filled `PathModel`
/// suitable for an SF Symbol anchor: fills pass through (closed), strokes
/// are outlined with `CompatibleStroker` at `width × strokeScale`.
public enum SymbolOutliner {

    public struct Result: Sendable {
        public var path: PathModel
        /// Parallel to `path.subpaths`.
        public var roles: [ContourRole]
    }

    public static func outline(_ shapes: [SVGShape], strokeScale: Double) -> PathModel {
        outlineWithRoles(shapes, strokeScale: strokeScale).path
    }

    public static func outlineWithRoles(_ shapes: [SVGShape], strokeScale: Double) -> Result {
        var subpaths: [Subpath] = []
        var roles: [ContourRole] = []
        for (i, shape) in shapes.enumerated() {
            if shape.isFilled {
                for sp in shape.path.subpaths where !sp.segments.isEmpty {
                    subpaths.append(Subpath(segments: closedSegments(sp), isClosed: true))
                    roles.append(.fill(shape: i, evenOdd: shape.isEvenOdd))
                }
            }
            if var stroke = shape.stroke {
                stroke.width *= strokeScale
                for (pairIndex, sp) in shape.path.subpaths.enumerated() {
                    let contours = CompatibleStroker.outline(sp, style: stroke)
                    for c in contours {
                        subpaths.append(c)
                        roles.append(sp.isClosed ? .strokeClosed(shape: i, pair: pairIndex) : .strokeOpen(shape: i))
                    }
                }
            }
        }
        return Result(path: PathModel(subpaths: subpaths), roles: roles)
    }

    static func closedSegments(_ sp: Subpath) -> [Segment] {
        guard !sp.isClosed, let s = sp.start, let e = sp.end, s.distance(to: e) > 1e-9 else { return sp.segments }
        return sp.segments + [.line(e, s)]
    }

    // MARK: - Winding plan

    /// Decide, from one reference anchor (Regular), which subpaths to
    /// reverse so that: every "body" winds positive, every hole winds
    /// negative *within its own shape*. Apply the same plan to all
    /// anchors so their structure stays identical.
    public static func windingPlan(for result: Result) -> [Bool] {
        let sps = result.path.subpaths
        var flip = Array(repeating: false, count: sps.count)
        let areas = sps.map(\.signedArea)

        // Group indices by role key.
        var fillGroups: [Int: [Int]] = [:]
        var evenOddShapes: Set<Int> = []
        var closedPairs: [String: [Int]] = [:]
        for (i, role) in result.roles.enumerated() {
            switch role {
            case .fill(let shape, let evenOdd):
                fillGroups[shape, default: []].append(i)
                if evenOdd { evenOddShapes.insert(shape) }
            case .strokeOpen:
                flip[i] = areas[i] < 0
            case .strokeClosed(let shape, let pair):
                closedPairs["\(shape)-\(pair)", default: []].append(i)
            }
        }
        for (_, idx) in closedPairs {
            guard let big = idx.max(by: { abs(areas[$0]) < abs(areas[$1]) }) else { continue }
            for i in idx { flip[i] = (i == big) ? areas[i] < 0 : areas[i] > 0 }
        }
        for (shape, idx) in fillGroups {
            if evenOddShapes.contains(shape) {
                for i in idx {
                    let probe = sps[i].segments[0].point(at: 0.5)
                    var depth = 0
                    for j in idx where j != i && contains(sps[j], probe) { depth += 1 }
                    let wantPositive = depth % 2 == 0
                    flip[i] = (areas[i] > 0) != wantPositive
                }
            } else if let big = idx.max(by: { abs(areas[$0]) < abs(areas[$1]) }), areas[big] < 0 {
                for i in idx { flip[i] = true }
            }
        }
        return flip
    }

    public static func apply(plan: [Bool], to path: PathModel) -> PathModel {
        PathModel(subpaths: path.subpaths.enumerated().map { i, sp in
            i < plan.count && plan[i] ? sp.reversedKeepingStart() : sp
        })
    }

    /// Even-odd point-in-contour on a sampled polygon.
    static func contains(_ sp: Subpath, _ q: Point) -> Bool {
        var pts: [Point] = []
        for s in sp.segments { for k in 0..<8 { pts.append(s.point(at: Double(k) / 8)) } }
        var inside = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let a = pts[i], b = pts[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}

extension Subpath {
    /// Reverse direction but keep the same start point (closed subpaths),
    /// so reversing never shifts the start point between weights.
    public func reversedKeepingStart() -> Subpath {
        let r = reversed()
        guard isClosed, r.segments.count > 1 else { return r }
        // reversed() starts at the old end == old start for closed paths.
        return r
    }
}
