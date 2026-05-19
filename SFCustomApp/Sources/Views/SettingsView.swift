import SwiftUI

/// App settings: server port, font name, export preferences
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("serverPort") private var serverPort: Int = 8787
    @AppStorage("fontName") private var fontName: String = "SFCustomIcons"
    @AppStorage("autoStartServer") private var autoStartServer: Bool = false
    @AppStorage("autoInstallFont") private var autoInstallFont: Bool = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            serverSettings
                .tabItem {
                    Label("Server", systemImage: "network")
                }

            fontSettings
                .tabItem {
                    Label("Font", systemImage: "textformat")
                }
        }
        .frame(width: 450, height: 300)
        .padding()
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("Export") {
                Toggle("Auto-install font after export", isOn: $autoInstallFont)
            }

            Section("Library") {
                HStack {
                    Text("Storage location")
                    Spacer()
                    Text(IconLibrary.storageURL.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(
                        IconLibrary.storageURL.path,
                        inFileViewerRootedAtPath: IconLibrary.storageURL.deletingLastPathComponent().path
                    )
                }
            }
        }
        .padding()
    }

    // MARK: - Server

    private var serverSettings: some View {
        Form {
            Section("Local HTTP Server") {
                HStack {
                    Text("Port")
                    TextField("Port", value: $serverPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Toggle("Start server on app launch", isOn: $autoStartServer)

                HStack {
                    Text("Status:")
                    Text(appState.isServerRunning ? "Running" : "Stopped")
                        .foregroundColor(appState.isServerRunning ? .green : .secondary)
                }

                if appState.isServerRunning {
                    HStack {
                        Text("URL:")
                        Text("http://localhost:\(serverPort)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Figma Plugin") {
                Text("The Figma plugin connects to this server to send icon data. Make sure the port matches the plugin's configuration.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Font

    private var fontSettings: some View {
        Form {
            Section("Font Configuration") {
                HStack {
                    Text("Font Name")
                    TextField("Font Name", text: $fontName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Font installed:")
                    Text(appState.lastExportedFontURL != nil ? "Yes" : "No")
                        .foregroundColor(appState.lastExportedFontURL != nil ? .green : .secondary)
                }
            }

            Section("Unicode Range") {
                HStack {
                    Text("Starting codepoint")
                    Text("U+E000 (Private Use Area)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text("Icons are assigned sequential codepoints starting from U+E000. The Private Use Area (U+E000–U+F8FF) supports up to 6,400 custom glyphs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
