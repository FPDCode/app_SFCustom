import Foundation

/// Builds an Apple SF Symbol template SVG by:
///   1. Asking `StrokeSnooper` for 9 weight-scaled variants of the source SVG.
///   2. Inserting each variant into the 27 (9 weights × 3 scales) slot groups
///      in the bundled SF Symbol template.
@MainActor
final class TemplateGenerator {

    enum GenerationError: Error, LocalizedError {
        case templateMissing
        case sourceMalformed
        case slotNotFound(weight: Weight, scale: Scale)

        var errorDescription: String? {
            switch self {
            case .templateMissing:
                return "Bundled SF Symbol template not found."
            case .sourceMalformed:
                return "Source SVG didn't expose a usable root element."
            case .slotNotFound(let w, let s):
                return "Template slot \(w.templateID)-\(s.templateSuffix) wasn't found."
            }
        }
    }

    // Column X anchors (text-anchor:middle) measured from Apple's
    // Template v7.0 export. Distance between columns is 296.711 units.
    private static let columnX: [Weight: Double] = [
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

    /// Target visual height of the source icon at Small scale, in template
    /// canvas units. Matches Apple's recommended sizing (≈ 2× cap height).
    private static let smallTargetHeight: Double = 140.0

    private let snooper: StrokeSnooper

    init(snooper: StrokeSnooper? = nil) {
        self.snooper = snooper ?? StrokeSnooper()
    }

    /// Produce the full SF Symbol template SVG XML for `icon`.
    func generate(for icon: Icon) async throws -> String {
        let variants = try await snooper.generateAllWeights(from: icon.sourceSVG)
        return try buildTemplate(iconName: icon.name, variants: variants)
    }

    // MARK: - Template assembly

    private func buildTemplate(
        iconName: String,
        variants: [Weight: StrokeSnooper.VariantResult]
    ) throws -> String {
        var template = try loadBundledTemplate()

        // Inject descriptive-name so Xcode shows the icon's name.
        template = injectDescriptiveName(into: template, iconName: iconName)

        for weight in Weight.allCases {
            guard let variant = variants[weight] else { continue }
            let innerXML = try extractInnerSVG(variant.svgXML)
            let viewBox = ViewBox(width: variant.sourceWidth, height: variant.sourceHeight)
            for scale in Scale.allCases {
                let slotBody = renderSlot(
                    innerXML: innerXML,
                    viewBox: viewBox,
                    weight: weight,
                    scale: scale
                )
                template = try injectSlot(
                    template: template,
                    weight: weight,
                    scale: scale,
                    body: slotBody
                )
            }
        }

        return template
    }

    /// Build the inner contents of a single `<g id="Weight-Scale">` slot.
    /// The icon is scaled to a target height that grows with scale, and
    /// translated so its horizontal center sits on the column X and its
    /// bottom edge sits on the row baseline.
    private func renderSlot(
        innerXML: String,
        viewBox: ViewBox,
        weight: Weight,
        scale: Scale
    ) -> String {
        let height = max(viewBox.height, 0.0001)
        let width  = max(viewBox.width,  0.0001)

        let targetHeight = Self.smallTargetHeight * scale.sizeScale
        let s = targetHeight / height // uniform scale to hit target height
        let renderedWidth  = width  * s
        let renderedHeight = height * s

        let columnCenter = Self.columnX[weight] ?? 0
        let baselineY = scale.baselineY

        let tx = columnCenter - renderedWidth / 2.0
        let ty = baselineY - renderedHeight

        let m = "matrix(\(fmt(s)) 0 0 \(fmt(s)) \(fmt(tx)) \(fmt(ty)))"
        return "<g transform=\"\(m)\">\(innerXML)</g>"
    }

    private struct ViewBox {
        var width: Double
        var height: Double
    }

    // MARK: - Template I/O

    private func loadBundledTemplate() throws -> String {
        guard let url = Bundle.module.url(forResource: "sf-symbol-template", withExtension: "svg"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8)
        else { throw GenerationError.templateMissing }
        // The bundled template's CDATA slot is for the original-XML embed;
        // remove it since we inject per-slot content instead.
        return str.replacingOccurrences(of: "<![CDATA[${original_svg_xml}]]>", with: "")
    }

    private func injectDescriptiveName(into template: String, iconName: String) -> String {
        // The Custom Symbols template uses placeholders like ${...}. Replace
        // any we recognize, and append a `descriptive-name` text element so
        // Xcode 26+ surfaces the icon name in the picker.
        var out = template
            .replacingOccurrences(of: "${cs_version_string}", with: "SF Custom 1.0")
            .replacingOccurrences(of: "${guide_left}",  with: "0")
            .replacingOccurrences(of: "${guide_right}", with: "0")
            .replacingOccurrences(of: "${guide_cap}",   with: "70.459")
            .replacingOccurrences(of: "${guide_base}",  with: "0")
            .replacingOccurrences(of: "${refscale}",    with: "1")
            .replacingOccurrences(of: "${stroke_scale_min}", with: "\(Weight.ultralight.strokeScale)")
            .replacingOccurrences(of: "${stroke_scale_max}", with: "\(Weight.black.strokeScale)")

        // Add a descriptive-name line near the existing template-version line.
        let escaped = xmlEscape(iconName)
        let nameLine = """
        <text id="descriptive-name" style="stroke:none;fill:black;font-family:-apple-system,&quot;SF Pro Display&quot;,&quot;SF Pro Text&quot;,Helvetica,sans-serif;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Generated from \(escaped)</text>
        """
        out = out.replacingOccurrences(
            of: "<text id=\"template-version\"",
            with: nameLine + "\n  <text id=\"template-version\""
        )
        return out
    }

    /// Replace `<g id="Weight-Scale"></g>` with `<g id="Weight-Scale">\(body)</g>`.
    private func injectSlot(
        template: String,
        weight: Weight,
        scale: Scale,
        body: String
    ) throws -> String {
        let slotID = "\(weight.templateID)-\(scale.templateSuffix)"
        let opener = "<g id=\"\(slotID)\">"
        let needle = "\(opener)</g>"
        guard let range = template.range(of: needle) else {
            throw GenerationError.slotNotFound(weight: weight, scale: scale)
        }
        return template.replacingCharacters(in: range, with: "\(opener)\(body)</g>")
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
