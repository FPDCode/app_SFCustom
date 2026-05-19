import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var server: LocalServer

    @State private var diagnosis: FontCompiler.Diagnosis = .noPython
    private let compiler = FontCompiler()

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            bridgeTab.tabItem { Label("Plugin Bridge", systemImage: "network") }
            fontTab.tabItem { Label("Font", systemImage: "textformat") }
        }
        .padding(20)
        .frame(width: 460, height: 320)
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
