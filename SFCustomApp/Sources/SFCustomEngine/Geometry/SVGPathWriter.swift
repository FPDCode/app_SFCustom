import Foundation

/// Serialises a `PathModel` back to SVG path data.
///
/// Output is always absolute `M`, `C`, `Z` so that the command sequence is
/// exactly what `PathModel.signature()` describes — no shortening to `L`,
/// `H`, `S` etc., which would make two compatible paths *look* different to
/// SF Symbols' interpolation.
public enum SVGPathWriter {

    public static func write(_ path: PathModel, precision: Int = 3) -> String {
        var out = ""
        out.reserveCapacity(path.subpaths.reduce(0) { $0 + $1.segments.count * 48 })
        for sp in path.subpaths {
            guard let first = sp.segments.first else { continue }
            out += "M" + fmt(first.p0, precision)
            for s in sp.segments {
                out += "C" + fmt(s.p1, precision) + " " + fmt(s.p2, precision) + " " + fmt(s.p3, precision)
            }
            if sp.isClosed { out += "Z" }
        }
        return out
    }

    static func fmt(_ p: Point, _ precision: Int) -> String {
        num(p.x, precision) + " " + num(p.y, precision)
    }

    static func num(_ v: Double, _ precision: Int) -> String {
        var s = String(format: "%.\(precision)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s
    }
}
