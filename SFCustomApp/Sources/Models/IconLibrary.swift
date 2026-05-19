import Foundation

/// Container for the full icon collection with persistence
struct IconLibrary: Codable {
    var icons: [Icon] = []
    var fontName: String = "SFCustomIcons"
    var nextCodepoint: UInt32 = 0xE000

    /// File URL for persisting the library as JSON
    static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SFCustom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    /// Assign the next available Private Use Area codepoint
    mutating func assignCodepoint() -> UInt32 {
        let cp = nextCodepoint
        nextCodepoint += 1
        return cp
    }

    /// Find icons matching a search query (name or tags)
    func search(_ query: String) -> [Icon] {
        let q = query.lowercased()
        return icons.filter { icon in
            icon.name.lowercased().contains(q) ||
            icon.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }
}
