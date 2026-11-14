import Foundation

/// Parses SVG path data (`d` attribute) into a `PathModel` of cubic segments.
///
/// Supports every command: M L H V C S Q T A Z, absolute and relative,
/// with implicit command repetition. Everything is normalised to cubics:
/// lines → collinear cubics, quadratics → exact cubics, arcs → cubic
/// approximations split into pieces of at most 90°.
///
/// Zero-length segments are dropped (they carry no geometry and would only
/// create structural noise). Because this decision depends solely on the
/// source geometry, it's identical for every weight.
public enum SVGPathParser {

    public enum ParseError: Error, Equatable {
        case unexpectedCharacter(Character, offset: Int)
        case missingArguments(command: Character)
    }

    public static func parse(_ d: String) throws -> PathModel {
        var tok = SVGTokenizer(Array(d.utf8))
        var builder = PathBuilder()
        var command: UInt8 = 0

        while let next = tok.peek() {
            if SVGTokenizer.isCommandLetter(next) {
                command = next
                tok.i += 1
            } else if command == 0 {
                throw ParseError.unexpectedCharacter(Character(UnicodeScalar(next)), offset: tok.i)
            }
            // After M/m, implicit repeats become L/l.
            let current = command
            let rel = current >= UInt8(ascii: "a")
            let upper = rel ? current - 32 : current

            func num() throws -> Double {
                guard let n = tok.nextNumber() else {
                    throw ParseError.missingArguments(command: Character(UnicodeScalar(current)))
                }
                return n
            }
            func pt() throws -> Point {
                let x = try num(), y = try num()
                return rel ? builder.current + Point(x, y) : Point(x, y)
            }

            switch upper {
            case UInt8(ascii: "M"):
                builder.move(to: try pt())
                command = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "L"):
                builder.line(to: try pt())
            case UInt8(ascii: "H"):
                let x = try num()
                builder.line(to: Point(rel ? builder.current.x + x : x, builder.current.y))
            case UInt8(ascii: "V"):
                let y = try num()
                builder.line(to: Point(builder.current.x, rel ? builder.current.y + y : y))
            case UInt8(ascii: "C"):
                let c1 = try pt(), c2 = try pt(), p = try pt()
                builder.cubic(c1, c2, p)
            case UInt8(ascii: "S"):
                let c2 = try pt(), p = try pt()
                builder.smoothCubic(c2, p)
            case UInt8(ascii: "Q"):
                let c = try pt(), p = try pt()
                builder.quad(c, p)
            case UInt8(ascii: "T"):
                builder.smoothQuad(try pt())
            case UInt8(ascii: "A"):
                let rx = try num(), ry = try num(), rot = try num()
                guard let large = tok.nextFlag(), let sweep = tok.nextFlag() else {
                    throw ParseError.missingArguments(command: Character(UnicodeScalar(current)))
                }
                builder.arc(rx: rx, ry: ry, rotation: rot, largeArc: large, sweep: sweep, to: try pt())
            case UInt8(ascii: "Z"):
                builder.close()
                // Z takes no arguments; require a new command letter next.
                command = 0
                if let n = tok.peek(), !SVGTokenizer.isCommandLetter(n) {
                    throw ParseError.unexpectedCharacter(Character(UnicodeScalar(n)), offset: tok.i)
                }
            default:
                throw ParseError.unexpectedCharacter(Character(UnicodeScalar(current)), offset: tok.i)
            }
        }
        return builder.finish()
    }
}

/// Incrementally builds a `PathModel`, tracking SVG pen state.
public struct PathBuilder {
    public private(set) var current = Point.zero
    private var subpathStart = Point.zero
    private var segments: [Segment] = []
    private var subpaths: [Subpath] = []
    private var lastCubicControl: Point?
    private var lastQuadControl: Point?
    private var hasOpenSubpath = false

    public init() {}

    public mutating func move(to p: Point) {
        flush(closed: false)
        current = p
        subpathStart = p
        hasOpenSubpath = true
        lastCubicControl = nil
        lastQuadControl = nil
    }

    public mutating func line(to p: Point) {
        append(.line(current, p))
        current = p
        lastCubicControl = nil
        lastQuadControl = nil
    }

    public mutating func cubic(_ c1: Point, _ c2: Point, _ p: Point) {
        append(Segment(current, c1, c2, p))
        current = p
        lastCubicControl = c2
        lastQuadControl = nil
    }

    public mutating func smoothCubic(_ c2: Point, _ p: Point) {
        let c1 = lastCubicControl.map { current * 2 - $0 } ?? current
        cubic(c1, c2, p)
    }

    public mutating func quad(_ c: Point, _ p: Point) {
        append(.quadratic(current, c, p))
        current = p
        lastQuadControl = c
        lastCubicControl = nil
    }

    public mutating func smoothQuad(_ p: Point) {
        let c = lastQuadControl.map { current * 2 - $0 } ?? current
        quad(c, p)
    }

    public mutating func arc(rx: Double, ry: Double, rotation: Double, largeArc: Bool, sweep: Bool, to p: Point) {
        for s in ArcConverter.cubics(from: current, to: p, rx: rx, ry: ry,
                                      rotationDegrees: rotation, largeArc: largeArc, sweep: sweep) {
            append(s)
        }
        current = p
        lastCubicControl = nil
        lastQuadControl = nil
    }

    public mutating func close() {
        if current.distance(to: subpathStart) > 1e-9 {
            append(.line(current, subpathStart))
        }
        current = subpathStart
        flush(closed: true)
        // A drawing command after Z continues from the subpath start.
        hasOpenSubpath = true
        lastCubicControl = nil
        lastQuadControl = nil
    }

    public mutating func finish() -> PathModel {
        flush(closed: false)
        return PathModel(subpaths: subpaths)
    }

    private mutating func append(_ s: Segment) {
        if !hasOpenSubpath { subpathStart = current; hasOpenSubpath = true }
        if s.isDegenerate { return }
        segments.append(s)
    }

    private mutating func flush(closed: Bool) {
        if !segments.isEmpty {
            subpaths.append(Subpath(segments: segments, isClosed: closed))
        }
        segments = []
        hasOpenSubpath = false
    }
}

/// SVG endpoint-arc → cubic Béziers (SVG 1.1 implementation notes, F.6).
enum ArcConverter {
    static func cubics(from p0: Point, to p1: Point, rx rxIn: Double, ry ryIn: Double,
                       rotationDegrees: Double, largeArc: Bool, sweep: Bool) -> [Segment] {
        if p0.distance(to: p1) < 1e-12 { return [] }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-12 || ry < 1e-12 { return [.line(p0, p1)] }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }

        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den > 0 ? (max(0, num) / den).squareRoot() : 0
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let pieces = max(1, Int(ceil(abs(dTheta) / (.pi / 2) - 1e-9)))
        let step = dTheta / Double(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)

        func ellipsePoint(_ t: Double) -> Point {
            let x = rx * cos(t), y = ry * sin(t)
            return Point(cosPhi * x - sinPhi * y + cx, sinPhi * x + cosPhi * y + cy)
        }
        func ellipseDeriv(_ t: Double) -> Point {
            let x = -rx * sin(t), y = ry * cos(t)
            return Point(cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y)
        }

        var out: [Segment] = []
        var t = theta1
        var start = p0
        for i in 0..<pieces {
            let t2 = t + step
            let end = (i == pieces - 1) ? p1 : ellipsePoint(t2)
            let c1 = start + ellipseDeriv(t) * k
            let c2 = end - ellipseDeriv(t2) * k
            out.append(Segment(start, c1, c2, end))
            start = end
            t = t2
        }
        return out
    }
}
