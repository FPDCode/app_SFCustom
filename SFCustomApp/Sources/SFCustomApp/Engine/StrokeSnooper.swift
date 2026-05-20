import Foundation
import WebKit

/// Renders a source SVG in an off-screen `WKWebView`, walks every element
/// using `getComputedStyle()` so CSS-inherited stroke-widths are resolved,
/// and produces N variants where each stroke-width is multiplied by a per-
/// weight scale factor.
///
/// This mirrors Custom Symbols.app's approach. The WebView is what makes
/// it robust: it correctly resolves `stroke-width` whether the source SVG
/// uses an attribute, an inline `style`, a `<style>` block, inheritance
/// through `<g>` parents, percentages, or CSS variables — because we ask
/// the browser, not a regex.
@MainActor
final class StrokeSnooper: NSObject {
    enum SnoopError: Error, LocalizedError {
        case noSVGRoot
        case javascriptFailure(String)
        case unexpectedResult

        var errorDescription: String? {
            switch self {
            case .noSVGRoot:
                return "Couldn't find an <svg> root in the source."
            case .javascriptFailure(let msg):
                return "SVG inspection failed: \(msg)"
            case .unexpectedResult:
                return "SVG inspection returned an unexpected result."
            }
        }
    }

    struct VariantResult {
        /// Width/height extracted from the source SVG (used to position
        /// the variant inside the template canvas).
        var sourceWidth: Double
        var sourceHeight: Double
        /// The SVG XML for this variant (root `<svg>` element).
        var svgXML: String
        /// The stroke scale used to generate it.
        var strokeScale: Double
        /// Tight bounding box of the rendered content (after stroke
        /// scaling) — i.e. what the browser would `getBBox()` on the
        /// root SVG element. Used by TemplateGenerator to size the icon
        /// at cap-height regardless of viewBox padding.
        var contentBBox: BBox
    }

    struct BBox: Hashable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private var webView: WKWebView?

    override init() {
        super.init()
    }

    /// Produce one variant per provided stroke scale. The order of the
    /// returned array matches the order of `scales`.
    func generateVariants(from sourceSVG: String, scales: [Double]) async throws -> [VariantResult] {
        let webView = makeWebView()
        try await load(svg: sourceSVG, into: webView)

        var results: [VariantResult] = []
        for scale in scales {
            let variant = try await runSnoop(scale: scale, on: webView)
            results.append(variant)
        }
        return results
    }

    /// Convenience: produce one variant per `Weight`.
    func generateAllWeights(from sourceSVG: String) async throws -> [Weight: VariantResult] {
        let weights = Weight.allCases
        let variants = try await generateVariants(
            from: sourceSVG,
            scales: weights.map(\.strokeScale)
        )
        var out: [Weight: VariantResult] = [:]
        for (w, v) in zip(weights, variants) {
            out[w] = v
        }
        return out
    }

    // MARK: - WKWebView plumbing

    private func makeWebView() -> WKWebView {
        if let existing = webView { return existing }
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 800), configuration: config)
        webView = wv
        return wv
    }

    private func load(svg: String, into webView: WKWebView) async throws {
        // Wrap the SVG in a minimal HTML host so the browser's CSS engine
        // resolves stroke-width correctly. The trailing <script> announces
        // readiness so we can await it deterministically.
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>html,body{margin:0;padding:0;background:transparent;}svg{display:block;}</style>
        </head><body>\(svg)<script>window.__svgReady = true;</script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        try await waitUntilReady(webView)
    }

    private func waitUntilReady(_ webView: WKWebView) async throws {
        for _ in 0..<200 {
            let ready = try? await webView.evaluateJavaScript("window.__svgReady === true && document.getElementsByTagName('svg').length > 0") as? Bool
            if ready == true { return }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        throw SnoopError.noSVGRoot
    }

    private func runSnoop(scale: Double, on webView: WKWebView) async throws -> VariantResult {
        let js = Self.snoopJS(strokeScale: scale)
        let raw: Any?
        do {
            raw = try await webView.evaluateJavaScript(js)
        } catch {
            throw SnoopError.javascriptFailure(error.localizedDescription)
        }
        guard let dict = raw as? [String: Any],
              let xml = dict["xml"] as? String,
              let w = (dict["width"] as? NSNumber)?.doubleValue,
              let h = (dict["height"] as? NSNumber)?.doubleValue
        else {
            throw SnoopError.unexpectedResult
        }
        let bb = dict["bbox"] as? [String: Any]
        let bbox = BBox(
            x:      (bb?["x"]      as? NSNumber)?.doubleValue ?? 0,
            y:      (bb?["y"]      as? NSNumber)?.doubleValue ?? 0,
            width:  (bb?["width"]  as? NSNumber)?.doubleValue ?? w,
            height: (bb?["height"] as? NSNumber)?.doubleValue ?? h
        )
        return VariantResult(sourceWidth: w, sourceHeight: h, svgXML: xml, strokeScale: scale, contentBBox: bbox)
    }

    // MARK: - The JavaScript

    /// JS that:
    ///  1. Finds the root `<svg>`.
    ///  2. Clones it into a detached node so live styles still resolve.
    ///  3. Walks every element; for each, materializes computed stroke,
    ///     fill, stroke-linejoin, stroke-linecap, fill-rule onto attributes,
    ///     and rewrites `stroke-width` as `existing × strokeScale`.
    ///  4. Serializes the clone with XMLSerializer and returns dimensions.
    private static func snoopJS(strokeScale: Double) -> String {
        """
        (function() {
            var STROKE_SCALE = \(strokeScale);
            var STROKE_ELEMENTS = new Set([
                'altGlyph','circle','ellipse','line','path','polygon',
                'polyline','rect','text','textPath','tref','tspan'
            ]);

            var svgs = document.getElementsByTagName('svg');
            if (!svgs.length) return null;
            var original = svgs[0];

            var width = original.width && original.width.baseVal ? original.width.baseVal.value : 0;
            var height = original.height && original.height.baseVal ? original.height.baseVal.value : 0;
            if (!width || !height) {
                var vb = (original.getAttribute('viewBox') || '').trim().split(/\\s+/);
                if (vb.length === 4) {
                    width  = parseFloat(vb[2]) || width;
                    height = parseFloat(vb[3]) || height;
                }
            }

            function materialize(src, dst) {
                var cs;
                try { cs = window.getComputedStyle(src); } catch (e) { cs = null; }
                if (!cs) return;

                function bake(key, attr) {
                    var v = cs[key];
                    if (v == null || v === '') return;
                    // Convert rgba() -> rgb() + separate -opacity attr.
                    if (typeof v === 'string' && v.indexOf('rgba(') === 0) {
                        var inner = v.substring(5, v.lastIndexOf(')'));
                        var parts = inner.split(',').map(function(x){return x.trim();});
                        if (parts.length === 4) {
                            dst.setAttribute(attr, 'rgb(' + parts[0] + ',' + parts[1] + ',' + parts[2] + ')');
                            dst.setAttribute(attr + '-opacity', parts[3]);
                            return;
                        }
                    }
                    dst.setAttribute(attr, v);
                }

                bake('stroke', 'stroke');
                bake('fill', 'fill');
                if (cs.strokeLinejoin)  dst.setAttribute('stroke-linejoin',  cs.strokeLinejoin);
                if (cs.strokeLinecap)   dst.setAttribute('stroke-linecap',   cs.strokeLinecap);
                if (cs.strokeMiterlimit)dst.setAttribute('stroke-miterlimit',cs.strokeMiterlimit);
                if (cs.fillRule)        dst.setAttribute('fill-rule',        cs.fillRule);

                // Stroke-width: scale and persist as attribute (px units stripped).
                if (STROKE_ELEMENTS.has(src.nodeName) || STROKE_ELEMENTS.has(src.tagName)) {
                    var sw = cs.strokeWidth;
                    if (sw && sw !== '0' && sw !== '0px') {
                        var isPct = sw.charAt(sw.length - 1) === '%';
                        var n = parseFloat(sw);
                        if (!isNaN(n) && isFinite(n)) {
                            var scaled = n * STROKE_SCALE;
                            dst.setAttribute('stroke-width', isPct ? (scaled + '%') : String(scaled));
                            if (dst.style) dst.style.strokeWidth = '';
                        }
                    }
                }

                // Strip inline style so attributes are the source of truth.
                if (dst.removeAttribute) dst.removeAttribute('style');
            }

            function walk(src, dst) {
                materialize(src, dst);
                var sChildren = src.children || [];
                var dChildren = dst.children || [];
                var n = Math.min(sChildren.length, dChildren.length);
                for (var i = 0; i < n; i++) walk(sChildren[i], dChildren[i]);
            }

            var clone = original.cloneNode(true);
            walk(original, clone);
            // Make sure viewBox is set on the variant so downstream renderers can scale.
            if (!clone.getAttribute('viewBox') && width && height) {
                clone.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
            }

            // To get a tight bbox AFTER stroke scaling we have to mount
            // the modified clone into the live DOM (getBBox only works on
            // rendered elements). Off-screen, measure, then remove.
            var bbox = { x: 0, y: 0, width: width, height: height };
            try {
                var host = document.createElement('div');
                host.style.cssText = 'position:absolute;left:-9999px;top:-9999px;width:' + width + 'px;height:' + height + 'px;';
                document.body.appendChild(host);
                host.appendChild(clone);
                var liveBBox = clone.getBBox();
                bbox = {
                    x: liveBBox.x, y: liveBBox.y,
                    width: liveBBox.width, height: liveBBox.height
                };
                document.body.removeChild(host);
            } catch (e) {
                // Some SVGs (no rendered children) throw — fall back.
            }

            var xml = new XMLSerializer().serializeToString(clone);
            return { xml: xml, width: width, height: height, bbox: bbox };
        })();
        """
    }
}
