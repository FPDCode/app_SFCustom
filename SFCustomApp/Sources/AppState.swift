import SwiftUI
import Combine

/// Central app state managing the icon library, server, and font compilation
@MainActor
class AppState: ObservableObject {
    @Published var library: IconLibrary = IconLibrary()
    @Published var selectedIcon: Icon?
    @Published var isServerRunning: Bool = false
    @Published var lastExportedFontURL: URL?
    @Published var statusMessage: String = "Ready"

    let templateGenerator = TemplateGenerator()
    let fontCompiler = FontCompiler()
    let fontBookInstaller = FontBookInstaller()
    let localServer = LocalServer()

    init() {
        loadLibrary()
    }

    func loadLibrary() {
        if let data = try? Data(contentsOf: IconLibrary.storageURL),
           let lib = try? JSONDecoder().decode(IconLibrary.self, from: data) {
            library = lib
        }
    }

    func saveLibrary() {
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: IconLibrary.storageURL)
        }
    }

    func addIcon(_ icon: Icon) {
        library.icons.append(icon)
        selectedIcon = icon
        saveLibrary()
        statusMessage = "Added \(icon.name)"
    }

    func removeIcon(_ icon: Icon) {
        library.icons.removeAll { $0.id == icon.id }
        if selectedIcon?.id == icon.id { selectedIcon = nil }
        saveLibrary()
    }

    func exportTemplate(for icon: Icon) throws -> Data {
        let svg = try templateGenerator.generate(for: icon)
        statusMessage = "Template exported for \(icon.name)"
        return Data(svg.utf8)
    }

    func exportFont() throws -> URL {
        let url = try fontCompiler.compile(icons: library.icons)
        lastExportedFontURL = url
        statusMessage = "Font compiled with \(library.icons.count) icons"
        return url
    }

    func installFont() throws {
        guard let url = lastExportedFontURL else {
            throw SFCustomError.noFontCompiled
        }
        try fontBookInstaller.install(fontAt: url)
        statusMessage = "Font installed to Font Book"
    }

    func startServer() {
        Task {
            do {
                try await localServer.start(appState: self)
                isServerRunning = true
                statusMessage = "Server running on localhost:\(localServer.port)"
            } catch {
                statusMessage = "Server error: \(error.localizedDescription)"
            }
        }
    }

    func stopServer() {
        localServer.stop()
        isServerRunning = false
        statusMessage = "Server stopped"
    }
}

enum SFCustomError: LocalizedError {
    case noFontCompiled
    case invalidSVG(String)
    case fontCompilationFailed(String)
    case fontInstallFailed(String)
    case templateGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFontCompiled: return "No font has been compiled yet. Export a font first."
        case .invalidSVG(let msg): return "Invalid SVG: \(msg)"
        case .fontCompilationFailed(let msg): return "Font compilation failed: \(msg)"
        case .fontInstallFailed(let msg): return "Font install failed: \(msg)"
        case .templateGenerationFailed(let msg): return "Template generation failed: \(msg)"
        }
    }
}
