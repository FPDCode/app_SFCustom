import Foundation
import SwiftUI

/// Persists the user's icon library to ~/Library/Application Support/SF Custom/library.json.
@MainActor
final class IconLibrary: ObservableObject {
    @Published private(set) var icons: [Icon] = []

    private let storeURL: URL

    static let pueStart: UInt32 = 0xE000

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SF Custom", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.storeURL = base.appendingPathComponent("library.json")
        load()
    }

    func add(name: String, sourceSVG: String, figmaNodeID: String? = nil) -> Icon {
        let next = nextCodepoint()
        let icon = Icon(
            name: uniqueName(from: name),
            sourceSVG: sourceSVG,
            codepoint: next,
            figmaNodeID: figmaNodeID
        )
        icons.append(icon)
        save()
        return icon
    }

    func update(_ icon: Icon) {
        guard let idx = icons.firstIndex(where: { $0.id == icon.id }) else { return }
        var updated = icon
        updated.updatedAt = .now
        icons[idx] = updated
        save()
    }

    /// Replace an existing icon's source SVG (and optionally its name).
    /// Keeps the same id, codepoint, and Figma link — so users keep their
    /// Unicode character stable across updates.
    @discardableResult
    func replace(
        _ icon: Icon,
        with newSVG: String,
        renamingTo newName: String? = nil,
        figmaNodeID: String? = nil
    ) -> Icon {
        guard let idx = icons.firstIndex(where: { $0.id == icon.id }) else { return icon }
        icons[idx].sourceSVG = newSVG
        if let newName, !newName.isEmpty {
            icons[idx].name = uniqueName(from: newName, excluding: icon.id)
        }
        if let figmaNodeID {
            icons[idx].figmaNodeID = figmaNodeID
        }
        icons[idx].updatedAt = .now
        save()
        return icons[idx]
    }

    func delete(_ icon: Icon) {
        icons.removeAll { $0.id == icon.id }
        save()
    }

    func rename(_ icon: Icon, to newName: String) {
        guard let idx = icons.firstIndex(where: { $0.id == icon.id }) else { return }
        icons[idx].name = uniqueName(from: newName, excluding: icon.id)
        icons[idx].updatedAt = .now
        save()
    }

    /// Break the link between a library icon and its source Figma node,
    /// so the next send creates a fresh icon instead of overwriting this one.
    func unlinkFromFigma(_ icon: Icon) {
        guard let idx = icons.firstIndex(where: { $0.id == icon.id }) else { return }
        icons[idx].figmaNodeID = nil
        icons[idx].updatedAt = .now
        save()
    }

    // MARK: - Lookup

    func find(byFigmaNodeID nodeID: String) -> Icon? {
        icons.first { $0.figmaNodeID == nodeID }
    }

    func find(byID id: UUID) -> Icon? {
        icons.first { $0.id == id }
    }

    func find(byName name: String) -> Icon? {
        icons.first { $0.name == name }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Icon].self, from: data) {
            self.icons = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(icons) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Helpers

    private func nextCodepoint() -> UInt32 {
        let used = Set(icons.map(\.codepoint))
        var cp = Self.pueStart
        while used.contains(cp) { cp += 1 }
        return cp
    }

    private func uniqueName(from raw: String, excluding excludedID: UUID? = nil) -> String {
        let base = sanitize(raw)
        let taken = Set(icons.filter { $0.id != excludedID }.map(\.name))
        if !taken.contains(base) { return base }
        var i = 2
        while taken.contains("\(base).\(i)") { i += 1 }
        return "\(base).\(i)"
    }

    private func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "icon" }
        // SF Symbol-style names: lowercase, dot-separated tokens.
        return trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: ".")
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }
}
