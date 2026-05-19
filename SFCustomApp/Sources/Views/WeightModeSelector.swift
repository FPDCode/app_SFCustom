import SwiftUI

/// Lets the user choose how to provide weight variants:
/// - Uniform: Same icon across all weights
/// - Single + Generate: Provide one, auto-generate the rest
/// - Full Control: Provide all 3 manually
struct WeightModeSelector: View {
    @Binding var weightMode: WeightMode
    @Binding var masters: WeightMasters
    let onGenerate: () -> Void
    let onExportTemplate: () -> Void

    @State private var selectedSourceWeight: WeightMasters.SourceWeight = .regular

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weight Mode")
                .font(.headline)

            // Mode picker
            Picker("Mode", selection: modeBinding) {
                Label("Uniform", systemImage: "equal.circle")
                    .tag(ModeTag.uniform)
                Label("Single + Generate", systemImage: "wand.and.stars")
                    .tag(ModeTag.singleGenerate)
                Label("Full Control", systemImage: "slider.horizontal.3")
                    .tag(ModeTag.fullControl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Mode description
            modeDescription

            // Mode-specific controls
            switch weightMode {
            case .uniform:
                uniformControls
            case .singleGenerate:
                singleGenerateControls
            case .fullControl:
                fullControlControls
            }

            // Always-visible Export Template button — uses the currently
            // selected Weight Mode (Uniform / Single+Generate / Full Control)
            // to produce the SF Symbol template SVG.
            Divider().padding(.vertical, 4)
            Button {
                onExportTemplate()
            } label: {
                Label("Export Template (\(modeLabel))", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var modeLabel: String {
        switch weightMode {
        case .uniform: return "Uniform"
        case .singleGenerate(let src):
            switch src {
            case .ultralight: return "Single+Gen · Ultralight"
            case .regular:    return "Single+Gen · Regular"
            case .black:      return "Single+Gen · Black"
            }
        case .fullControl: return "Full Control"
        }
    }

    // MARK: - Mode Tag (for segmented picker)

    private enum ModeTag: Int {
        case uniform, singleGenerate, fullControl
    }

    private var modeBinding: Binding<ModeTag> {
        Binding(
            get: {
                switch weightMode {
                case .uniform: return .uniform
                case .singleGenerate: return .singleGenerate
                case .fullControl: return .fullControl
                }
            },
            set: { tag in
                switch tag {
                case .uniform:
                    weightMode = .uniform
                    masters.ultralight = masters.regular
                    masters.black = masters.regular
                case .singleGenerate:
                    weightMode = .singleGenerate(selectedSourceWeight)
                case .fullControl:
                    weightMode = .fullControl
                }
            }
        )
    }

    // MARK: - Mode Descriptions

    @ViewBuilder
    private var modeDescription: some View {
        switch weightMode {
        case .uniform:
            Label("The same icon path is used for all 3 master weights. Simplest option — the icon looks identical at every weight.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        case .singleGenerate:
            Label("Provide one icon and specify its weight. SF Custom generates the other two masters using Apple's measured weight growth curve.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        case .fullControl:
            Label("Provide separate SVG paths for Ultralight, Regular, and Black. Maximum control over how the icon appears at each weight.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Uniform Controls

    private var uniformControls: some View {
        HStack {
            Text("All weights use the Regular path")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Single + Generate Controls

    private var singleGenerateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source weight:")
                    .font(.subheadline)

                Picker("Source Weight", selection: $selectedSourceWeight) {
                    Text("Ultralight").tag(WeightMasters.SourceWeight.ultralight)
                    Text("Regular").tag(WeightMasters.SourceWeight.regular)
                    Text("Black").tag(WeightMasters.SourceWeight.black)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .onChange(of: selectedSourceWeight) { _, newValue in
                    weightMode = .singleGenerate(newValue)
                }
            }

            Button {
                onGenerate()
            } label: {
                Label("Generate Weight Variants", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)

            // Show growth factors
            growthFactorInfo
        }
    }

    private var growthFactorInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apple Weight Growth Curve:")
                .font(.caption.bold())
            HStack(spacing: 16) {
                growthChip("Ultralight", factor: 1.0)
                growthChip("Regular", factor: 1.016)
                growthChip("Black", factor: 1.284)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(6)
    }

    private func growthChip(_ label: String, factor: Double) -> some View {
        VStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f%%", (factor - 1.0) * 100))
                .font(.system(.caption, design: .monospaced))
        }
    }

    // MARK: - Full Control Controls

    private var fullControlControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            pathField("Ultralight Path", path: $masters.ultralight)
            pathField("Regular Path", path: $masters.regular)
            pathField("Black Path", path: $masters.black)
        }
    }

    private func pathField(_ label: String, path: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
            TextEditor(text: path)
                .font(.system(.caption2, design: .monospaced))
                .frame(height: 40)
                .border(.quaternary)
        }
    }
}
