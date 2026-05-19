import Foundation

/// Parses SVG path data from raw SVG strings and provides path manipulation utilities
struct SVGParser {

    // MARK: - Path Extraction

    /// Extract SVG path `d` attribute values from an SVG string
    /// Returns an array of path data strings (one per <path> element)
    static func extractPaths(from svg: String) throws -> [String] {
        // Match all d="..." attributes in <path> elements
        let pattern = #"<path[^>]*\sd="([^"]+)"[^>]*/?\s*>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(svg.startIndex..., in: svg)
        let matches = regex.matches(in: svg, range: range)

        guard !matches.isEmpty else {
            throw SFCustomError.invalidSVG("No <path> elements found in SVG")
        }

        return matches.compactMap { match in
            guard let dRange = Range(match.range(at: 1), in: svg) else { return nil }
            return String(svg[dRange])
        }
    }

    /// Merge multiple SVG paths into a single compound path
    static func mergePaths(_ paths: [String]) -> String {
        paths.joined(separator: " ")
    }

    /// Extract the viewBox dimensions from an SVG string
    static func extractViewBox(from svg: String) -> (x: Double, y: Double, width: Double, height: Double)? {
        let pattern = #"viewBox="([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)) else {
            return nil
        }

        func doubleAt(_ index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: svg) else { return nil }
            return Double(svg[range])
        }

        guard let x = doubleAt(1), let y = doubleAt(2), let w = doubleAt(3), let h = doubleAt(4) else {
            return nil
        }
        return (x, y, w, h)
    }

    // MARK: - Path Data Parsing

    /// A parsed SVG path command (M, L, C, Q, Z, etc.)
    struct PathCommand {
        let type: Character        // Command letter (M, L, C, Q, A, Z, etc.)
        let isRelative: Bool       // Lowercase = relative
        var parameters: [Double]   // Numeric parameters
    }

    /// Parse an SVG path `d` string into structured commands
    static func parsePathData(_ d: String) -> [PathCommand] {
        var commands: [PathCommand] = []
        // Match command letter followed by optional numbers
        let pattern = #"([MmLlHhVvCcSsQqTtAaZz])\s*((?:[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?[\s,]*)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(d.startIndex..., in: d)
        let matches = regex.matches(in: d, range: range)

        for match in matches {
            guard let cmdRange = Range(match.range(at: 1), in: d) else { continue }
            let cmdChar = d[cmdRange].first!

            var params: [Double] = []
            if let paramRange = Range(match.range(at: 2), in: d) {
                let paramStr = String(d[paramRange])
                let numPattern = #"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?"#
                if let numRegex = try? NSRegularExpression(pattern: numPattern) {
                    let numMatches = numRegex.matches(in: paramStr, range: NSRange(paramStr.startIndex..., in: paramStr))
                    params = numMatches.compactMap { m in
                        guard let r = Range(m.range, in: paramStr) else { return nil }
                        return Double(paramStr[r])
                    }
                }
            }

            commands.append(PathCommand(
                type: cmdChar.uppercased().first!,
                isRelative: cmdChar.isLowercase,
                parameters: params
            ))
        }

        return commands
    }

    /// Convert parsed commands back to an SVG path `d` string
    static func serializePathData(_ commands: [PathCommand]) -> String {
        commands.map { cmd in
            let letter = cmd.isRelative ? String(cmd.type).lowercased() : String(cmd.type)
            if cmd.parameters.isEmpty {
                return letter
            }
            let params = cmd.parameters.map { formatNumber($0) }.joined(separator: " ")
            return "\(letter)\(params)"
        }.joined(separator: " ")
    }

    /// Format a number with reasonable precision, avoiding trailing zeros
    private static func formatNumber(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1_000_000 {
            return String(Int(n))
        }
        let s = String(format: "%.3f", n)
        // Trim trailing zeros after decimal
        var trimmed = s
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    // MARK: - Bounding Box

    struct BoundingBox {
        var minX: Double = .infinity
        var minY: Double = .infinity
        var maxX: Double = -.infinity
        var maxY: Double = -.infinity

        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
        var centerX: Double { (minX + maxX) / 2.0 }
        var centerY: Double { (minY + maxY) / 2.0 }

        mutating func include(_ x: Double, _ y: Double) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    /// Compute approximate bounding box from path commands
    /// Note: This is approximate — curves may extend beyond control points
    static func boundingBox(of commands: [PathCommand]) -> BoundingBox {
        var box = BoundingBox()
        var curX = 0.0, curY = 0.0

        for cmd in commands {
            let p = cmd.parameters
            switch cmd.type {
            case "M", "L", "T":
                // Pairs of (x, y)
                var i = 0
                while i + 1 < p.count {
                    let x = cmd.isRelative ? curX + p[i] : p[i]
                    let y = cmd.isRelative ? curY + p[i+1] : p[i+1]
                    box.include(x, y)
                    curX = x; curY = y
                    i += 2
                }
            case "H":
                for val in p {
                    let x = cmd.isRelative ? curX + val : val
                    box.include(x, curY)
                    curX = x
                }
            case "V":
                for val in p {
                    let y = cmd.isRelative ? curY + val : val
                    box.include(curX, y)
                    curY = y
                }
            case "C":
                // Cubic bezier: (x1,y1, x2,y2, x,y)
                var i = 0
                while i + 5 < p.count {
                    for j in stride(from: 0, to: 6, by: 2) {
                        let x = cmd.isRelative ? curX + p[i+j] : p[i+j]
                        let y = cmd.isRelative ? curY + p[i+j+1] : p[i+j+1]
                        box.include(x, y)
                    }
                    curX = cmd.isRelative ? curX + p[i+4] : p[i+4]
                    curY = cmd.isRelative ? curY + p[i+5] : p[i+5]
                    i += 6
                }
            case "Q":
                // Quadratic bezier: (x1,y1, x,y)
                var i = 0
                while i + 3 < p.count {
                    for j in stride(from: 0, to: 4, by: 2) {
                        let x = cmd.isRelative ? curX + p[i+j] : p[i+j]
                        let y = cmd.isRelative ? curY + p[i+j+1] : p[i+j+1]
                        box.include(x, y)
                    }
                    curX = cmd.isRelative ? curX + p[i+2] : p[i+2]
                    curY = cmd.isRelative ? curY + p[i+3] : p[i+3]
                    i += 4
                }
            case "S":
                // Smooth cubic bezier: (x2,y2, x,y) — reflected first control point implied
                var i = 0
                while i + 3 < p.count {
                    for j in stride(from: 0, to: 4, by: 2) {
                        let x = cmd.isRelative ? curX + p[i+j] : p[i+j]
                        let y = cmd.isRelative ? curY + p[i+j+1] : p[i+j+1]
                        box.include(x, y)
                    }
                    curX = cmd.isRelative ? curX + p[i+2] : p[i+2]
                    curY = cmd.isRelative ? curY + p[i+3] : p[i+3]
                    i += 4
                }
            case "A":
                // Elliptical arc: (rx, ry, x-axis-rotation, large-arc, sweep, x, y)
                var i = 0
                while i + 6 < p.count {
                    let x = cmd.isRelative ? curX + p[i+5] : p[i+5]
                    let y = cmd.isRelative ? curY + p[i+6] : p[i+6]
                    box.include(x, y)
                    curX = x; curY = y
                    i += 7
                }
            case "Z":
                break // Close path
            default:
                break
            }
        }

        return box
    }
}
