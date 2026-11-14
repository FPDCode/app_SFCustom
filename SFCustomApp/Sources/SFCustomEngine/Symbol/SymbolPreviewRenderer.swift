import Foundation

/// Small standalone SVGs for on-screen previews (WKWebView).
public enum SymbolPreviewRenderer {

    public struct Preview: Sendable, Hashable {
        public var svg: String
        public var viewBoxWidth: Double
        public var viewBoxHeight: Double
        /// Distance from the top of the viewBox to the baseline (y = 0).
        public var baselineFromTop: Double
        public var capHeight: Double { SymbolTemplateBuilder.capHeight }
    }

    /// Shared vertical frame: from cap line (or higher overshoot) down to
    /// baseline (or lower overshoot), with breathing room. Using the union
    /// over all anchors keeps previews of different weights aligned.
    static func verticalFrame(_ template: SymbolTemplate) -> (top: Double, bottom: Double) {
        var top = -SymbolTemplateBuilder.capHeight, bottom = 0.0
        for a in template.anchors {
            let b = a.contentBounds
            top = min(top, b.minY); bottom = max(bottom, b.maxY)
        }
        let pad = SymbolTemplateBuilder.capHeight * 0.1
        return (top - pad, bottom + pad)
    }

    /// Preview of one geometry inside its slot (margin to margin).
    public static func preview(path: PathModel, margins: AnchorMargins, in template: SymbolTemplate,
                               fill: String = "currentColor") -> Preview {
        let frame = verticalFrame(template)
        let width = margins.left + path.tightBounds.width + margins.right
        let h = frame.bottom - frame.top
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 \(n(frame.top)) \(n(width)) \(n(h))"><path fill="\(fill)" d="\(SVGPathWriter.write(path))"/></svg>
        """
        return Preview(svg: svg, viewBoxWidth: width, viewBoxHeight: h, baselineFromTop: -frame.top)
    }

    public static func preview(anchor: AnchorWeight, in template: SymbolTemplate) -> Preview {
        let a = template.anchor(anchor)
        return preview(path: a.path, margins: a.margins, in: template)
    }

    /// Any weight between Ultralight (0) and Black (2). Uses a fixed
    /// viewBox (widest anchor) so a slider doesn't make the icon jump.
    public static func interpolatedPreview(at position: Double, in template: SymbolTemplate) -> Preview? {
        guard let (path, margins) = template.interpolated(at: position) else { return nil }
        let frame = verticalFrame(template)
        let maxW = template.anchors.map(\.slotWidth).max() ?? 100
        let w = margins.left + path.tightBounds.width + margins.right
        let dx = (maxW - w) / 2
        let h = frame.bottom - frame.top
        let moved = path.transformed(by: .translate(dx, 0))
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 \(n(frame.top)) \(n(maxW)) \(n(h))"><path fill="currentColor" d="\(SVGPathWriter.write(moved))"/></svg>
        """
        return Preview(svg: svg, viewBoxWidth: maxW, viewBoxHeight: h, baselineFromTop: -frame.top)
    }

    /// The talk's onion-skin technique: the three anchors stacked at 50 %
    /// opacity, centred on each other, plus a dot at each part's start
    /// point and its order number — so "different starting point" and
    /// "wrong path order" become visible at a glance.
    public static func onionSkin(_ template: SymbolTemplate, showMarkers: Bool = true) -> Preview {
        let tints: [AnchorWeight: String] = [.ultralight: "#1E88E5", .regular: "#757575", .black: "#E53935"]
        let frame = verticalFrame(template)
        let maxW = template.anchors.map(\.slotWidth).max() ?? 100
        let h = frame.bottom - frame.top
        let r = SymbolTemplateBuilder.capHeight * 0.025
        var body = ""
        var markers = ""
        for a in template.anchors {
            let dx = (maxW - a.slotWidth) / 2
            let p = a.path.transformed(by: .translate(dx, 0))
            let tint = tints[a.weight] ?? "#000"
            body += "<path fill=\"\(tint)\" fill-opacity=\"0.35\" stroke=\"\(tint)\" stroke-width=\"0.4\" d=\"\(SVGPathWriter.write(p))\"/>"
            guard showMarkers else { continue }
            for (i, sp) in p.subpaths.enumerated() {
                guard let s = sp.start else { continue }
                markers += "<circle cx=\"\(n(s.x))\" cy=\"\(n(s.y))\" r=\"\(n(r))\" fill=\"\(tint)\"/>"
                if a.weight == .regular {
                    markers += "<text x=\"\(n(s.x + r * 1.6))\" y=\"\(n(s.y - r * 1.6))\" font-size=\"\(n(r * 4))\" font-family=\"-apple-system, sans-serif\" fill=\"\(tint)\">\(i + 1)</text>"
                }
            }
        }
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 \(n(frame.top)) \(n(maxW)) \(n(h))">\(body)\(markers)</svg>
        """
        return Preview(svg: svg, viewBoxWidth: maxW, viewBoxHeight: h, baselineFromTop: -frame.top)
    }

    static func n(_ v: Double) -> String { SVGPathWriter.num(v, 3) }
}
