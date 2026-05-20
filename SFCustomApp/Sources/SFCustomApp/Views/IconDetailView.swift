import SwiftUI
import UniformTypeIdentifiers

struct IconDetailView: View {
    var icon: Icon

    @EnvironmentObject var library: IconLibrary
    @EnvironmentObject var settings: AppSettings

    @State private var variants: [Weight: StrokeSnooper.VariantResult] = [:]
    @State private var isLoadingVariants = false
    @State private var lastError: String?
    @State private var isExporting = false

    private let snooper = StrokeSnooper()

    @State private var copiedHint: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            FigmaUsageStrip(icon: icon, copiedHint: $copiedHint)
            Divider()
            grid
            Divider()
            footer
        }
        .background(Color(nsColor: settings.darkBackground ? .underPageBackgroundColor : .windowBackgroundColor))
        .task(id: icon.id) {
            await regenerate()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            SVGThumbnail(svg: icon.sourceSVG)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            VStack(alignment: .leading, spacing: 4) {
                Text(icon.name).font(.title2.weight(.semibold))
                HStack(spacing: 12) {
                    Label(icon.codepointString, systemImage: "number")
                    Label("9 weights × 3 scales", systemImage: "rectangle.3.group")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            Toggle(isOn: $settings.darkBackground) {
                Image(systemName: settings.darkBackground ? "moon.fill" : "sun.max.fill")
            }
            .toggleStyle(.button)
            .help("Toggle background")

            ExportMenu(icon: icon, isExporting: $isExporting, onError: { lastError = $0 })
        }
        .padding(16)
    }

    // MARK: - Preview Grid

    private var grid: some View {
        ZStack {
            if isLoadingVariants && variants.isEmpty {
                ProgressView("Computing weights…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if variants.isEmpty {
                Text(lastError ?? "Couldn't render this icon.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                        GridRow {
                            cellLabel("").frame(width: 84, height: 32)
                            ForEach(Weight.allCases) { w in
                                cellLabel(w.displayName).frame(height: 32)
                            }
                        }
                        ForEach(Scale.allCases) { s in
                            GridRow {
                                cellLabel(s.displayName).frame(width: 84)
                                ForEach(Weight.allCases) { w in
                                    PreviewCell(
                                        svg: variants[w]?.svgXML ?? icon.sourceSVG,
                                        scale: s,
                                        showGuides: settings.showGuides,
                                        dark: settings.darkBackground
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cellLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle("Show guides", isOn: $settings.showGuides)
                .toggleStyle(.switch)
                .controlSize(.small)

            if let err = lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Delete", role: .destructive) {
                library.delete(icon)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Variant generation

    private func regenerate() async {
        isLoadingVariants = true
        defer { isLoadingVariants = false }
        do {
            variants = try await snooper.generateAllWeights(from: icon.sourceSVG)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            variants = [:]
        }
    }
}

/// One cell in the preview grid: a weight×scale rendering of the icon.
private struct PreviewCell: View {
    var svg: String
    var scale: Scale
    var showGuides: Bool
    var dark: Bool

    var body: some View {
        let size: CGFloat = baseSize * CGFloat(scale.sizeScale)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dark ? Color.black.opacity(0.5) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )

            if showGuides {
                GuideOverlay()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    .padding(8)
            }

            SVGWebView(svg: svg, background: .clear, padding: 8)
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
        .frame(width: 132, height: 132)
        .padding(4)
    }

    private var baseSize: CGFloat { 56 }
}

private struct GuideOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        let baseline = rect.maxY - rect.height * 0.18
        let capline = baseline - rect.height * 0.52
        p.move(to: .init(x: rect.minX, y: baseline))
        p.addLine(to: .init(x: rect.maxX, y: baseline))
        p.move(to: .init(x: rect.minX, y: capline))
        p.addLine(to: .init(x: rect.maxX, y: capline))
        // x-height optional reference at the middle
        p.move(to: .init(x: rect.minX, y: mid))
        p.addLine(to: .init(x: rect.maxX, y: mid))
        return p
    }
}

// MARK: - Export menu

struct ExportMenu: View {
    var icon: Icon
    @Binding var isExporting: Bool
    var onError: (String) -> Void

    var body: some View {
        Menu {
            Button("Save Template SVG…") { Task { await exportTemplate() } }
            Button("Save Source SVG…") { saveSource() }
            Button("Copy Source SVG") { copy(icon.sourceSVG) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(isExporting)
    }

    @MainActor
    private func exportTemplate() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let gen = TemplateGenerator()
            let template = try await gen.generate(for: icon)
            promptSave(filename: "\(icon.name)_template.svg", content: template)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func saveSource() {
        promptSave(filename: "\(icon.name).svg", content: icon.sourceSVG)
    }

    private func promptSave(filename: String, content: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

#if canImport(AppKit)
import AppKit
#endif
