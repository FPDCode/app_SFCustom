import Foundation

/// Generates Apple-compliant SF Symbol template SVGs (v7.0 dynamic format,
/// Small row only — Ultralight/Regular/Black masters).
///
/// We build the template ourselves rather than going through SwiftDraw's
/// `SFSymbolRenderer`: that renderer renormalizes every input SVG into a
/// uniform cell box, which discards per-weight geometric differences. By
/// building the template directly we control each cell's transform and can
/// apply Apple's weight growth curve as a `matrix(...)` on the cell — so
/// Ultralight, Regular, and Black render at visibly different sizes per
/// Apple's measured 0% / 1.6% / 28.4% growth factors.
struct TemplateGenerator {

    enum Error: Swift.Error {
        case noSource
    }

    // ─── Canvas constants (Apple template v7.0) ────────────────────

    private let canvasW: Double = 3300
    private let canvasH: Double = 2200
    private let baselineY: Double = 696
    private let capHeight: Double = 70.459
    private var caplineY: Double { baselineY - capHeight }

    // ─── Public API ────────────────────────────────────────────────

    func generate(for icon: Icon) throws -> String {
        // 1. Resolve a single set of source paths from the captured SVG.
        guard let svg = icon.sourceSVG, !svg.isEmpty else { throw Error.noSource }
        let paths = extractPaths(from: svg)
        guard !paths.isEmpty else { throw Error.noSource }

        let viewBox = extractViewBox(from: svg) ?? (0, 0, 256, 256)
        let bbox = boundingBoxOfPaths(paths, fallback: viewBox)

        // 2. Compute per-weight scale factors from Apple's growth curve.
        let scales = weightScales(for: icon.weightMode)

        // 3. Build each cell. The icon is fit to the cell width (sized for
        //    the source weight), then scaled per Apple's growth curve. So
        //    Black ends up filling more horizontal space than Ultralight —
        //    matching SF Symbols' real visual progression.
        var cells = ""
        var marginGuides = ""

        // The "base cell width" we fit Regular into. We pick a reasonable
        // visible width relative to cap height (icon ≈ aspect ratio fit).
        let aspect = bbox.width / max(bbox.height, 1)
        let baseCellWidth = capHeight * aspect          // ≈ 70 × aspect

        for (weight, scale, anchorX) in [
            (WeightLabel.ultralight, scales.ultralight, 559.711),
            (WeightLabel.regular,    scales.regular,    1449.84),
            (WeightLabel.black,      scales.black,      2933.4),
        ] {
            let cellWidth = baseCellWidth * scale
            let leftMargin = anchorX - cellWidth / 2.0
            let rightMargin = anchorX + cellWidth / 2.0

            cells += renderCell(
                weight: weight.cellSuffix,
                anchorX: anchorX,
                paths: paths,
                bbox: bbox,
                scale: scale * (capHeight / max(bbox.height, 1))
            )

            marginGuides += marginLine(
                id: "left-margin-\(weight.cellSuffix)-S", x: leftMargin
            )
            marginGuides += marginLine(
                id: "right-margin-\(weight.cellSuffix)-S", x: rightMargin
            )
        }

        return buildSVG(iconName: icon.name, symbolCells: cells, marginGuides: marginGuides)
    }

    // ─── Per-weight scales ────────────────────────────────────────

    private struct WeightScales { var ultralight: Double; var regular: Double; var black: Double }

    /// Compute per-weight scale factors. For `.singleGenerate`, rebase
    /// Apple's growth curve so the user's chosen source weight = 1.0.
    private func weightScales(for mode: WeightMode) -> WeightScales {
        switch mode {
        case .uniform:
            return WeightScales(ultralight: 1.0, regular: 1.0, black: 1.0)

        case .singleGenerate(let source):
            let g = TemplateConfig.weightGrowthFactors
            let ul = g[.ultralight] ?? 1.0
            let rg = g[.regular] ?? 1.016
            let bk = g[.black] ?? 1.284
            let base: Double
            switch source {
            case .ultralight: base = ul
            case .regular:    base = rg
            case .black:      base = bk
            }
            return WeightScales(ultralight: ul / base, regular: rg / base, black: bk / base)

        case .fullControl:
            // Currently the capture pipeline only stores one source SVG; the
            // three masters are identical. Future: per-master sourceSVGs.
            return WeightScales(ultralight: 1.0, regular: 1.0, black: 1.0)
        }
    }

    // ─── Cell renderer ────────────────────────────────────────────

    /// Render one symbol cell. The icon's paths are placed in cell-local
    /// coordinates (origin at the cell's anchor on the baseline), with
    /// Y inverted so the icon sits ABOVE the baseline (negative-Y).
    private func renderCell(
        weight: String,
        anchorX: Double,
        paths: [ExtractedPath],
        bbox: BBox,
        scale: Double
    ) -> String {
        // The cell's group lives at (anchorX, baselineY) in canvas coords.
        // Inside the cell, path Y < 0 is ABOVE the baseline (SVG y-down).
        //
        // Map source coords (y-down, top=minY, bottom=maxY) into cell coords:
        //   cellY = (sourceY - maxY) * scale
        //   → sourceY=maxY (bottom) → 0 (on baseline)
        //   → sourceY=minY (top)    → -scale*height (above baseline)
        // That's:  scaleY=+scale, translateY=-maxY*scale
        //
        // Source SVG is already y-down, so no flip needed.
        let scaledW = bbox.width * scale
        let cellTx = anchorX - scaledW / 2.0
        let cellTy = baselineY
        let pathTx = -bbox.minX * scale
        let pathTy = -bbox.maxY * scale

        var inner = ""
        for p in paths {
            let transformed = scalePath(p.d, sx: scale, sy: scale, tx: pathTx, ty: pathTy)
            let rule = p.fillRule == "evenodd" ? " fill-rule=\"evenodd\"" : ""
            inner += "<path\(rule) d=\"\(transformed)\"/>"
        }

        return """
          <g id="\(weight)-S" transform="matrix(1 0 0 1 \(fmt(cellTx)) \(fmt(cellTy)))">
        \(inner)
          </g>

        """
    }

    // ─── SVG path extraction ──────────────────────────────────────

    private struct ExtractedPath { let d: String; let fillRule: String }
    private struct BBox { var minX, minY, maxX, maxY: Double; var width: Double { maxX - minX }; var height: Double { maxY - minY } }

    private func extractPaths(from svg: String) -> [ExtractedPath] {
        // Match <path … d="…" … /> capturing the d attribute. Also grab an
        // optional fill-rule attribute.
        let pattern = #"<path\b([^>]*)/?\s*>"#
        guard let r = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let range = NSRange(svg.startIndex..., in: svg)
        var out: [ExtractedPath] = []
        for m in r.matches(in: svg, range: range) {
            guard let attrR = Range(m.range(at: 1), in: svg) else { continue }
            let attrs = String(svg[attrR])
            guard let d = attribute("d", in: attrs), !d.isEmpty else { continue }
            let rule = attribute("fill-rule", in: attrs) ?? "nonzero"
            out.append(ExtractedPath(d: d, fillRule: rule))
        }
        return out
    }

    private func attribute(_ name: String, in attrs: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*\"([^\"]*)\""
        guard let r = try? NSRegularExpression(pattern: pattern),
              let m = r.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(m.range(at: 1), in: attrs)
        else { return nil }
        return String(attrs[range])
    }

    private func extractViewBox(from svg: String) -> (Double, Double, Double, Double)? {
        let pattern = #"viewBox\s*=\s*"([^"]+)""#
        guard let r = try? NSRegularExpression(pattern: pattern),
              let m = r.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
              let range = Range(m.range(at: 1), in: svg) else { return nil }
        let parts = svg[range].split(whereSeparator: { ", \t\n".contains($0) }).compactMap { Double($0) }
        guard parts.count >= 4 else { return nil }
        return (parts[0], parts[1], parts[2], parts[3])
    }

    private func boundingBoxOfPaths(_ paths: [ExtractedPath], fallback: (Double, Double, Double, Double)) -> BBox {
        var box = BBox(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)
        for p in paths {
            let bb = SVGParser.boundingBox(of: SVGParser.parsePathData(p.d))
            if bb.width > 0, bb.height > 0 {
                box.minX = min(box.minX, bb.minX)
                box.minY = min(box.minY, bb.minY)
                box.maxX = max(box.maxX, bb.maxX)
                box.maxY = max(box.maxY, bb.maxY)
            }
        }
        if box.minX.isInfinite {
            return BBox(minX: fallback.0, minY: fallback.1, maxX: fallback.0 + fallback.2, maxY: fallback.1 + fallback.3)
        }
        return box
    }

    // ─── Path scaling ─────────────────────────────────────────────

    private func scalePath(_ d: String, sx: Double, sy: Double, tx: Double, ty: Double) -> String {
        let commands = SVGParser.parsePathData(d)
        let transformed = transformCommands(commands, scaleX: sx, scaleY: sy, translateX: tx, translateY: ty)
        return SVGParser.serializePathData(transformed)
    }

    private func transformCommands(
        _ commands: [SVGParser.PathCommand],
        scaleX: Double, scaleY: Double, translateX: Double, translateY: Double
    ) -> [SVGParser.PathCommand] {
        commands.map { cmd in
            var t = cmd
            let tx = cmd.isRelative ? 0.0 : translateX
            let ty = cmd.isRelative ? 0.0 : translateY
            switch cmd.type {
            case "M", "L", "T":
                var i = 0
                while i + 1 < t.parameters.count {
                    t.parameters[i]   = cmd.parameters[i]   * scaleX + tx
                    t.parameters[i+1] = cmd.parameters[i+1] * scaleY + ty
                    i += 2
                }
            case "H":
                t.parameters = cmd.parameters.map { $0 * scaleX + tx }
            case "V":
                t.parameters = cmd.parameters.map { $0 * scaleY + ty }
            case "C":
                var i = 0
                while i + 5 < t.parameters.count {
                    for j in stride(from: 0, to: 6, by: 2) {
                        t.parameters[i+j]   = cmd.parameters[i+j]   * scaleX + tx
                        t.parameters[i+j+1] = cmd.parameters[i+j+1] * scaleY + ty
                    }
                    i += 6
                }
            case "S", "Q":
                var i = 0
                while i + 3 < t.parameters.count {
                    for j in stride(from: 0, to: 4, by: 2) {
                        t.parameters[i+j]   = cmd.parameters[i+j]   * scaleX + tx
                        t.parameters[i+j+1] = cmd.parameters[i+j+1] * scaleY + ty
                    }
                    i += 4
                }
            case "A":
                if t.parameters.count >= 7 {
                    t.parameters[0] = abs(cmd.parameters[0] * scaleX)
                    t.parameters[1] = abs(cmd.parameters[1] * scaleY)
                    if scaleY < 0 { t.parameters[4] = cmd.parameters[4] == 0 ? 1 : 0 }
                    t.parameters[5] = cmd.parameters[5] * scaleX + tx
                    t.parameters[6] = cmd.parameters[6] * scaleY + ty
                }
            default: break
            }
            return t
        }
    }

    // ─── Apple template SVG assembly ──────────────────────────────

    private func buildSVG(iconName: String, symbolCells: String, marginGuides: String) -> String {
        let notes = notesGroup(iconName: iconName)
        let guides = guidesGroup(marginGuides: marginGuides)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!--Generator: SF Custom Template v7.0-->
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 \(fmt(canvasW)) \(fmt(canvasH))">
         <!--glyph: "\(iconName)", point size: 100.0, template writer version: "138.0.0"-->
        \(notes)
        \(guides)
         <g id="Symbols">
        \(symbolCells) </g>
        </svg>
        """
    }

    private func notesGroup(iconName: String) -> String {
        var s = """
         <g id="Notes">
          <rect height="\(fmt(canvasH))" id="artboard" style="fill:white;opacity:1" width="\(fmt(canvasW))" x="0" y="0"/>
          <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="292" y2="292"/>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
        """
        let labels: [(String, Double)] = [
            ("Ultralight", 559.711), ("Thin", 856.422), ("Light", 1153.13),
            ("Regular", 1449.84), ("Medium", 1746.56), ("Semibold", 2043.27),
            ("Bold", 2339.98), ("Heavy", 2636.69), ("Black", 2933.4)
        ]
        for (label, x) in labels {
            s += "\n  <text style=\"stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;\" transform=\"matrix(1 0 0 1 \(fmt(x)) 322)\">\(label)</text>"
        }
        s += """

          <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1903" y2="1903"/>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 726)">Small</text>
          <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.7.0</text>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1951)">Requires Xcode 26 or greater</text>
          <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Generated from \(iconName)</text>
         </g>
        """
        return s
    }

    private func guidesGroup(marginGuides: String) -> String {
        var s = " <g id=\"Guides\">\n"
        s += "  <line id=\"Baseline-S\" style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"\(fmt(baselineY))\" y2=\"\(fmt(baselineY))\"/>\n"
        s += "  <line id=\"Capline-S\" style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"\(fmt(caplineY))\" y2=\"\(fmt(caplineY))\"/>\n"
        s += marginGuides
        s += " </g>"
        return s
    }

    private func marginLine(id: String, x: Double) -> String {
        "  <line id=\"\(id)\" style=\"fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;\" x1=\"\(fmt(x))\" x2=\"\(fmt(x))\" y1=\"600.785\" y2=\"720.121\"/>\n"
    }

    // ─── Formatting ───────────────────────────────────────────────

    private func fmt(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1_000_000 { return String(Int(n)) }
        var s = String(format: "%.3f", n)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

// MARK: - WeightLabel cell name helper

private extension WeightLabel {
    var cellSuffix: String {
        switch self {
        case .ultralight: return "Ultralight"
        case .thin:       return "Thin"
        case .light:      return "Light"
        case .regular:    return "Regular"
        case .medium:     return "Medium"
        case .semibold:   return "Semibold"
        case .bold:       return "Bold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        }
    }
}
