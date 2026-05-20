import SwiftUI
import AppKit

/// Side-by-side test bench for **exported templates** vs SF Pro symbols.
///
/// What the user sees here is what a developer using the exported
/// `template.svg` will get in Xcode / SF Symbols app. Each anchor weight
/// (Ultralight, Regular, Black) is rendered straight from the template
/// generator and matched against the chosen SF Pro symbol at the same
/// weight + point size, scaled so cap heights line up — so visual
/// differences are real differences, not artefacts of mismatched
/// rendering.
struct CompareView: View {
    @EnvironmentObject var library: IconLibrary
    @EnvironmentObject var settings: AppSettings

    /// Pre-select an icon when opening the sheet from the sidebar.
    var initialIcon: Icon?

    @State private var selectedIconID: Icon.ID?
    @State private var sfSymbolName: String = "location.fill"
    @State private var pointSize: Double = 17
    @State private var previews: [TemplateGenerator.AnchorPreview] = []
    @State private var isPreviewing = false
    @State private var status: Status?
    @State private var lastError: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let exporter = Exporter()
    private let generator = TemplateGenerator()

    /// High-contrast colour for monochrome icons: white on dark, black on light.
    private var iconTint: Color { colorScheme == .dark ? .white : .black }

    enum Status: Identifiable {
        case exported(URL)
        case exportFailed(String)
        var id: String {
            switch self {
            case .exported(let u):       return "ok:\(u.path)"
            case .exportFailed(let msg): return "err:\(msg)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pickerStrip
            Divider()
            sizeControl
            Divider()
            ScrollView {
                content.padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 700)
        .onAppear {
            if selectedIconID == nil { selectedIconID = initialIcon?.id ?? library.icons.first?.id }
        }
        .task(id: selectedIconID) {
            await regeneratePreviews()
        }
        .alert(item: $status) { status in
            switch status {
            case .exported(let url):
                return Alert(
                    title: Text("Exported"),
                    message: Text(url.path),
                    primaryButton: .default(Text("Reveal in Finder")) { exporter.reveal(url) },
                    secondaryButton: .cancel(Text("OK"))
                )
            case .exportFailed(let msg):
                return Alert(title: Text("Export failed"), message: Text(msg), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compare Export").font(.title2.weight(.semibold))
                Text("Renders the exported template's slots next to SF Pro symbols at matched cap-heights — what a developer will see when they ship your icon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - Picker strip

    private var pickerStrip: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Your icon (from exported template)", systemImage: "scribble.variable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedIconID) {
                    Text("—").tag(Icon.ID?.none)
                    ForEach(library.icons.sorted { $0.name < $1.name }) { icon in
                        Text(icon.name).tag(Icon.ID?(icon.id))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 220)
            }

            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Label("SF Pro symbol", systemImage: "apple.logo")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("e.g. location.fill", text: $sfSymbolName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                    if !isValidSymbol(sfSymbolName) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("This SF Symbol name doesn't exist on this system.")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Size control

    private var sizeControl: some View {
        HStack(spacing: 12) {
            Text("Point size")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Slider(value: $pointSize, in: 10...60, step: 1)
                .frame(maxWidth: 320)
            Text("\(Int(pointSize)) pt")
                .font(.system(.callout, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
            Spacer()
            ForEach([13, 17, 22, 34], id: \.self) { preset in
                Button("\(preset)pt") { pointSize = Double(preset) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let err = lastError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if isPreviewing && previews.isEmpty {
            ProgressView("Rendering template…")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if previews.isEmpty {
            Text("Pick an icon to start.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if variantsAreIdentical {
                    identicalVariantsWarning
                }
                sectionHeader("Anchor weights — your export vs SF Pro")
                ForEach(previews, id: \.weight) { preview in
                    weightRow(preview: preview)
                }
                Divider()
                inlineRow
            }
        }
    }

    /// True when all anchor variants produced byte-identical output —
    /// which means stroke-scaling didn't change anything (filled-only
    /// source), so all three weights will look the same.
    private var variantsAreIdentical: Bool {
        let hashes = Set(previews.map(\.innerXMLHash))
        return hashes.count == 1 && previews.count > 1
    }

    private var identicalVariantsWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This icon has no strokes, so all three anchor weights are identical.")
                    .font(.callout.weight(.medium))
                Text("SF Pro symbols vary weight by drawing thicker strokes (or wider fills). Either redraw with explicit strokes, or provide separate Ultralight / Regular / Black versions and import each one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5)
                )
        )
    }

    private func weightRow(preview: TemplateGenerator.AnchorPreview) -> some View {
        let sfWeight = mapToSFProWeight(preview.weight)
        // Cell height grows with point size so larger sizes get more room.
        let cellHeight = CGFloat(pointSize) * 1.8
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.weight.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("vs SF Pro \(sfWeightLabel(sfWeight))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 130, alignment: .leading)

            comparisonCell(
                cellHeight: cellHeight,
                left: templateGlyphView(preview: preview),
                right: sfProGlyphView(weight: sfWeight)
            )
        }
    }

    private var inlineRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Inline with text — does it sit right?")
            if let preview = previews.first(where: { $0.weight == .regular }) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Find the").font(.system(size: CGFloat(pointSize)))
                    templateGlyphInline(preview: preview)
                    Text("on the map next to").font(.system(size: CGFloat(pointSize)))
                    sfProGlyphInline()
                    Text("after sunset.").font(.system(size: CGFloat(pointSize)))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.darkBackground ? Color.black.opacity(0.5) : Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    private func comparisonCell<L: View, R: View>(cellHeight: CGFloat, left: L, right: R) -> some View {
        HStack(spacing: 24) {
            VStack(spacing: 6) {
                ZStack { left }
                    .frame(height: cellHeight)
                Text("Your icon").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                ZStack { right }
                    .frame(height: cellHeight)
                Text("SF Pro").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(settings.darkBackground ? Color.black.opacity(0.5) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    /// Render the template slot SVG at a CSS height where the cap-height
    /// inside the SVG equals SF Pro's cap-height at the target point size.
    /// This makes the optical comparison fair.
    private func templateGlyphView(preview: TemplateGenerator.AnchorPreview) -> some View {
        let pt = CGFloat(pointSize)
        let renderedHeightPt = pt * (preview.viewBoxHeight / preview.capHeight) * Self.sfProCapToPtRatio
        let renderedWidthPt  = renderedHeightPt * (preview.viewBoxWidth / preview.viewBoxHeight)
        return SVGWebView(svg: preview.svg, background: .clear, padding: 0, tint: iconTint)
            .frame(width: renderedWidthPt, height: renderedHeightPt)
            .allowsHitTesting(false)
    }

    /// Inline variant: aligns with the surrounding text baseline.
    private func templateGlyphInline(preview: TemplateGenerator.AnchorPreview) -> some View {
        let pt = CGFloat(pointSize)
        let renderedHeightPt = pt * (preview.viewBoxHeight / preview.capHeight) * Self.sfProCapToPtRatio
        let renderedWidthPt  = renderedHeightPt * (preview.viewBoxWidth / preview.viewBoxHeight)
        // The icon sits with baseline at viewBox y=0 (which is ~91% down
        // the SVG vertically because of the 10% overshoot we added).
        let baselineOffset = renderedHeightPt * CGFloat(preview.capHeight / preview.viewBoxHeight)
        return SVGWebView(svg: preview.svg, background: .clear, padding: 0, tint: iconTint)
            .frame(width: renderedWidthPt, height: renderedHeightPt)
            .alignmentGuide(.firstTextBaseline) { _ in baselineOffset }
            .allowsHitTesting(false)
    }

    private func sfProGlyphView(weight: Font.Weight) -> some View {
        Group {
            if isValidSymbol(sfSymbolName) {
                Image(systemName: sfSymbolName)
                    .font(.system(size: CGFloat(pointSize), weight: weight))
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: CGFloat(pointSize), weight: weight))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sfProGlyphInline() -> some View {
        Group {
            if isValidSymbol(sfSymbolName) {
                Image(systemName: sfSymbolName)
                    .font(.system(size: CGFloat(pointSize)))
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: CGFloat(pointSize)))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                exporter.reveal()
            } label: {
                Label("Open SFCustomExports", systemImage: "folder")
            }
            .controlSize(.regular)

            if let icon = selectedIcon {
                Text("Will export to ~/SFCustomExports/\(icon.name)/")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await exportCurrent() }
            } label: {
                Label("Export Template", systemImage: "square.and.arrow.down.on.square")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(selectedIcon == nil)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var selectedIcon: Icon? {
        guard let id = selectedIconID else { return nil }
        return library.icons.first { $0.id == id }
    }

    /// Calibration: visual height of an SF Pro symbol at 1pt nominal
    /// size. SF Pro symbols are drawn to fill roughly the em box, so
    /// 0.95 puts our template's icon at near-parity visual size.
    private static let sfProCapToPtRatio: CGFloat = 0.95

    private func mapToSFProWeight(_ w: Weight) -> Font.Weight {
        switch w {
        case .ultralight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        }
    }

    private func sfWeightLabel(_ w: Font.Weight) -> String {
        switch w {
        case .ultraLight: return "Ultralight"
        case .thin:       return "Thin"
        case .light:      return "Light"
        case .regular:    return "Regular"
        case .medium:     return "Medium"
        case .semibold:   return "Semibold"
        case .bold:       return "Bold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        default:          return ""
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
    }

    private func isValidSymbol(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
    }

    // MARK: - Regenerate / Export

    @MainActor
    private func regeneratePreviews() async {
        guard let icon = selectedIcon else {
            previews = []
            return
        }
        isPreviewing = true
        defer { isPreviewing = false }
        do {
            previews = try await generator.generateAnchorPreviews(for: icon)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            previews = []
        }
    }

    @MainActor
    private func exportCurrent() async {
        guard let icon = selectedIcon else { return }
        do {
            let result = try await exporter.export(icon: icon)
            status = .exported(result.templateURL)
        } catch {
            status = .exportFailed(error.localizedDescription)
        }
    }
}

