import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - Stroke style

public enum LineJoin: String, Sendable, Hashable { case miter, round, bevel }
public enum LineCap: String, Sendable, Hashable { case butt, round, square }

public struct StrokeStyle: Hashable, Sendable {
    public var width: Double
    public var join: LineJoin
    public var cap: LineCap
    public var miterLimit: Double

    public init(width: Double, join: LineJoin = .miter, cap: LineCap = .butt, miterLimit: Double = 4) {
        self.width = width
        self.join = join
        self.cap = cap
        self.miterLimit = miterLimit
    }
}

/// One drawable element after flattening groups and transforms.
public struct SVGShape: Hashable, Sendable {
    /// Geometry in root user space (all ancestor transforms baked in).
    public var path: PathModel
    /// True when the element paints a fill (`fill` not `none`).
    public var isFilled: Bool
    /// Present when the element paints a stroke with a positive width.
    /// The width is already multiplied by the element's transform scale.
    public var stroke: StrokeStyle?
    public var elementName: String
    public var id: String?
}

/// Reads an SVG document into flattened `SVGShape`s.
///
/// Handles: path, rect (incl. rx/ry), circle, ellipse, line, polyline,
/// polygon; nested `<g>`/`<svg>` with `transform`; presentation attributes
/// and inline `style` with inheritance. Skips non-rendered containers
/// (defs, clipPath, mask, symbol, marker, pattern, gradients) and anything
/// with `display:none`.
///
/// Feed it the output of the app's `StrokeSnooper` (computed styles baked
/// onto attributes) for full CSS fidelity; plain SVGs work too.
public enum SVGShapeReader {

    public struct Report: Sendable {
        public var shapes: [SVGShape]
        /// Element names that were present but not converted (e.g. `text`, `use`, `image`).
        public var unsupportedElements: [String]
    }

    /// - Parameter groupID: when set, only elements inside the element with
    ///   this `id` are returned (used to read `Regular-S` etc. from a template).
    public static func read(_ svg: String, insideElementWithID groupID: String? = nil) -> Report {
        let delegate = Delegate(targetID: groupID)
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return Report(shapes: delegate.shapes, unsupportedElements: Array(Set(delegate.unsupported)).sorted())
    }

    /// Convenience: all geometry inside `groupID` merged into one PathModel.
    public static func path(_ svg: String, insideElementWithID groupID: String? = nil) -> PathModel {
        var p = PathModel()
        for s in read(svg, insideElementWithID: groupID).shapes { p.append(s.path) }
        return p
    }

    // MARK: - Element → PathModel

    static func geometry(element name: String, attributes a: [String: String]) -> PathModel? {
        func n(_ key: String, _ def: Double = 0) -> Double {
            guard let v = a[key] else { return def }
            return SVGNumberScanner.numbers(in: v).first ?? def
        }
        switch name {
        case "path":
            guard let d = a["d"] else { return nil }
            return try? SVGPathParser.parse(d)
        case "rect":
            return rect(x: n("x"), y: n("y"), w: n("width"), h: n("height"),
                        rx: a["rx"].flatMap { SVGNumberScanner.numbers(in: $0).first },
                        ry: a["ry"].flatMap { SVGNumberScanner.numbers(in: $0).first })
        case "circle":
            let r = n("r")
            return ellipse(cx: n("cx"), cy: n("cy"), rx: r, ry: r)
        case "ellipse":
            return ellipse(cx: n("cx"), cy: n("cy"), rx: n("rx"), ry: n("ry"))
        case "line":
            var b = PathBuilder()
            b.move(to: Point(n("x1"), n("y1")))
            b.line(to: Point(n("x2"), n("y2")))
            return b.finish()
        case "polyline", "polygon":
            let nums = SVGNumberScanner.numbers(in: a["points"] ?? "")
            guard nums.count >= 4 else { return nil }
            var b = PathBuilder()
            b.move(to: Point(nums[0], nums[1]))
            var i = 2
            while i + 1 < nums.count { b.line(to: Point(nums[i], nums[i + 1])); i += 2 }
            if name == "polygon" { b.close() }
            return b.finish()
        default:
            return nil
        }
    }

    static func rect(x: Double, y: Double, w: Double, h: Double, rx rxIn: Double?, ry ryIn: Double?) -> PathModel? {
        guard w > 0, h > 0 else { return nil }
        var rx = rxIn ?? ryIn ?? 0
        var ry = ryIn ?? rxIn ?? 0
        rx = min(max(0, rx), w / 2)
        ry = min(max(0, ry), h / 2)
        var b = PathBuilder()
        if rx <= 0 || ry <= 0 {
            b.move(to: Point(x, y))
            b.line(to: Point(x + w, y))
            b.line(to: Point(x + w, y + h))
            b.line(to: Point(x, y + h))
            b.close()
        } else {
            b.move(to: Point(x + rx, y))
            b.line(to: Point(x + w - rx, y))
            b.arc(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, to: Point(x + w, y + ry))
            b.line(to: Point(x + w, y + h - ry))
            b.arc(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, to: Point(x + w - rx, y + h))
            b.line(to: Point(x + rx, y + h))
            b.arc(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, to: Point(x, y + h - ry))
            b.line(to: Point(x, y + ry))
            b.arc(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, to: Point(x + rx, y))
            b.close()
        }
        return b.finish()
    }

    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> PathModel? {
        guard rx > 0, ry > 0 else { return nil }
        let k = 0.5522847498307936
        let r = Point(cx + rx, cy), bt = Point(cx, cy + ry), l = Point(cx - rx, cy), t = Point(cx, cy - ry)
        let segs = [
            Segment(r, Point(cx + rx, cy + ry * k), Point(cx + rx * k, cy + ry), bt),
            Segment(bt, Point(cx - rx * k, cy + ry), Point(cx - rx, cy + ry * k), l),
            Segment(l, Point(cx - rx, cy - ry * k), Point(cx - rx * k, cy - ry), t),
            Segment(t, Point(cx + rx * k, cy - ry), Point(cx + rx, cy - ry * k), r),
        ]
        return PathModel(subpaths: [Subpath(segments: segs, isClosed: true)])
    }

    // MARK: - XML walk

    private struct Context {
        var transform: AffineTransform2D = .identity
        var style: [String: String] = [:]
        var inTarget: Bool
        var hidden: Bool = false
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let targetID: String?
        var stack: [Context]
        var shapes: [SVGShape] = []
        var unsupported: [String] = []

        static let inherited: Set<String> = [
            "fill", "stroke", "stroke-width", "stroke-linejoin", "stroke-linecap",
            "stroke-miterlimit", "fill-rule", "visibility",
        ]
        static let nonRendered: Set<String> = [
            "defs", "clipPath", "mask", "symbol", "marker", "pattern",
            "linearGradient", "radialGradient", "filter", "style", "title", "desc", "metadata",
        ]
        static let shapeNames: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]
        static let containers: Set<String> = ["svg", "g", "a", "switch"]

        init(targetID: String?) {
            self.targetID = targetID
            self.stack = [Context(inTarget: targetID == nil)]
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attrs: [String: String] = [:]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            var ctx = stack.last!
            if targetID != nil, attrs["id"] == targetID { ctx.inTarget = true }

            // Resolve presentation attributes + inline style (style wins).
            var own: [String: String] = [:]
            for (k, v) in attrs where Self.inherited.contains(k) || k == "display" || k == "opacity" { own[k] = v }
            if let style = attrs["style"] {
                for decl in style.split(separator: ";") {
                    let parts = decl.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    own[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            for (k, v) in own where Self.inherited.contains(k) { ctx.style[k] = v }
            if own["display"] == "none" || Self.nonRendered.contains(local) { ctx.hidden = true }

            if let t = attrs["transform"] {
                ctx.transform = ctx.transform.concatenating(AffineTransform2D.parse(t))
            }
            if local == "svg", stack.count > 1 {
                // Nested <svg>: honour x/y offset (viewBox scaling is ignored).
                let x = SVGNumberScanner.numbers(in: attrs["x"] ?? "0").first ?? 0
                let y = SVGNumberScanner.numbers(in: attrs["y"] ?? "0").first ?? 0
                ctx.transform = ctx.transform.concatenating(.translate(x, y))
            }
            stack.append(ctx)

            guard ctx.inTarget, !ctx.hidden else { return }
            if Self.shapeNames.contains(local) {
                guard let geo = SVGShapeReader.geometry(element: local, attributes: attrs), !geo.isEmpty else { return }
                if ctx.style["visibility"] == "hidden" { return }
                let path = geo.transformed(by: ctx.transform)
                let fill = (ctx.style["fill"] ?? "black").lowercased()
                let strokePaint = (ctx.style["stroke"] ?? "none").lowercased()
                var stroke: StrokeStyle?
                if strokePaint != "none" && strokePaint != "transparent" {
                    let w = SVGNumberScanner.numbers(in: ctx.style["stroke-width"] ?? "1").first ?? 1
                    let scaled = w * ctx.transform.meanScale
                    if scaled > 0 {
                        stroke = StrokeStyle(
                            width: scaled,
                            join: LineJoin(rawValue: ctx.style["stroke-linejoin"] ?? "") ?? .miter,
                            cap: LineCap(rawValue: ctx.style["stroke-linecap"] ?? "") ?? .butt,
                            miterLimit: SVGNumberScanner.numbers(in: ctx.style["stroke-miterlimit"] ?? "4").first ?? 4
                        )
                    }
                }
                let isFilled = fill != "none" && fill != "transparent"
                guard isFilled || stroke != nil else { return }
                shapes.append(SVGShape(path: path, isFilled: isFilled, stroke: stroke,
                                       elementName: local, id: attrs["id"]))
            } else if !Self.containers.contains(local) {
                unsupported.append(local)
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            if stack.count > 1 { stack.removeLast() }
        }
    }
}
