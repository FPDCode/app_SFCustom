import SwiftUI
import SFCustomEngine

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var server: LocalServer

    @State private var diagnosis: FontCompiler.Diagnosis = .noPython
    private let compiler = FontCompiler()

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            symbolsTab.tabItem { Label("Symbols", systemImage: "lineweight") }
            bridgeTab.tabItem { Label("Plugin Bridge", systemImage: "network") }
            fontTab.tabItem { Label("Font", systemImage: "textformat") }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear { diagnosis = compiler.diagnose() }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Toggle("Show baseline & cap-height guides in preview", isOn: $settings.showGuides)
            Toggle("Dark preview background", isOn: $settings.darkBackground)
        }
        .padding(.top, 8)
    }

    private var symbolsTab: some View {
        Form {
            Picker("Stroke ladder", selection: $settings.ladderPreset) {
                ForEach(StrokeLadder.Preset.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p.rawValue)
                }
            }
            if settings.ladderPreset == StrokeLadder.Preset.custom.rawValue {
                HStack {
                    numberField("Ultralight", $settings.customUltralight)
                    numberField("Regular", $settings.customRegular)
                    numberField("Black", $settings.customBlack)
                }
            }
            Text("Stroke widths in template units (cap height 70). The talk recipe 2 · 7 · 13 is closest to Apple’s own symbols.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Normalise Regular stroke to the ladder", isOn: $settings.normalizeRegular)
            Text("On: every icon gets the same Regular stroke, whatever stroke width you drew with. Off: your stroke is kept and the ladder is used as ratios.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Default margin")
                TextField("", value: $settings.defaultMargin, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70)
                Text("units (8–10 recommended)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func numberField(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption)
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                .frame(width: 70)
        }
    }

    private var bridgeTab: some View {
        Form {
            Toggle("Start plugin bridge automatically", isOn: $settings.startServerAutomatically)
            HStack {
                Text("Port")
                TextField("", value: $settings.serverPort, format: .number)
                    .frame(width: 80)
                Spacer()
                Button(server.isRunning ? "Restart" : "Start") {
                    server.stop()
                    server.start(on: UInt16(settings.serverPort))
                }
            }
            if server.isRunning {
                Label("Listening on 127.0.0.1:\(server.port)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let err = server.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 8)
    }

    private var fontTab: some View {
        Form {
            HStack {
                Text("Family Name")
                TextField("", text: $settings.familyName)
            }
            HStack {
                Text("Style Name")
                TextField("", text: $settings.styleName)
            }
            Toggle("Variable font (one file, Ultralight → Black)", isOn: $settings.variableFont)
            Text("Builds a single font with a weight axis from the three compatible anchors.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            diagnosticsSection
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        switch diagnosis {
        case .ready(let path):
            Label("Ready (\(path))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .fontToolsMissing(let path):
            VStack(alignment: .leading, spacing: 8) {
                Label("Found Python at \(path) but `fonttools` isn't installed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Run this in Terminal:")
                    .font(.caption)
                Text("pip3 install --user fonttools")
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
            }
        case .noPython:
            VStack(alignment: .leading, spacing: 8) {
                Label("Python 3 not found.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Install it from python.org or with: `brew install python`")
                    .font(.caption)
            }
        }
        Button("Re-check") { diagnosis = compiler.diagnose() }
            .controlSize(.small)
    }
}

#if canImport(AppKit)
import AppKit
#endif
