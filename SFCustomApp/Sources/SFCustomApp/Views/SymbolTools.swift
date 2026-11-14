import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SFCustomEngine

// MARK: - Compatibility pill

/// Green / orange / red status of the three anchors, with a popover that
/// explains each issue in designer language.
struct CompatibilityPill: View {
    var report: CompatibilityReport
    var warnings: [String] = []

    @State private var isShowingDetails = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(report.summary)
                if !warnings.isEmpty && report.status == .ok {
                    Image(systemName: "info.circle")
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Can SF Symbols interpolate Ultralight ↔ Regular ↔ Black?")
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            details.padding(16).frame(width: 360)
        }
    }

    private var symbol: String {
        switch report.status {
        case .ok:      return "checkmark.seal.fill"
        case .fixable: return "wrench.and.screwdriver.fill"
        case .broken:  return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch report.status {
        case .ok:      return .green
        case .fixable: return .orange
        case .broken:  return .red
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline).font(.headline)
            Text("SF Symbols draws Thin, Light, Medium… by blending your Ultralight, Regular and Black. That only works when all three have the same parts, points, order and start points.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.issues.isEmpty {
                Divider()
                ForEach(report.issues) { issue in
                    Label {
                        Text(issue.message).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: issue.isAutoFixable ? "wrench.and.screwdriver" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isAutoFixable ? Color.orange : Color.red)
                    }
                    .font(.callout)
                }
            }
            if !warnings.isEmpty {
                Divider()
                ForEach(warnings, id: \.self) { w in
                    Label {
                        Text(w).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var headline: String {
        switch report.status {
        case .ok:      return "All weights interpolate cleanly"
        case .fixable: return "Fixable differences between weights"
        case .broken:  return "These weights won’t interpolate"
        }
    }
}

// MARK: - Margins editor

/// Per-anchor side bearings (the talk recommends 8–10 units).
struct MarginsEditor: View {
    var icon: Icon
    @EnvironmentObject var library: IconLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Margins").font(.headline)
            Text("Space between the glyph and its left / right guide, in template units. Apple uses ≈ 9.77; 8–10 works well.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text("Left").font(.caption.weight(.medium))
                    Text("Right").font(.caption.weight(.medium))
                }
                ForEach(AnchorWeight.allCases, id: \.self) { w in
                    GridRow {
                        Text(w.displayName).frame(width: 80, alignment: .leading)
                        field(w, \.left)
                        field(w, \.right)
                    }
                }
            }
            HStack {
                Button("Apply Regular to all") { copyRegularToAll() }
                Spacer()
                Button("Reset") { reset() }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func current(_ w: AnchorWeight) -> AnchorMargins {
        SymbolSettings.margins(for: icon)[w] ?? .standard
    }

    private func field(_ w: AnchorWeight, _ side: WritableKeyPath<AnchorMargins, Double>) -> some View {
        let binding = Binding<Double>(
            get: { current(w)[keyPath: side] },
            set: { newValue in
                var m = current(w)
                m[keyPath: side] = max(0, newValue)
                var updated = icon
                var all = updated.margins ?? [:]
                all[w.rawValue] = m
                updated.margins = all
                library.update(updated)
            })
        return HStack(spacing: 4) {
            TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
            Stepper("", value: binding, in: 0...60, step: 0.5).labelsHidden()
        }
    }

    private func copyRegularToAll() {
        let r = current(.regular)
        var updated = icon
        updated.margins = Dictionary(uniqueKeysWithValues: AnchorWeight.allCases.map { ($0.rawValue, r) })
        library.update(updated)
    }

    private func reset() {
        var updated = icon
        updated.margins = nil
        library.update(updated)
    }
}

// MARK: - Onion skin + weight scrubber

/// The talk's onion-skin check, automated: the three anchors overlaid at
/// 50 % with start-point dots and part numbers, plus a slider that blends
/// through every in-between weight like Xcode will.
struct OnionSkinPanel: View {
    var template: SymbolTemplate
    var tint: Color
    var background: Color

    @State private var position: Double = 1
    @State private var showMarkers = true

    private struct WeightStop { var name: String; var position: Double }
    private static let weights: [WeightStop] = SymbolInterpolator.weightPositions.map {
        WeightStop(name: $0.name, position: $0.position)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Onion skin & in-between weights").font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Start points & order", isOn: $showMarkers)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    SVGWebView(svg: SymbolPreviewRenderer.onionSkin(template, showMarkers: showMarkers).svg,
                               background: .clear, padding: 8)
                        .frame(width: 220, height: 220)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        .allowsHitTesting(false)
                    HStack(spacing: 10) {
                        legend("Ultralight", Color(red: 0.12, green: 0.53, blue: 0.90))
                        legend("Regular", .gray)
                        legend("Black", Color(red: 0.90, green: 0.22, blue: 0.21))
                    }
                    .font(.caption2)
                }
                VStack(spacing: 8) {
                    Group {
                        if let p = SymbolPreviewRenderer.interpolatedPreview(at: position, in: template) {
                            SVGWebView(svg: p.svg, background: .clear, padding: 12, tint: tint)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                                Text("Can’t blend: the weights aren’t compatible.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190)
                    .background(RoundedRectangle(cornerRadius: 8).fill(background))
                    .allowsHitTesting(false)

                    Slider(value: $position, in: 0...2)
                        .disabled(template.compatibility.status == .broken)
                    HStack {
                        ForEach(0..<Self.weights.count, id: \.self) { i in
                            Button(Self.weights[i].name) { position = Self.weights[i].position }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(abs(position - Self.weights[i].position) < 0.05 ? Color.accentColor : Color.secondary)
                            if i < Self.weights.count - 1 { Spacer(minLength: 0) }
                        }
                    }
                }
            }
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Developer handoff

/// "Work together with your designer!" — the snippet a developer needs.
struct HandoffCard: View {
    var name: String
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Developer handoff").font(.subheadline.weight(.semibold))
                Spacer()
                if let copied {
                    Text("Copied \(copied)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(HandoffSnippet.instructions(name: name))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(HandoffSnippet.swiftUI(name: name))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Button("Copy SwiftUI") { copy(HandoffSnippet.swiftUI(name: name), label: "SwiftUI") }
                Button("Copy UIKit") { copy(HandoffSnippet.uiKit(name: name), label: "UIKit") }
            }
            .controlSize(.small)
        }
    }

    private func copy(_ s: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        copied = label
    }
}

// MARK: - Check an existing template file

/// Lint any SF Symbol template (e.g. drawn by hand in Illustrator/Figma)
/// for the talk's interpolation pitfalls, and auto-fix what can be fixed.
struct TemplateCheckView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var fileURL: URL?
    @State private var source: String?
    @State private var report: CompatibilityReport?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check Template").font(.title2.weight(.semibold))
                    Text("Finds different point counts, start points, part order and line/curve mismatches between Ultralight, Regular and Black.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            HStack {
                Button {
                    isImporting = true
                } label: {
                    Label("Choose Template SVG…", systemImage: "doc.badge.gearshape")
                }
                if let fileURL {
                    Text(fileURL.lastPathComponent).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
            if let report {
                CompatibilityPill(report: report)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if report.issues.isEmpty {
                            Text("No problems found. SF Symbols can interpolate all weights.")
                        }
                        ForEach(report.issues) { issue in
                            Label(issue.message, systemImage: issue.isAutoFixable ? "wrench.and.screwdriver" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.isAutoFixable ? Color.orange : Color.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                if report.status == .fixable {
                    Button {
                        saveFixed()
                    } label: {
                        Label("Fix & Save As…", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                } else if report.status == .broken {
                    Text("Different point counts can’t be fixed automatically: remove the extra points (or add the missing ones) in your design tool, then check again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [UTType(filenameExtension: "svg") ?? .image]) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    private func load(_ url: URL) {
        let needs = url.startAccessingSecurityScopedResource()
        defer { if needs { url.stopAccessingSecurityScopedResource() } }
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            message = "Couldn’t read \(url.lastPathComponent)."
            return
        }
        fileURL = url
        source = s
        report = CompatibilityChecker.check(templateSVG: s)
        message = nil
    }

    private func saveFixed() {
        guard let s = source, let fixed = CompatibilityFixer.fix(templateSVG: s) else {
            message = "Nothing to fix."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "template") + "-fixed.svg"
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try fixed.write(to: url, atomically: true, encoding: .utf8)
            let after = CompatibilityChecker.check(templateSVG: fixed)
            message = "Saved \(url.lastPathComponent) — \(after.summary)."
        } catch {
            message = error.localizedDescription
        }
    }
}
