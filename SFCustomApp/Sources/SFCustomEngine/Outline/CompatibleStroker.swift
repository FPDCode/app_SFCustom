import Foundation

/// Converts strokes into filled outlines whose **structure never depends on
/// the stroke width**.
///
/// Why: SF Symbols interpolates the in-between weights from three anchors
/// (Ultralight-S, Regular-S, Black-S), and that only works when all three
/// have the same subpaths, in the same order, with the same number of
/// segments and the same start points. Generic "outline stroke" algorithms
/// (Illustrator, Figma, CoreGraphics) add or drop points depending on the
/// width — inner corners collapse at Black, extra points appear at
/// Ultralight. This stroker makes every structural decision from the
/// *source* geometry only, so outlining one path at 2, 7 and 13 units
/// always yields equal `PathModel.signature()`s.
///
/// Rules:
///  • Every source segment is split into a fixed number of pieces derived
///    from its own curvature (never from the width).
///  • Each piece offsets to exactly one cubic per side.
///  • Each corner (non-smooth vertex) emits exactly 2 cubics per side,
///    whatever the join type or width. Whether a side is "inner" depends on
///    the turn direction, which is a property of the source.
///  • Miter-vs-bevel depends only on the corner angle (the miter ratio is
///    width-independent), so it is identical for every weight.
///  • Inner offsets that would invert (radius smaller than half the width)
///    get their handles clamped to zero length — points are *never* removed.
///  • Caps: butt = 2, round = 2, square = 3 cubics.
///  • Outline start = offset of the source start point, left side first;
///    subpath order follows source order.
public enum CompatibleStroker {

    /// Corners whose tangent change is below this angle are treated as smooth.
    static let smoothAngle = 0.5 * Double.pi / 180
    /// Max turning per piece before a source segment is split.
    static let maxTurnPerPiece = Double.pi / 6
    static let maxPiecesPerSegment = 8

    // MARK: Public API

    public static func outline(_ path: PathModel, style: StrokeStyle) -> PathModel {
        PathModel(subpaths: path.subpaths.flatMap { outline($0, style: style) })
    }

    /// Outline one subpath. Open → 1 closed contour. Closed → 2 closed
    /// contours (outer + inner, opposite winding so the hole stays empty
    /// under the non-zero fill rule).
    public static func outline(_ subpath: Subpath, style: StrokeStyle) -> [Subpath] {
        let d = max(style.width, 0) / 2
        let pieces = prepare(subpath)
        guard !pieces.isEmpty else { return [] }

        if subpath.isClosed {
            let outer = offsetSide(pieces, d: d, closed: true, style: style)
            let reversed = pieces.reversed().map { $0.reversed() }
            let inner = offsetSide(Array(reversed), d: d, closed: true, style: style)
            return [close(outer), close(inner)]
        } else {
            var contour = offsetSide(pieces, d: d, closed: false, style: style)
            contour += cap(at: pieces.last!.p3, tangent: pieces.last!.endTangent ?? Point(1, 0), d: d, style: style.cap)
            let reversed = Array(pieces.reversed().map { $0.reversed() })
            contour += offsetSide(reversed, d: d, closed: false, style: style)
            contour += cap(at: reversed.last!.p3, tangent: reversed.last!.endTangent ?? Point(-1, 0), d: d, style: style.cap)
            return [close(contour)]
        }
    }

    // MARK: Source preparation (width-independent)

    static func prepare(_ subpath: Subpath) -> [Segment] {
        var out: [Segment] = []
        for seg in subpath.segments where !seg.isDegenerate {
            let n = pieceCount(for: seg)
            if n == 1 { out.append(seg); continue }
            var rest = seg
            for i in 0..<(n - 1) {
                // Split the remainder so pieces are equal in original t.
                let t = 1.0 / Double(n - i)
                let (a, b) = rest.split(at: t)
                out.append(a)
                rest = b
            }
            out.append(rest)
        }
        return out
    }

    static func pieceCount(for seg: Segment) -> Int {
        let turn = seg.totalTurning
        let n = Int(ceil(turn / maxTurnPerPiece - 1e-9))
        return min(maxPiecesPerSegment, max(1, n))
    }

    // MARK: Offsetting one side

    /// Left-side offset (normal = tangent.perpendicular) of a run of pieces,
    /// including corner joins between pieces. For closed runs the closing
    /// corner (last → first) is included, ending where the run started.
    static func offsetSide(_ pieces: [Segment], d: Double, closed: Bool, style: StrokeStyle) -> [Segment] {
        var out: [Segment] = []
        for (i, piece) in pieces.enumerated() {
            out.append(offset(piece, d: d))
            let hasNext = i + 1 < pieces.count || closed
            guard hasNext else { break }
            let next = pieces[(i + 1) % pieces.count]
            out += join(at: piece.p3,
                        tIn: piece.endTangent ?? Point(1, 0),
                        tOut: next.startTangent ?? Point(1, 0),
                        d: d, style: style)
        }
        return out
    }

    /// Offset one piece by `d` along its left normal, as a single cubic.
    /// Endpoints are exact; handle lengths are fitted so the curve passes
    /// through the offset of the source midpoint.
    ///
    /// On the concave (inner) side the offset distance is limited to the
    /// local radius of curvature. Without that, a tight curve stroked wider
    /// than its radius flips inside out and punches a hole into the fill
    /// (e.g. a small circle at Black). With it, the inner edge collapses
    /// onto the centre of curvature instead — same points, zero area.
    static func offset(_ s: Segment, d: Double) -> Segment {
        let t0 = s.startTangent ?? Point(1, 0)
        let t1 = s.endTangent ?? t0
        let q0 = s.p0 + t0.perpendicular * limitedDistance(s, at: 0, d: d)
        let q3 = s.p3 + t1.perpendicular * limitedDistance(s, at: 1, d: d)
        let a = s.p1 - s.p0
        let b = s.p2 - s.p3
        let ab = a + b
        var k = 1.0
        let abLen2 = ab.dot(ab)
        if abLen2 > 1e-18, let tm = s.tangent(at: 0.5) {
            let target = s.point(at: 0.5) + tm.perpendicular * limitedDistance(s, at: 0.5, d: d)
            k = (target - (q0 + q3) / 2).dot(ab) * 8 / (3 * abLen2)
        }
        // Remaining inversions: clamp handles instead of dropping points so
        // the structure stays identical.
        k = min(max(k, 0), 8)
        return Segment(q0, q0 + a * k, q3 + b * k, q3)
    }

    /// `d`, capped at the radius of curvature when `t` lies on the side the
    /// curve bends toward (left normal side, positive curvature).
    static func limitedDistance(_ s: Segment, at t: Double, d: Double) -> Double {
        guard let k = s.curvature(at: t), k > 1e-12 else { return d }
        return min(d, 1 / k)
    }

    // MARK: Joins — always 0 (smooth) or 2 cubics (corner)

    static func isCorner(tIn: Point, tOut: Point) -> Bool {
        abs(atan2(tIn.cross(tOut), tIn.dot(tOut))) >= smoothAngle
    }

    static func join(at v: Point, tIn: Point, tOut: Point, d: Double, style: StrokeStyle) -> [Segment] {
        guard isCorner(tIn: tIn, tOut: tOut) else { return [] }
        let nIn = tIn.perpendicular, nOut = tOut.perpendicular
        let a = v + nIn * d
        let b = v + nOut * d
        let theta = atan2(tIn.cross(tOut), tIn.dot(tOut)) // signed turn
        let isInner = theta > 0 // turning toward the left normal

        if isInner {
            // Route through the pivot; non-zero fill keeps the overlap solid.
            return [.line(a, v), .line(v, b)]
        }

        switch style.join {
        case .round:
            return arc(center: v, from: nIn, sweep: theta, radius: d, pieces: 2)
        case .miter:
            let half = abs(theta) / 2
            let ratio = 1 / max(cos(half), 1e-9)
            if ratio <= style.miterLimit, let bis = (nIn + nOut).normalized {
                let m = v + bis * (d * ratio)
                return [.line(a, m), .line(m, b)]
            }
            fallthrough
        case .bevel:
            let mid = a.lerp(to: b, 0.5)
            return [.line(a, mid), .line(mid, b)]
        }
    }

    // MARK: Caps

    /// Cap at the end of a run travelling along `tangent`, from the left
    /// offset point to the right offset point.
    static func cap(at p: Point, tangent t: Point, d: Double, style: LineCap) -> [Segment] {
        let n = t.perpendicular
        let l = p + n * d, r = p - n * d
        switch style {
        case .butt:
            return [.line(l, p), .line(p, r)]
        case .square:
            let l2 = l + t * d, r2 = r + t * d
            return [.line(l, l2), .line(l2, r2), .line(r2, r)]
        case .round:
            return arc(center: p, from: n, sweep: -Double.pi, radius: d, pieces: 2)
        }
    }

    // MARK: Helpers

    /// Circular arc around `center`, starting in direction `from` (unit),
    /// sweeping `sweep` radians (signed, math orientation), as `pieces` cubics.
    static func arc(center c: Point, from u: Point, sweep: Double, radius r: Double, pieces: Int) -> [Segment] {
        let start = atan2(u.y, u.x)
        let step = sweep / Double(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)
        var out: [Segment] = []
        for i in 0..<pieces {
            let a0 = start + step * Double(i), a1 = a0 + step
            let p0 = c + Point(cos(a0), sin(a0)) * r
            let p3 = c + Point(cos(a1), sin(a1)) * r
            let d0 = Point(-sin(a0), cos(a0)) * r
            let d1 = Point(-sin(a1), cos(a1)) * r
            out.append(Segment(p0, p0 + d0 * k, p3 - d1 * k, p3))
        }
        return out
    }

    /// Make a contour contiguous (snap each start onto the previous end)
    /// and close it.
    static func close(_ segs: [Segment]) -> Subpath {
        var s = segs
        for i in 1..<max(s.count, 1) where i < s.count {
            let delta = s[i - 1].p3 - s[i].p0
            s[i].p0 = s[i - 1].p3
            s[i].p1 = s[i].p1 + delta
        }
        if let first = s.first, var last = s.last {
            let delta = first.p0 - last.p3
            last.p3 = first.p0
            last.p2 = last.p2 + delta
            s[s.count - 1] = last
        }
        return Subpath(segments: s, isClosed: true)
    }
}

/// Turns a whole icon (flattened shapes) into a single filled `PathModel`
/// suitable for an SF Symbol anchor: fills pass through, strokes are
/// outlined with `CompatibleStroker` at `width × strokeScale`.
public enum SymbolOutliner {

    public static func outline(_ shapes: [SVGShape], strokeScale: Double) -> PathModel {
        var out = PathModel()
        for shape in shapes {
            if shape.isFilled {
                // Ensure fills are closed so they're valid symbol geometry.
                out.append(PathModel(subpaths: shape.path.subpaths.map {
                    Subpath(segments: closedSegments($0), isClosed: true)
                }))
            }
            if var stroke = shape.stroke {
                stroke.width *= strokeScale
                out.append(CompatibleStroker.outline(shape.path, style: stroke))
            }
        }
        return out
    }

    static func closedSegments(_ sp: Subpath) -> [Segment] {
        guard !sp.isClosed, let s = sp.start, let e = sp.end, s.distance(to: e) > 1e-9 else { return sp.segments }
        return sp.segments + [.line(e, s)]
    }
}
