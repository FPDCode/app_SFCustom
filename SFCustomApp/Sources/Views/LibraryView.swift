import SwiftUI
import UniformTypeIdentifiers
import SwiftDraw

/// Sidebar view showing the icon library with search, list, and drag-and-drop import
struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var isTargeted = false

    var filteredIcons: [Icon] {
        if searchText.isEmpty {
            return appState.library.icons
        }
        return appState.library.search(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.headline)
                Spacer()
                Text("\(appState.library.icons.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Icon list
            if filteredIcons.isEmpty {
                emptyLibrary
            } else {
                List(filteredIcons, selection: Binding(
                    get: { appState.selectedIcon?.id },
                    set: { id in
                        appState.selectedIcon = appState.library.icons.first { $0.id == id }
                    }
                )) { icon in
                    iconRow(icon)
                        .contextMenu {
                            Button("Duplicate") { duplicateIcon(icon) }
                            Divider()
                            Button("Delete", role: .destructive) { appState.removeIcon(icon) }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .searchable(text: $searchText, prompt: "Search icons...")
        .onDrop(of: [.svg, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue, lineWidth: 2)
                    .background(.blue.opacity(0.05))
                    .padding(4)
            }
        }
    }

    // MARK: - Icon Row

    private func iconRow(_ icon: Icon) -> some View {
        HStack(spacing: 12) {
            // Mini preview of the icon path
            IconThumbnail(icon: icon, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(icon.name)
                    .font(.body)
                    .lineLimit(1)
                Text("U+\(String(icon.unicodeCodepoint, radix: 16, uppercase: true))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Weight mode indicator
            weightModeIcon(icon.weightMode)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func weightModeIcon(_ mode: WeightMode) -> some View {
        Group {
            switch mode {
            case .uniform:
                Image(systemName: "equal.circle")
            case .singleGenerate:
                Image(systemName: "wand.and.stars")
            case .fullControl:
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    // MARK: - Empty State

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No icons yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Drag an SVG file here\nor use the + button")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      url.pathExtension.lowercased() == "svg" else { return }

                Task { @MainActor in
                    importSVG(from: url)
                }
            }
        }
        return true
    }

    private func importSVG(from url: URL) {
        do {
            let svgContent = try String(contentsOf: url, encoding: .utf8)
            let paths = try SVGParser.extractPaths(from: svgContent)
            let mergedPath = SVGParser.mergePaths(paths)

            let name = url.deletingPathExtension().lastPathComponent
            let icon = Icon(name: name, svgPath: mergedPath)
            appState.addIcon(icon)
        } catch {
            appState.statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func duplicateIcon(_ icon: Icon) {
        var copy = Icon(name: "\(icon.name)-copy", svgPath: icon.masters.regular)
        copy.masters = icon.masters
        copy.weightMode = icon.weightMode
        copy.tags = icon.tags
        appState.addIcon(copy)
    }
}

// MARK: - Icon Thumbnail

/// Renders a small preview of an icon. When given a full SVG document
/// (via `sourceSVG`), parses every <path> with its strokes and fills.
/// Falls back to single-path rendering for legacy icons.
struct IconThumbnail: View {
    let pathData: String
    let sourceSVG: String?
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(pathData: String, sourceSVG: String? = nil, size: CGFloat) {
        self.pathData = pathData
        self.sourceSVG = sourceSVG
        self.size = size
    }

    init(icon: Icon, size: CGFloat) {
        self.pathData = icon.masters.regular
        self.sourceSVG = icon.sourceSVG
        self.size = size
    }

    /// Adapt the captured SVG's hard-coded `fill="black"` to the current
    /// color scheme. SwiftDraw renders the SVG with its embedded colors;
    /// since icons are always captured as black-on-transparent, in dark mode
    /// they'd render invisibly. Swap to white for high contrast.
    private func recoloredSVG(_ svg: String) -> String {
        guard colorScheme == .dark else { return svg }
        // Match `fill="black"`, `fill="#000"`, `fill="#000000"`, and the
        // CSS equivalent inside `style="…;fill:black;…"`.
        var result = svg
        let blackPatterns: [(String, String)] = [
            ("fill=\"black\"", "fill=\"white\""),
            ("fill=\"#000\"", "fill=\"#fff\""),
            ("fill=\"#000000\"", "fill=\"#ffffff\""),
            ("fill:\\s*black", "fill:white"),
            ("fill:\\s*#000(?![0-9a-fA-F])", "fill:#fff"),
            ("fill:\\s*#000000\\b", "fill:#ffffff"),
        ]
        for (pattern, replacement) in blackPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    var body: some View {
        // When we have the source SVG, render via SwiftDraw — same engine the
        // template generator uses, so the thumbnail can't drift from the
        // exported template or font geometry.
        if let svg = sourceSVG, !svg.isEmpty, let parsed = SwiftDraw.SVG(xml: recoloredSVG(svg)) {
            SwiftDraw.SVGView(svg: parsed)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Canvas { context, canvasSize in
                renderSinglePath(into: &context, canvasSize: canvasSize)
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: - Legacy single-path renderer (used when sourceSVG isn't available)

    private func renderSinglePath(into context: inout GraphicsContext, canvasSize: CGSize) {
        let commands = SVGParser.parsePathData(pathData)
        let bbox = SVGParser.boundingBox(of: commands)
        guard bbox.width > 0, bbox.height > 0 else { return }

        let scale = min(canvasSize.width / bbox.width, canvasSize.height / bbox.height) * 0.8
        let offsetX = (canvasSize.width - bbox.width * scale) / 2.0 - bbox.minX * scale
        let offsetY = (canvasSize.height - bbox.height * scale) / 2.0 - bbox.minY * scale

        let path = SVGPathBuilder.buildPath(commands: commands, scale: scale, offsetX: offsetX, offsetY: offsetY)
        context.fill(path, with: .color(.primary), style: FillStyle(eoFill: true))
    }
}

/// Builds a SwiftUI Path from parsed SVG commands, supporting M/L/H/V/C/S/Q/T/A/Z
/// and their relative variants. Required for compound icons exported from Figma.
enum SVGPathBuilder {
    static func buildPath(
        commands: [SVGParser.PathCommand],
        scale: Double,
        offsetX: Double,
        offsetY: Double
    ) -> Path {
        var path = Path()
        var curX = 0.0, curY = 0.0
        var startX = 0.0, startY = 0.0     // subpath start (for Z)
        var lastCtrlX = 0.0, lastCtrlY = 0.0
        var lastCtrlCmd: Character = " "    // last bezier command, for S/T reflection

        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        for cmd in commands {
            let p = cmd.parameters
            let rel = cmd.isRelative
            switch cmd.type {
            case "M":
                var i = 0
                while i + 1 < p.count {
                    let x = rel ? curX + p[i] : p[i]
                    let y = rel ? curY + p[i+1] : p[i+1]
                    if i == 0 {
                        path.move(to: pt(x, y))
                        startX = x; startY = y
                    } else {
                        path.addLine(to: pt(x, y))
                    }
                    curX = x; curY = y
                    i += 2
                }
                lastCtrlCmd = " "
            case "L":
                var i = 0
                while i + 1 < p.count {
                    let x = rel ? curX + p[i] : p[i]
                    let y = rel ? curY + p[i+1] : p[i+1]
                    path.addLine(to: pt(x, y))
                    curX = x; curY = y
                    i += 2
                }
                lastCtrlCmd = " "
            case "H":
                for v in p {
                    let x = rel ? curX + v : v
                    path.addLine(to: pt(x, curY))
                    curX = x
                }
                lastCtrlCmd = " "
            case "V":
                for v in p {
                    let y = rel ? curY + v : v
                    path.addLine(to: pt(curX, y))
                    curY = y
                }
                lastCtrlCmd = " "
            case "C":
                var i = 0
                while i + 5 < p.count {
                    let c1x = rel ? curX + p[i]   : p[i]
                    let c1y = rel ? curY + p[i+1] : p[i+1]
                    let c2x = rel ? curX + p[i+2] : p[i+2]
                    let c2y = rel ? curY + p[i+3] : p[i+3]
                    let x   = rel ? curX + p[i+4] : p[i+4]
                    let y   = rel ? curY + p[i+5] : p[i+5]
                    path.addCurve(to: pt(x, y), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
                    lastCtrlX = c2x; lastCtrlY = c2y
                    curX = x; curY = y
                    i += 6
                }
                lastCtrlCmd = "C"
            case "S":
                var i = 0
                while i + 3 < p.count {
                    let c1x = (lastCtrlCmd == "C" || lastCtrlCmd == "S") ? (2 * curX - lastCtrlX) : curX
                    let c1y = (lastCtrlCmd == "C" || lastCtrlCmd == "S") ? (2 * curY - lastCtrlY) : curY
                    let c2x = rel ? curX + p[i]   : p[i]
                    let c2y = rel ? curY + p[i+1] : p[i+1]
                    let x   = rel ? curX + p[i+2] : p[i+2]
                    let y   = rel ? curY + p[i+3] : p[i+3]
                    path.addCurve(to: pt(x, y), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
                    lastCtrlX = c2x; lastCtrlY = c2y
                    curX = x; curY = y
                    i += 4
                }
                lastCtrlCmd = "S"
            case "Q":
                var i = 0
                while i + 3 < p.count {
                    let c1x = rel ? curX + p[i]   : p[i]
                    let c1y = rel ? curY + p[i+1] : p[i+1]
                    let x   = rel ? curX + p[i+2] : p[i+2]
                    let y   = rel ? curY + p[i+3] : p[i+3]
                    path.addQuadCurve(to: pt(x, y), control: pt(c1x, c1y))
                    lastCtrlX = c1x; lastCtrlY = c1y
                    curX = x; curY = y
                    i += 4
                }
                lastCtrlCmd = "Q"
            case "T":
                var i = 0
                while i + 1 < p.count {
                    let c1x = (lastCtrlCmd == "Q" || lastCtrlCmd == "T") ? (2 * curX - lastCtrlX) : curX
                    let c1y = (lastCtrlCmd == "Q" || lastCtrlCmd == "T") ? (2 * curY - lastCtrlY) : curY
                    let x   = rel ? curX + p[i]   : p[i]
                    let y   = rel ? curY + p[i+1] : p[i+1]
                    path.addQuadCurve(to: pt(x, y), control: pt(c1x, c1y))
                    lastCtrlX = c1x; lastCtrlY = c1y
                    curX = x; curY = y
                    i += 2
                }
                lastCtrlCmd = "T"
            case "A":
                // SVG arc → approximate with cubic beziers
                var i = 0
                while i + 6 < p.count {
                    let rx = abs(p[i])
                    let ry = abs(p[i+1])
                    let xAxisRot = p[i+2] * .pi / 180.0
                    let largeArc = p[i+3] != 0
                    let sweep = p[i+4] != 0
                    let endX = rel ? curX + p[i+5] : p[i+5]
                    let endY = rel ? curY + p[i+6] : p[i+6]
                    appendArc(to: &path, from: (curX, curY), to: (endX, endY),
                              rx: rx, ry: ry, xAxisRot: xAxisRot,
                              largeArc: largeArc, sweep: sweep,
                              transform: pt)
                    curX = endX; curY = endY
                    i += 7
                }
                lastCtrlCmd = " "
            case "Z":
                path.closeSubpath()
                curX = startX; curY = startY
                lastCtrlCmd = " "
            default:
                break
            }
        }
        return path
    }

    /// Convert an SVG elliptical arc to cubic Bezier segments and append to path.
    /// Algorithm from the SVG 1.1 implementation notes (Appendix F.6).
    private static func appendArc(to path: inout Path,
                                  from: (Double, Double),
                                  to: (Double, Double),
                                  rx rxIn: Double, ry ryIn: Double,
                                  xAxisRot phi: Double,
                                  largeArc: Bool, sweep: Bool,
                                  transform: (Double, Double) -> CGPoint) {
        let (x1, y1) = from
        let (x2, y2) = to
        if rxIn == 0 || ryIn == 0 {
            path.addLine(to: transform(x2, y2))
            return
        }
        var rx = rxIn, ry = ryIn
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx = (x1 - x2) / 2.0, dy = (y1 - y2) / 2.0
        let x1p =  cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
            lambda = 1
        }
        let sign: Double = (largeArc == sweep) ? -1 : 1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = sign * sqrt(max(0, num / den))
        let cxp =  coef * (rx * y1p) / ry
        let cyp = -coef * (ry * x1p) / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2.0
        let cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2.0

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let d = sqrt((ux*ux + uy*uy) * (vx*vx + vy*vy))
            let c = max(-1.0, min(1.0, (ux*vx + uy*vy) / d))
            let s: Double = (ux*vy - uy*vx >= 0) ? 1 : -1
            return s * acos(c)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        // Split into segments of at most 90° for accurate cubic approximation
        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / Double(segments)
        let t = (4.0 / 3.0) * tan(delta / 4.0)

        var theta = theta1
        for _ in 0..<segments {
            let cosT1 = cos(theta), sinT1 = sin(theta)
            let cosT2 = cos(theta + delta), sinT2 = sin(theta + delta)

            // Point and tangent on unit circle, then scaled/rotated/translated
            let p1x = cosT1 - t * sinT1
            let p1y = sinT1 + t * cosT1
            let p2x = cosT2 + t * sinT2
            let p2y = sinT2 - t * cosT2

            func ellipse(_ ex: Double, _ ey: Double) -> (Double, Double) {
                let xR = rx * ex, yR = ry * ey
                return (cosPhi * xR - sinPhi * yR + cx, sinPhi * xR + cosPhi * yR + cy)
            }
            let (c1x, c1y) = ellipse(p1x, p1y)
            let (c2x, c2y) = ellipse(p2x, p2y)
            let (ex, ey) = ellipse(cosT2, sinT2)
            path.addCurve(to: transform(ex, ey), control1: transform(c1x, c1y), control2: transform(c2x, c2y))
            theta += delta
        }
    }
}
