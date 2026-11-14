import Foundation

/// SVG-style 2D affine matrix `[a c e; b d f; 0 0 1]`.
/// Named to avoid clashing with Foundation's `AffineTransform`.
public struct AffineTransform2D: Hashable, Sendable {
    public var a, b, c, d, e, f: Double

    public init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f
    }

    public static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

    public static func translate(_ tx: Double, _ ty: Double) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: 0, c: 0, d: 1, e: tx, f: ty)
    }

    public static func scale(_ sx: Double, _ sy: Double) -> AffineTransform2D {
        AffineTransform2D(a: sx, b: 0, c: 0, d: sy, e: 0, f: 0)
    }

    public static func rotate(degrees: Double) -> AffineTransform2D {
        let r = degrees * .pi / 180
        return AffineTransform2D(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), e: 0, f: 0)
    }

    public static func skewX(degrees: Double) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: 0, c: tan(degrees * .pi / 180), d: 1, e: 0, f: 0)
    }

    public static func skewY(degrees: Double) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: tan(degrees * .pi / 180), c: 0, d: 1, e: 0, f: 0)
    }

    /// `self` applied after `other` — i.e. the SVG composition order
    /// `parent.concatenating(child)` maps child space → parent space.
    public func concatenating(_ m: AffineTransform2D) -> AffineTransform2D {
        AffineTransform2D(
            a: a * m.a + c * m.b,
            b: b * m.a + d * m.b,
            c: a * m.c + c * m.d,
            d: b * m.c + d * m.d,
            e: a * m.e + c * m.f + e,
            f: b * m.e + d * m.f + f
        )
    }

    public func apply(_ p: Point) -> Point {
        Point(a * p.x + c * p.y + e, b * p.x + d * p.y + f)
    }

    /// Geometric-mean scale; used to scale stroke widths through transforms.
    public var meanScale: Double { abs(a * d - b * c).squareRoot() }

    /// Parse an SVG `transform` attribute (list of matrix/translate/scale/
    /// rotate/skewX/skewY). Unknown functions are ignored.
    public static func parse(_ s: String) -> AffineTransform2D {
        var result = AffineTransform2D.identity
        let scanner = s as NSString
        let pattern = #"(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return result }
        for m in re.matches(in: s, range: NSRange(location: 0, length: scanner.length)) {
            let name = scanner.substring(with: m.range(at: 1))
            let args = SVGNumberScanner.numbers(in: scanner.substring(with: m.range(at: 2)))
            let t: AffineTransform2D
            switch name {
            case "matrix" where args.count >= 6:
                t = AffineTransform2D(a: args[0], b: args[1], c: args[2], d: args[3], e: args[4], f: args[5])
            case "translate" where !args.isEmpty:
                t = .translate(args[0], args.count > 1 ? args[1] : 0)
            case "scale" where !args.isEmpty:
                t = .scale(args[0], args.count > 1 ? args[1] : args[0])
            case "rotate" where !args.isEmpty:
                if args.count >= 3 {
                    t = AffineTransform2D.translate(args[1], args[2])
                        .concatenating(.rotate(degrees: args[0]))
                        .concatenating(.translate(-args[1], -args[2]))
                } else {
                    t = .rotate(degrees: args[0])
                }
            case "skewX" where !args.isEmpty: t = .skewX(degrees: args[0])
            case "skewY" where !args.isEmpty: t = .skewY(degrees: args[0])
            default: continue
            }
            result = result.concatenating(t)
        }
        return result
    }
}

/// Extracts SVG numbers (handles `1.5.5`, `-1-2`, exponents, commas).
enum SVGNumberScanner {
    static func numbers(in s: String) -> [Double] {
        var out: [Double] = []
        var tokenizer = SVGTokenizer(Array(s.utf8))
        while let n = tokenizer.nextNumber() { out.append(n) }
        return out
    }
}

/// Byte-level tokenizer shared by the path-data and number parsers.
struct SVGTokenizer {
    let bytes: [UInt8]
    var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { i >= bytes.count }

    mutating func skipSeparators() {
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C { i += 1 } else { break }
        }
    }

    /// Peek the next non-separator byte.
    mutating func peek() -> UInt8? {
        skipSeparators()
        return i < bytes.count ? bytes[i] : nil
    }

    static func isCommandLetter(_ c: UInt8) -> Bool {
        switch c {
        case UInt8(ascii: "e"), UInt8(ascii: "E"): return false
        default: return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
        }
    }

    /// Single-character flag for arc commands (`0`/`1`, may be unseparated).
    mutating func nextFlag() -> Bool? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        let c = bytes[i]
        if c == UInt8(ascii: "0") { i += 1; return false }
        if c == UInt8(ascii: "1") { i += 1; return true }
        return nil
    }

    mutating func nextNumber() -> Double? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        let start = i
        if bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
        var sawDigit = false, sawDot = false
        while i < bytes.count {
            let c = bytes[i]
            if c >= 0x30 && c <= 0x39 { sawDigit = true; i += 1 }
            else if c == UInt8(ascii: ".") && !sawDot { sawDot = true; i += 1 }
            else { break }
        }
        if sawDigit, i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            var j = i + 1
            if j < bytes.count, bytes[j] == UInt8(ascii: "+") || bytes[j] == UInt8(ascii: "-") { j += 1 }
            if j < bytes.count, bytes[j] >= 0x30 && bytes[j] <= 0x39 {
                i = j
                while i < bytes.count, bytes[i] >= 0x30 && bytes[i] <= 0x39 { i += 1 }
            }
        }
        guard sawDigit else { i = start; return nil }
        return Double(String(decoding: bytes[start..<i], as: UTF8.self))
    }
}
