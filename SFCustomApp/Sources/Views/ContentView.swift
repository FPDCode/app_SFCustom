import SwiftUI

/// Main app window — SF Symbols-style layout:
/// Top: Icon grid browser (full width)
/// Bottom/side: Inspector panel when an icon is selected (editor + preview)
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInspector = false

    var body: some View {
        HSplitView {
            // Primary: Grid browser (always visible, like SF Symbols app)
            IconGridView(selectedIcon: $appState.selectedIcon)
                .frame(minWidth: 500)

            // Inspector: Editor + Preview (slides in when icon selected)
            if let icon = appState.selectedIcon {
                inspectorPanel(for: icon)
                    .frame(minWidth: 340, idealWidth: 380, maxWidth: 450)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .navigationTitle("SF Custom")
        .onChange(of: appState.selectedIcon) { _, newValue in
            showInspector = newValue != nil
        }
    }

    // MARK: - Inspector Panel

    private func inspectorPanel(for icon: Icon) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(icon.name)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text(icon.codepointHex)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            if icon.version > 1 {
                                Text("v\(icon.version)")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.1))
                                    .cornerRadius(3)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        appState.selectedIcon = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                Divider()

                // Large preview
                IconThumbnail(icon: icon, size: 120)
                    .frame(width: 160, height: 160)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(.quaternary)
                    )
                    .padding(16)

                Divider()

                // Editor
                IconEditorView(icon: binding(for: icon))
                    .padding(.bottom, 8)

                Divider()

                // Weight preview grid
                PreviewGrid(icon: icon)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            createNewIcon()
        } label: {
            Label("New Icon", systemImage: "plus")
        }

        Divider()

        Button {
            exportTemplate()
        } label: {
            Label("Export Template", systemImage: "square.and.arrow.up")
        }
        .disabled(appState.selectedIcon == nil)

        Button {
            exportFont()
        } label: {
            Label("Export Font", systemImage: "textformat")
        }
        .disabled(appState.library.icons.isEmpty)

        Button {
            installFont()
        } label: {
            Label("Install Font", systemImage: "arrow.down.to.line")
        }
        .disabled(appState.lastExportedFontURL == nil)

        Divider()

        Button {
            toggleServer()
        } label: {
            Label(
                appState.isServerRunning ? "Stop Server" : "Start Server",
                systemImage: appState.isServerRunning ? "bolt.slash" : "bolt"
            )
        }

        // Status
        Text(appState.statusMessage)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(minWidth: 150, alignment: .trailing)
    }

    // MARK: - Actions

    private func createNewIcon() {
        let icon = Icon(name: "untitled", svgPath: "M0 0")
        appState.addIcon(icon)
    }

    private func exportTemplate() {
        guard let icon = appState.selectedIcon else { return }
        do {
            let data = try appState.exportTemplate(for: icon)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.svg]
            panel.nameFieldStringValue = "\(icon.name)_dynamic.svg"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            appState.statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportFont() {
        do {
            let _ = try appState.exportFont()
        } catch {
            appState.statusMessage = "Font export failed: \(error.localizedDescription)"
        }
    }

    private func installFont() {
        do {
            try appState.installFont()
        } catch {
            appState.statusMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    private func toggleServer() {
        if appState.isServerRunning {
            appState.stopServer()
        } else {
            appState.startServer()
        }
    }

    // MARK: - Helpers

    private func binding(for icon: Icon) -> Binding<Icon> {
        Binding(
            get: {
                appState.library.icons.first(where: { $0.id == icon.id }) ?? icon
            },
            set: { newValue in
                if let index = appState.library.icons.firstIndex(where: { $0.id == icon.id }) {
                    appState.library.icons[index] = newValue
                    appState.selectedIcon = newValue
                    appState.saveLibrary()
                }
            }
        )
    }
}
