import SwiftUI
import WebKit

/// Thin SwiftUI wrapper around a `WKWebView` that renders an SVG string.
/// We use a WebView so the live preview matches StrokeSnooper's view of
/// the world — same CSS engine, same stroke-width resolution.
struct SVGWebView: NSViewRepresentable {
    var svg: String
    var background: Color = .clear
    var padding: Double = 12

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
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html,body { margin:0; padding:0; height:100%; background:\(bgHex); }
          .stage { box-sizing:border-box; padding:\(padding)px; height:100%;
                   display:flex; align-items:center; justify-content:center; }
          .stage svg { width:100%; height:100%; max-width:100%; max-height:100%; display:block; }
        </style>
        </head><body><div class="stage">\(svg)</div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func nsColorHex(_ color: Color) -> String {
        if color == .clear { return "transparent" }
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
