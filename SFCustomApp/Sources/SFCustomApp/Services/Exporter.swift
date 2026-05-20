import Foundation
import AppKit

/// Writes templates and source SVGs to `~/SFCustomExports/<iconName>/`,
/// the user-visible "test exports" folder.
///
/// One per-icon folder keeps things tidy when you're iterating on multiple
/// icons in parallel — and Xcode/SF Symbols app can ingest the `template.svg`
/// directly without any post-processing.
@MainActor
struct Exporter {

    enum ExportError: Error, LocalizedError {
        case couldNotCreateDirectory(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .couldNotCreateDirectory(let msg): return "Couldn't create export folder: \(msg)"
            case .writeFailed(let msg):            return "Write failed: \(msg)"
            }
        }
    }

    struct ExportResult {
        var iconFolder: URL
        var templateURL: URL
        var sourceURL: URL
    }

    /// The user-visible exports root. Lives at `~/SFCustomExports/`.
    static var rootDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("SFCustomExports", isDirectory: true)
    }

    /// Render and export the 9×3 SF Symbol template + the source SVG to
    /// `~/SFCustomExports/<icon.name>/`.
    func export(icon: Icon) async throws -> ExportResult {
        let templateXML = try await TemplateGenerator().generate(for: icon)

        let folder = Self.rootDirectory.appendingPathComponent(icon.name, isDirectory: true)
        try createDirectory(folder)

        let templateURL = folder.appendingPathComponent("template.svg")
        let sourceURL   = folder.appendingPathComponent("source.svg")

        do {
            try templateXML.write(to: templateURL, atomically: true, encoding: .utf8)
            try icon.sourceSVG.write(to: sourceURL,   atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        return ExportResult(iconFolder: folder, templateURL: templateURL, sourceURL: sourceURL)
    }

    /// Reveal the exports root (or a specific subfolder) in Finder.
    func reveal(_ url: URL? = nil) {
        let target = url ?? Self.rootDirectory
        if !FileManager.default.fileExists(atPath: target.path) {
            try? createDirectory(target)
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ExportError.couldNotCreateDirectory(error.localizedDescription)
        }
    }
}
