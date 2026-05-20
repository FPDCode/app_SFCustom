import Foundation

/// Generates an Apple SF Symbol Template v.7.0 SVG from a single source icon.
///
/// Matches the structure of Apple's official exports (compare with
/// `SF Samples/SF Symbol_Template/more SF Symbol Samples/calendar.svg`):
///   • viewBox 0 0 3300 2200
///   • <Notes> group with weight labels + template-version + descriptive-name
///   • <Guides> group with H-reference, baseline/cap lines, per-weight margins
///   • <Symbols> group with exactly 3 anchor weights (Ultralight-S, Regular-S,
///     Black-S). Xcode interpolates the other weights and the M/L scales.
///
/// Sizing rules (also derived from Apple's exports):
///   • Each icon is scaled so its tight content bbox height equals the
///     cap height (≈ 70.459 units).
///   • A 9.76562-unit side bearing sits between the icon's left/right
///     edge and the slot's left/right margin line.
///   • The slot is positioned so its centre lines up with the column X
///     of that weight (559.711 for Ultralight, 1449.84 for Regular,
///     2933.4 for Black).
///   • Icon path coordinates are in icon-local space — y=0 at baseline,
///     y negative above baseline, no Y-flip applied.
@MainActor
final class TemplateGenerator {

    enum GenerationError: Error, LocalizedError {
        case sourceMalformed
        case missingBBox

        var errorDescription: String? {
            switch self {
            case .sourceMalformed: return "Source SVG didn't expose a usable root element."
            case .missingBBox:     return "Couldn't measure the icon's content."
            }
        }
    }

    // Apple template canvas constants.
    private static let canvasWidth: Double = 3300
    private static let canvasHeight: Double = 2200

    // Cap height — the height of a Regular-weight uppercase letter, and the
    // height we size each icon to.
    private static let capHeight: Double = 70.459

    // Symmetric side bearing between icon's tight bbox and the margin lines.
    // Measured directly from Apple's calendar.svg / pencil.svg exports.
    private static let sideBearing: Double = 9.76562

    // Baseline / cap-line Y positions in the canvas, per scale row.
    private static let baselineS: Double = 696
    private static let baselineM: Double = 1126
    private static let baselineL: Double = 1556

    // Column X centres for the 9 weights (from Apple's template).
    private static let columnCenters: [Weight: Double] = [
        .ultralight: 559.711,
        .thin:       856.422,
        .light:      1153.13,
        .regular:    1449.84,
        .medium:     1746.56,
        .semibold:   2043.27,
        .bold:       2339.98,
        .heavy:      2636.69,
        .black:      2933.40,
    ]

    /// Apple's modern templates only ship the 3 anchor weights; Xcode
    /// interpolates the rest. Matching this keeps our output one-to-one
    /// with what SF Symbols app would produce from a designer's source.
    private static let anchorWeights: [Weight] = [.ultralight, .regular, .black]

    private let snooper: StrokeSnooper

    init(snooper: StrokeSnooper? = nil) {
        self.snooper = snooper ?? StrokeSnooper()
    }

    /// Build the template SVG for an icon.
    func generate(for icon: Icon) async throws -> String {
        let slots = try await buildAnchorSlots(for: icon)
        return assembleTemplate(iconName: icon.name, slots: slots)
    }

    /// One per-weight preview suitable for rendering in a `WKWebView`.
    /// Each `svg` is the exact icon content Xcode/SF Symbols app would
    /// display when asked to render that weight — so what the user sees
    /// here is what a developer using this template would ship.
    ///
    /// The viewBox is sized so that the icon's *cap height* equals
    /// `Self.capHeight` (≈ 70.459) units — meaning if you display two of
    /// these at the same pixel height they'll appear at the same optical
    /// size, just like SF Pro symbols.
    struct AnchorPreview {
        var weight: Weight
        /// Self-contained SVG that renders just this slot's icon, on a
        /// viewBox cropped to icon + bearings.
        var svg: String
        /// Cap-height in viewBox units (constant 70.459) — exposed so
        /// callers know the height-to-pointsize conversion factor.
        var capHeight: Double
        /// Total viewBox width / height — useful for aspect-ratio sizing.
        var viewBoxWidth: Double
        var viewBoxHeight: Double
        /// Used by CompareView to detect when all anchors are byte-identical
        /// (e.g. filled-only source with no strokes to scale).
        var innerXMLHash: Int
    }

    func generateAnchorPreviews(for icon: Icon) async throws -> [AnchorPreview] {
        let slots = try await buildAnchorSlots(for: icon)
        return slots.map(previewFromSlot)
    }

    // MARK: - Internals shared by `generate` and `generateAnchorPreviews`

    private func buildAnchorSlots(for icon: Icon) async throws -> [Slot] {
        let scales = Self.anchorWeights.map(\.strokeScale)
        let variants = try await snooper.generateVariants(from: icon.sourceSVG, scales: scales)
        guard variants.count == Self.anchorWeights.count else {
            throw GenerationError.sourceMalformed
        }
        // Compute ONE scale factor — the Regular variant's bbox sized to
        // cap-height — and reuse it across all weights. Heavier weights
        // have bigger bboxes (thicker strokes / wider shapes), so they'll
        // naturally render larger than lighter weights, matching how
        // Apple's actual templates show weight progression visually.
        guard let regularIdx = Self.anchorWeights.firstIndex(of: .regular) else {
            throw GenerationError.sourceMalformed
        }
        let referenceBBox = variants[regularIdx].contentBBox
        guard referenceBBox.height > 0 else { throw GenerationError.missingBBox }
        let sharedScale = Self.capHeight / referenceBBox.height
        return try zip(Self.anchorWeights, variants).map { weight, variant in
            try buildSlot(weight: weight, variant: variant, sharedScale: sharedScale)
        }
    }

    private func previewFromSlot(_ slot: Slot) -> AnchorPreview {
        // viewBox should encompass the icon's tight rendered extents
        // (which can exceed cap-height for heavier weights). Use the
        // slot's scaledHeight (with a small breathing pad) for accuracy,
        // and pin the bottom at y=0 (baseline) — anything above is
        // negative y (toward cap-line + overshoot).
        let slotWidth  = slot.slotRight - slot.slotLeft
        let pad        = Self.capHeight * 0.10
        let topY       = -(slot.scaledHeight + pad)
        let viewBoxH   = slot.scaledHeight + pad * 2
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 \(fmt(topY)) \(fmt(slotWidth)) \(fmt(viewBoxH))">\(slot.innerXML)</svg>
        """
        return AnchorPreview(
            weight: slot.weight,
            svg: svg,
            capHeight: Self.capHeight,
            viewBoxWidth: slotWidth,
            viewBoxHeight: viewBoxH,
            innerXMLHash: slot.innerXML.hashValue
        )
    }

    // MARK: - Per-slot layout

    private struct Slot {
        var weight: Weight
        var slotLeft: Double        // x of left margin line
        var slotRight: Double       // x of right margin line
        var scaledHeight: Double    // height of icon content after scaling
        var innerXML: String        // pre-transformed inner content
        var transform: String       // outer transform on <g id="WeightName-S">
    }

    private func buildSlot(weight: Weight, variant: StrokeSnooper.VariantResult, sharedScale: Double) throws -> Slot {
        let bbox = variant.contentBBox
        guard bbox.width > 0, bbox.height > 0 else {
            throw GenerationError.missingBBox
        }

        // Use the shared scale (from Regular) so heavier weights grow.
        let scale = sharedScale
        let scaledW = bbox.width * scale
        let scaledH = bbox.height * scale

        // Slot is centered on the column X for this weight.
        let columnX = Self.columnCenters[weight] ?? 0
        let slotTotalWidth = scaledW + 2 * Self.sideBearing
        let slotLeft = columnX - slotTotalWidth / 2.0
        let slotRight = slotLeft + slotTotalWidth

        // Inner transform: map source bbox to icon-local coords where the
        // bottom of the bbox sits at y=0 (baseline) and the top at
        // y=-capHeight. X is offset so the icon's left edge is at
        // x=sideBearing (which sits at slotLeft after outer translate).
        let tx = -bbox.x * scale + Self.sideBearing
        let ty = -(bbox.y + bbox.height) * scale
        let innerTransform = "matrix(\(fmt(scale)) 0 0 \(fmt(scale)) \(fmt(tx)) \(fmt(ty)))"
        let innerXML = try extractInnerSVG(variant.svgXML)

        // Outer transform on the <g id="WeightName-S"> just translates
        // to (slotLeft, baseline). No scale here — matches Apple exactly.
        let outerTransform = "matrix(1 0 0 1 \(fmt(slotLeft)) \(fmt(Self.baselineS)))"

        let body = "<g transform=\"\(innerTransform)\">\(innerXML)</g>"

        return Slot(
            weight: weight,
            slotLeft: slotLeft,
            slotRight: slotRight,
            scaledHeight: scaledH,
            innerXML: body,
            transform: outerTransform
        )
    }

    // MARK: - Template assembly

    private func assembleTemplate(iconName: String, slots: [Slot]) -> String {
        let safeName = xmlEscape(iconName)
        var out = ""
        out.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        out.append("\n")
        out.append("""
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 \(fmt(Self.canvasWidth)) \(fmt(Self.canvasHeight))">
        <!--Generator: SF Custom-->
        <style>
        .SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}
        </style>
        """)
        out.append("\n")
        out.append(notesGroup(iconName: safeName))
        out.append("\n")
        out.append(guidesGroup(slots: slots))
        out.append("\n")
        out.append(symbolsGroup(slots: slots))
        out.append("\n")
        out.append("</svg>\n")
        return out
    }

    private func notesGroup(iconName: String) -> String {
        // Column-header labels for all 9 weights — matches Apple even though
        // we only populate 3 slots. Designers like to see the full ladder.
        let weightLabels = [
            ("Ultralight", 559.711),
            ("Thin",       856.422),
            ("Light",     1153.13),
            ("Regular",   1449.84),
            ("Medium",    1746.56),
            ("Semibold",  2043.27),
            ("Bold",      2339.98),
            ("Heavy",     2636.69),
            ("Black",     2933.40),
        ].map { (label, x) in
            """
              <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 \(fmt(x)) 322)">\(label)</text>
            """
        }.joined(separator: "\n")

        return """
        <g id="Notes">
          <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
          <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="292" y2="292"/>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
        \(weightLabels)
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 726)">Small</text>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1156)">Medium</text>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1586)">Large</text>
          <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.7.0</text>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1951)">Generated by SF Custom</text>
          <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Generated from \(iconName)</text>
          <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1987)">Typeset at 100.0 points</text>
        </g>
        """
    }

    private func guidesGroup(slots: [Slot]) -> String {
        // H-reference letter (Apple's reference "H" glyph) at the start of
        // each scale row, so designers have a literal letter for height comparison.
        let hRef = #"<path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.2315-26.7285L12.4385-26.7285ZM55.1196 0L57.7637 0L30.6382-70.459L29.4326-70.459L29.4326-67.1323Z"/>"#

        var lines: [String] = []
        // Scale row markers — small / medium / large
        for (suffix, baseline, capline) in [
            ("S", Self.baselineS, Self.baselineS - Self.capHeight),
            ("M", Self.baselineM, Self.baselineM - Self.capHeight),
            ("L", Self.baselineL, Self.baselineL - Self.capHeight),
        ] {
            lines.append("""
              <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 \(fmt(baseline)))">\(hRef)</g>
              <line id="Baseline-\(suffix)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\(fmt(baseline))" y2="\(fmt(baseline))"/>
              <line id="Capline-\(suffix)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\(fmt(capline))" y2="\(fmt(capline))"/>
            """)
        }
        // Per-anchor-weight margin lines (left + right), measured from
        // the icon's actual bbox so designers can see/adjust the bearings.
        for slot in slots {
            let weightID = slot.weight.templateID
            lines.append("""
              <line id="right-margin-\(weightID)-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(fmt(slot.slotRight))" x2="\(fmt(slot.slotRight))" y1="600.785" y2="720.121"/>
              <line id="left-margin-\(weightID)-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(fmt(slot.slotLeft))" x2="\(fmt(slot.slotLeft))" y1="600.785" y2="720.121"/>
            """)
        }

        return """
        <g id="Guides">
        \(lines.joined(separator: "\n"))
        </g>
        """
    }

    private func symbolsGroup(slots: [Slot]) -> String {
        let bodies = slots.map { slot in
            "  <g id=\"\(slot.weight.templateID)-S\" transform=\"\(slot.transform)\">\n   \(slot.innerXML)\n  </g>"
        }.joined(separator: "\n")
        return """
        <g id="Symbols">
        \(bodies)
        </g>
        """
    }

    // MARK: - SVG helpers

    /// Strip the outer `<svg ...>...</svg>` and return its inner XML.
    private func extractInnerSVG(_ svgXML: String) throws -> String {
        guard let svgOpen = svgXML.range(of: "<svg"),
              let startTagEnd = svgXML.range(of: ">", range: svgOpen.upperBound..<svgXML.endIndex),
              let closing = svgXML.range(of: "</svg>", options: .backwards)
        else { throw GenerationError.sourceMalformed }
        return String(svgXML[startTagEnd.upperBound..<closing.lowerBound])
    }

    private func fmt(_ d: Double) -> String {
        if d.rounded() == d { return String(format: "%.0f", d) }
        return String(format: "%.4f", d)
    }

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
