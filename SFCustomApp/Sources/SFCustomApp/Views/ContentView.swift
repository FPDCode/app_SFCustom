import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var library: IconLibrary
    @EnvironmentObject var server: LocalServer
    @EnvironmentObject var settings: AppSettings

    @State private var selection: Icon.ID?
    @State private var searchText = ""
    @State private var isImporterPresented = false
    @State private var importError: String?
    @State private var isCompareOpen = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("SF Custom")
        .toolbar { toolbar }
        .onReceive(NotificationCenter.default.publisher(for: .sfcImportSVG)) { _ in
            isImporterPresented = true
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.svg],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): importSVGs(urls)
            case .failure(let err):  importError = err.localizedDescription
            }
        }
        .alert("Import failed", isPresented: .constant(importError != nil), actions: {
            Button("OK") { importError = nil }
        }, message: { Text(importError ?? "") })
        .sheet(isPresented: $isCompareOpen) {
            CompareView(initialIcon: selectedIcon)
                .environmentObject(library)
                .environmentObject(settings)
        }
        .onDrop(of: [.svg, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Sidebar (icon library)

    private var sidebar: some View {
        VStack(spacing: 0) {
            ServerStatusBadge()
                .padding(.horizontal, 12)
                .padding(.top, 12)

            SearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            List(selection: $selection) {
                if filteredIcons.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredIcons) { icon in
                        IconRow(icon: icon)
                            .tag(icon.id as Icon.ID?)
                            .contextMenu { iconContextMenu(for: icon) }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                isImporterPresented = true
            } label: {
                Label("Import SVG…", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("No icons yet")
                .font(.headline)
            Text("Drop an SVG here, or send one from the Figma plugin.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let icon = selectedIcon {
                IconDetailView(icon: icon)
                    .id(icon.id) // refresh when selection changes
            } else if library.icons.isEmpty {
                WelcomeView { isImporterPresented = true }
            } else {
                VStack {
                    Spacer()
                    Text("Pick an icon from the sidebar")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isCompareOpen = true
            } label: {
                Label("Compare", systemImage: "rectangle.split.2x1")
            }
            .disabled(library.icons.isEmpty)
            .help("Test your icons side-by-side with SF Pro symbols")
        }
        ToolbarItem(placement: .primaryAction) {
            CompileFontButton()
        }
    }

    // MARK: - Helpers

    private var filteredIcons: [Icon] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return library.icons.sorted { $0.name < $1.name } }
        return library.icons
            .filter { $0.name.lowercased().contains(q) }
            .sorted { $0.name < $1.name }
    }

    private var selectedIcon: Icon? {
        guard let id = selection else { return nil }
        return library.icons.first { $0.id == id }
    }

    private func importSVGs(_ urls: [URL]) {
        for url in urls {
            let needs = url.startAccessingSecurityScopedResource()
            defer { if needs { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let svg = String(data: data, encoding: .utf8) else {
                importError = "Couldn't read \(url.lastPathComponent)"
                continue
            }
            let name = url.deletingPathExtension().lastPathComponent
            let icon = library.add(name: name, sourceSVG: svg)
            selection = icon.id
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    importSVGs([url])
                }
            }
        }
    }

    private func renameIcon(_ icon: Icon) {
        let alert = NSAlert()
        alert.messageText = "Rename Icon"
        alert.informativeText = "Use lowercase, dot-separated tokens for SF Symbol-style names."
        let input = NSTextField(string: icon.name)
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            library.rename(icon, to: input.stringValue)
        }
    }

    private func duplicate(_ icon: Icon) {
        let dup = library.add(name: icon.name, sourceSVG: icon.sourceSVG)
        selection = dup.id
    }

    @ViewBuilder
    private func iconContextMenu(for icon: Icon) -> some View {
        Button { CopyAction.symbol(icon) } label: {
            Label("Copy Symbol", systemImage: "doc.on.doc")
        }
        Button { CopyAction.name(icon) } label: {
            Label("Copy Name", systemImage: "textformat")
        }
        Button { CopyAction.codepoint(icon) } label: {
            Label("Copy Codepoint  (\(icon.codepointString))", systemImage: "number")
        }
        Button { CopyAction.svg(icon) } label: {
            Label("Copy SVG", systemImage: "curlybraces")
        }
        Divider()
        Button("Rename…", action: { renameIcon(icon) })
        Button("Duplicate", action: { duplicate(icon) })
        if icon.figmaNodeID != nil {
            Button("Unlink from Figma") { library.unlinkFromFigma(icon) }
        }
        Divider()
        Button("Delete", role: .destructive) { library.delete(icon) }
    }
}

#if canImport(AppKit)
import AppKit
#endif

private extension UTType {
    static var svg: UTType { UTType(filenameExtension: "svg") ?? .image }
}
