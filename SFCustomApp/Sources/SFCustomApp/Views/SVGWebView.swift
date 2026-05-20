import SwiftUI
import WebKit

/// Thin SwiftUI wrapper around a `WKWebView` that renders an SVG string.
/// We use a WebView so the live preview matches StrokeSnooper's view of
/// the world — same CSS engine, same stroke-width resolution.
struct SVGWebView: NSViewRepresentable {
    var svg: String
    var background: Color = .clear
    var padding: Double = 12
    /// When non-nil, every `fill` and `stroke` in the SVG is forced to
    /// this colour (except explicit `none`/`transparent` ones). Used by
    /// the Compare view to keep monochrome icons readable in dark mode.
    var tint: Color? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsMagnification = false
        wv.isInspectable = false
        return wv
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let bgHex = nsColorHex(background)
        let tintCSS: String
        if let tint, let tintHex = nsColorHexOrNil(tint) {
            tintCSS = """
              svg [fill]:not([fill="none"]):not([fill="transparent"]) { fill: \(tintHex) !important; }
              svg [stroke]:not([stroke="none"]):not([stroke="transparent"]) { stroke: \(tintHex) !important; }
              svg, svg * { color: \(tintHex); }
            """
        } else {
            tintCSS = ""
        }
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html,body { margin:0; padding:0; height:100%; background:\(bgHex); }
          .stage { box-sizing:border-box; padding:\(padding)px; height:100%;
                   display:flex; align-items:center; justify-content:center; }
          .stage svg { width:100%; height:100%; max-width:100%; max-height:100%; display:block; }
          \(tintCSS)
        </style>
        </head><body><div class="stage">\(svg)</div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func nsColorHex(_ color: Color) -> String {
        if color == .clear { return "transparent" }
        return nsColorHexOrNil(color) ?? "transparent"
    }

    private func nsColorHexOrNil(_ color: Color) -> String? {
        if color == .clear { return nil }
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Smaller, animation-friendly thumbnail variant.
struct SVGThumbnail: View {
    var svg: String
    var body: some View {
        SVGWebView(svg: svg, background: .clear, padding: 4)
            .allowsHitTesting(false)
    }
}

#if canImport(AppKit)
import AppKit
#endif
