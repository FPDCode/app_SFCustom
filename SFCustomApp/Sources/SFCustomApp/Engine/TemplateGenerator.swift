import Foundation
import SFCustomEngine

/// Bridge between the app and `SFCustomEngine`.
///
///  1. `StrokeSnooper` renders the source SVG in WebKit once (scale 1.0) so
///     every CSS-derived style (classes, `<style>` blocks, inheritance,
///     `currentColor`) is baked onto attributes.
///  2. `SymbolTemplateBuilder` turns that into an Apple Template v.7.0
///     whose three anchors are **filled, point-compatible outlines**:
///     strokes are outlined by `CompatibleStroker`, the Regular stroke is
///     normalised to the ladder (2 · 7 · 13 by default), and
///     `CompatibilityChecker` verifies the result.
///
/// Settings (ladder, margins, mode) come from `SymbolSettings` + the icon.
@MainActor
final class TemplateGenerator {

    private let snooper: StrokeSnooper

    init(snooper: StrokeSnooper? = nil) {
        self.snooper = snooper ?? StrokeSnooper()
    }

    /// Full engine result: anchors, compatibility report, warnings.
    func build(for icon: Icon) async throws -> SymbolTemplate {
        let baked = await bakedSVG(icon.sourceSVG)
        return try SymbolTemplateBuilder.build(sourceSVG: baked, options: SymbolSettings.options(for: icon))
    }

    /// Template SVG ready for Xcode / SF Symbols app.
    func generate(for icon: Icon) async throws -> String {
        try await build(for: icon).svg
    }

    /// One preview per anchor weight, as rendered by Xcode.
    struct AnchorPreview {
        var weight: Weight
        /// Self-contained SVG of just this anchor, margin to margin.
        var svg: String
        /// Cap height in viewBox units (70.459).
        var capHeight: Double
        var viewBoxWidth: Double
        var viewBoxHeight: Double
        /// Distance from the viewBox top to the baseline, for text alignment.
        var baselineFromTop: Double
        /// Lets CompareView detect byte-identical anchors (no strokes).
        var innerXMLHash: Int
    }

    func generateAnchorPreviews(for icon: Icon) async throws -> [AnchorPreview] {
        Self.anchorPreviews(from: try await build(for: icon))
    }

    static func anchorPreviews(from template: SymbolTemplate) -> [AnchorPreview] {
        template.anchors.map { a in
            let p = SymbolPreviewRenderer.preview(anchor: a.weight, in: template)
            return AnchorPreview(weight: Weight(a.weight), svg: p.svg, capHeight: p.capHeight,
                                 viewBoxWidth: p.viewBoxWidth, viewBoxHeight: p.viewBoxHeight,
                                 baselineFromTop: p.baselineFromTop,
                                 innerXMLHash: SVGPathWriter.write(a.path).hashValue)
        }
    }

    /// Source SVG with computed styles baked in. Falls back to the raw
    /// source if WebKit can't render it (the engine still reads plain
    /// presentation attributes and inline styles).
    private func bakedSVG(_ source: String) async -> String {
        do {
            let variants = try await snooper.generateVariants(from: source, scales: [1.0])
            return variants.first?.svgXML ?? source
        } catch {
            return source
        }
    }
}
