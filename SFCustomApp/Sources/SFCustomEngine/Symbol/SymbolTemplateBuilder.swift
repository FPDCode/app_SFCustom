import Foundation

/// How the weights of a symbol are produced.
public enum SymbolMode: String, CaseIterable, Codable, Sendable {
    /// Stroke widths follow the ladder → real weight progression.
    case weights
    /// Same geometry in all three anchors: scales with text, but has the
    /// same weight everywhere (the talk's "easiest" option; right for
    /// icons that are filled shapes only).
    case scaleOnly

    public var displayName: String {
        switch self {
        case .weights:   return "Weights"
        case .scaleOnly: return "Scale only"
        }
    }
}

public struct SymbolBuildOptions: Hashable, Sendable {
    public var name: String
    public var ladder: StrokeLadder
    /// Force the Regular stroke to `ladder.regular` template units after
    /// sizing to cap height (otherwise the source stroke is scaled with
    /// the icon and the ladder is used as ratios only).
    public var normalizeRegularStroke: Bool
    public var margins: [AnchorWeight: AnchorMargins]
    public var mode: SymbolMode

    public init(name: String,
                ladder: StrokeLadder = .talk,
                normalizeRegularStroke: Bool = true,
                margins: [AnchorWeight: AnchorMargins] = [:],
                mode: SymbolMode = .weights) {
        self.name = name
        self.ladder = ladder
        self.normalizeRegularStroke = normalizeRegularStroke
        self.margins = margins
        self.mode = mode
    }

    public func margins(for w: AnchorWeight) -> AnchorMargins { margins[w] ?? .standard }
}

/// One anchor slot, in slot-local template coordinates: x = 0 is the left
/// margin guide, y = 0 the baseline, y = −capHeight the cap line.
public struct SymbolAnchor: Hashable, Sendable {
    public var weight: AnchorWeight
    public var path: PathModel
    public var margins: AnchorMargins
    /// Final stroke width in template units (nil when the icon has no strokes).
    public var strokeWidth: Double?

    /// Total slot width between the margin guides.
    public var slotWidth: Double { margins.left + contentBounds.width + margins.right }
    public var contentBounds: Rect { path.tightBounds }
}

public struct SymbolTemplate: Sendable {
    public var name: String
    public var mode: SymbolMode
    /// Ultralight, Regular, Black — in that order.
    public var anchors: [SymbolAnchor]
    public var compatibility: CompatibilityReport
    /// Human-readable notes (unsupported elements, no strokes, auto-fixes).
    public var warnings: [String]
    /// True when the source had at least one stroke.
    public var hasStrokes: Bool

    public func anchor(_ w: AnchorWeight) -> SymbolAnchor {
        anchors.first { $0.weight == w }!
    }

    /// Full Apple "Template v.7.0" SVG.
    public var svg: String { SymbolTemplateWriter.write(self) }

    /// Geometry at any position on the 0…2 axis (0 = Ultralight, 1 =
    /// Regular, 2 = Black), with the left margin interpolated too.
    /// `nil` when the anchors aren't compatible.
    public func interpolated(at position: Double) -> (path: PathModel, margins: AnchorMargins)? {
        let ul = anchor(.ultralight), rg = anchor(.regular), bl = anchor(.black)
        guard let p = SymbolInterpolator.interpolate(ultralight: ul.path, regular: rg.path, black: bl.path, at: position)
        else { return nil }
        let m = AnchorMargins(
            left: SymbolInterpolator.interpolate(ul.margins.left, rg.margins.left, bl.margins.left, at: position),
            right: SymbolInterpolator.interpolate(ul.margins.right, rg.margins.right, bl.margins.right, at: position))
        return (p, m)
    }
}

/// Builds an SF Symbol template from a source SVG.
///
/// Pipeline:
///  1. Flatten the SVG into shapes (fills + strokes).
///  2. Size the icon so the Regular anchor's outline is exactly cap height
///     tall, and (optionally) normalise the Regular stroke to 7 units.
///  3. Outline strokes for each anchor with `CompatibleStroker`
///     (structure identical across weights by construction).
///  4. Give every contour the right winding (plan taken from Regular,
///     applied to all three so structure stays identical).
///  5. Place each anchor in its slot with its margins.
///  6. Verify with `CompatibilityChecker`; auto-fix if needed.
public enum SymbolTemplateBuilder {

    public static let capHeight = 70.459

    public enum BuildError: Error, LocalizedError, Equatable {
        case noDrawableContent

        public var errorDescription: String? {
            switch self {
            case .noDrawableContent:
                return "The SVG has no paths or shapes that can be turned into a symbol."
            }
        }
    }

    public static func build(sourceSVG: String, options: SymbolBuildOptions) throws -> SymbolTemplate {
        let report = SVGShapeReader.read(sourceSVG)
        var warnings: [String] = []
        if !report.unsupportedElements.isEmpty {
            warnings.append("Ignored unsupported elements: \(report.unsupportedElements.joined(separator: ", ")). Convert text and images to paths first.")
        }
        return try build(shapes: report.shapes, options: options, warnings: warnings)
    }

    public static func build(shapes: [SVGShape], options: SymbolBuildOptions, warnings initial: [String] = []) throws -> SymbolTemplate {
        var warnings = initial
        guard !shapes.isEmpty else { throw BuildError.noDrawableContent }

        let strokeWidths = shapes.compactMap { $0.stroke?.width }
        let hasStrokes = !strokeWidths.isEmpty
        let maxStroke = strokeWidths.max() ?? 0
        if options.mode == .weights && !hasStrokes {
            warnings.append("This icon has no strokes, so all three weights are identical. Draw it with strokes to get real weights, or switch to “Scale only”.")
        }

        // --- 2. Sizing + Regular stroke normalisation (fixed-point iteration:
        // the outline's height depends on the stroke, the stroke on the scale).
        var regularScale = 1.0 // multiplier on source stroke widths for Regular
        var geometryScale = 1.0
        for _ in 0..<6 {
            let reg = SymbolOutliner.outline(shapes, strokeScale: regularScale)
            let h = reg.tightBounds.height
            guard h > 1e-9 else { throw BuildError.noDrawableContent }
            geometryScale = capHeight / h
            guard options.normalizeRegularStroke, hasStrokes, maxStroke > 0 else { break }
            let next = options.ladder.regular / (maxStroke * geometryScale)
            if abs(next - regularScale) < 1e-6 { regularScale = next; break }
            regularScale = next
        }

        // --- 3. Outline each anchor (in source units).
        func strokeScale(for w: AnchorWeight) -> Double {
            options.mode == .scaleOnly ? regularScale : regularScale * options.ladder.ratio(for: w)
        }
        var results: [AnchorWeight: SymbolOutliner.Result] = [:]
        for w in AnchorWeight.allCases {
            results[w] = SymbolOutliner.outlineWithRoles(shapes, strokeScale: strokeScale(for: w))
        }

        // --- 4. Winding plan from Regular, applied to all.
        let plan = SymbolOutliner.windingPlan(for: results[.regular]!)

        // --- 5. Placement. Vertical transform shared (from Regular) so
        // heavier weights grow evenly around the same centreline; each
        // anchor's own left edge sits on its left margin.
        let regBounds = results[.regular]!.path.tightBounds
        let ty = -regBounds.maxY * geometryScale
        var anchors: [SymbolAnchor] = []
        for w in AnchorWeight.allCases {
            let oriented = SymbolOutliner.apply(plan: plan, to: results[w]!.path)
            let b = oriented.tightBounds
            let m = options.margins(for: w)
            let t = AffineTransform2D(a: geometryScale, b: 0, c: 0, d: geometryScale,
                                      e: -b.minX * geometryScale + m.left, f: ty)
            anchors.append(SymbolAnchor(
                weight: w,
                path: oriented.transformed(by: t),
                margins: m,
                strokeWidth: hasStrokes ? maxStroke * strokeScale(for: w) * geometryScale : nil))
        }

        // --- 6. Verify / auto-fix.
        var check = CompatibilityChecker.check(anchors: anchors.map { ($0.weight, $0.path) })
        if check.status == .fixable {
            let fixed = CompatibilityFixer.fix(anchors: anchors.map { ($0.weight, $0.path) })
            for i in anchors.indices { if let p = fixed[anchors[i].weight] { anchors[i].path = p } }
            warnings.append("Auto-fixed: " + check.issues.map(\.message).joined(separator: "; "))
            check = CompatibilityChecker.check(anchors: anchors.map { ($0.weight, $0.path) })
        }

        return SymbolTemplate(name: options.name, mode: options.mode, anchors: anchors,
                              compatibility: check, warnings: warnings, hasStrokes: hasStrokes)
    }
}

// MARK: - Template SVG writer

/// Writes Apple's SF Symbol "Template v.7.0" layout.
///
/// Matches Apple's exports (see `SF Samples/…/calendar.svg`): 3300×2200
/// canvas, Notes / Guides / Symbols groups, three anchor groups
/// (Ultralight-S, Regular-S, Black-S) each translated to (slotLeft,
/// baseline-S) with filled paths in slot-local coordinates.
public enum SymbolTemplateWriter {

    static let canvasWidth = 3300.0
    static let canvasHeight = 2200.0
    static let baselines: [(suffix: String, label: String, y: Double)] = [
        ("S", "Small", 696), ("M", "Medium", 1126), ("L", "Large", 1556),
    ]
    static let columns: [(label: String, x: Double)] = [
        ("Ultralight", 559.711), ("Thin", 856.422), ("Light", 1153.13), ("Regular", 1449.84),
        ("Medium", 1746.56), ("Semibold", 2043.27), ("Bold", 2339.98), ("Heavy", 2636.69), ("Black", 2933.40),
    ]

    static func columnX(_ w: AnchorWeight) -> Double {
        switch w {
        case .ultralight: return 559.711
        case .regular:    return 1449.84
        case .black:      return 2933.40
        }
    }

    public static func slotLeft(_ a: SymbolAnchor) -> Double {
        columnX(a.weight) - a.slotWidth / 2
    }

    public static func write(_ t: SymbolTemplate) -> String {
        let cap = SymbolTemplateBuilder.capHeight
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 3300 2200">
        <!--Generator: SF Custom-->
        <style>
        .SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}
        </style>

        """
        // Notes
        let labelStyle = "stroke:none;fill:black;font-family:sans-serif;font-size:13;"
        out += "<g id=\"Notes\">\n"
        out += "  <rect height=\"2200\" id=\"artboard\" style=\"fill:white;opacity:1\" width=\"3300\" x=\"0\" y=\"0\"/>\n"
        out += "  <line style=\"fill:none;stroke:black;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"292\" y2=\"292\"/>\n"
        out += "  <text style=\"\(labelStyle)font-weight:bold;\" transform=\"matrix(1 0 0 1 263 322)\">Weight/Scale Variations</text>\n"
        for c in columns {
            out += "  <text style=\"\(labelStyle)text-anchor:middle;\" transform=\"matrix(1 0 0 1 \(n(c.x)) 322)\">\(c.label)</text>\n"
        }
        for b in baselines {
            out += "  <text style=\"\(labelStyle)\" transform=\"matrix(1 0 0 1 263 \(n(b.y + 30)))\">\(b.label)</text>\n"
        }
        out += "  <text id=\"template-version\" style=\"\(labelStyle)text-anchor:end;\" transform=\"matrix(1 0 0 1 3036 1933)\">Template v.7.0</text>\n"
        out += "  <text style=\"\(labelStyle)text-anchor:end;\" transform=\"matrix(1 0 0 1 3036 1951)\">Generated by SF Custom</text>\n"
        out += "  <text id=\"descriptive-name\" style=\"\(labelStyle)text-anchor:end;\" transform=\"matrix(1 0 0 1 3036 1969)\">\(xmlEscape(t.name))</text>\n"
        out += "  <text style=\"\(labelStyle)text-anchor:end;\" transform=\"matrix(1 0 0 1 3036 1987)\">Typeset at 100.0 points</text>\n"
        out += "</g>\n"

        // Guides
        let hRef = #"<path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.2315-26.7285L12.4385-26.7285ZM55.1196 0L57.7637 0L30.6382-70.459L29.4326-70.459L29.4326-67.1323Z"/>"#
        out += "<g id=\"Guides\">\n"
        for b in baselines {
            out += "  <g id=\"H-reference\" style=\"fill:#27AAE1;stroke:none;\" transform=\"matrix(1 0 0 1 339 \(n(b.y)))\">\(hRef)</g>\n"
            out += "  <line id=\"Baseline-\(b.suffix)\" style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"\(n(b.y))\" y2=\"\(n(b.y))\"/>\n"
            out += "  <line id=\"Capline-\(b.suffix)\" style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"\(n(b.y - cap))\" y2=\"\(n(b.y - cap))\"/>\n"
        }
        for a in t.anchors {
            let l = slotLeft(a), r = l + a.slotWidth
            out += "  <line id=\"left-margin-\(a.weight.templateID)-S\" style=\"fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;\" x1=\"\(n(l))\" x2=\"\(n(l))\" y1=\"600.785\" y2=\"720.121\"/>\n"
            out += "  <line id=\"right-margin-\(a.weight.templateID)-S\" style=\"fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;\" x1=\"\(n(r))\" x2=\"\(n(r))\" y1=\"600.785\" y2=\"720.121\"/>\n"
        }
        out += "</g>\n"

        // Symbols
        out += "<g id=\"Symbols\">\n"
        for a in t.anchors {
            out += "  <g id=\"\(a.weight.templateID)-S\" transform=\"matrix(1 0 0 1 \(n(slotLeft(a))) 696)\">\n"
            out += "   <path d=\"\(SVGPathWriter.write(a.path, precision: 4))\"/>\n"
            out += "  </g>\n"
        }
        out += "</g>\n</svg>\n"
        return out
    }

    static func n(_ v: Double) -> String { SVGPathWriter.num(v, 4) }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
