import Foundation

/// A single custom icon with its vector data and weight configuration
struct Icon: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var tags: [String]
    var weightMode: WeightMode
    var masters: WeightMasters
    /// Optional full SVG document captured from the source (e.g. from Figma).
    /// When present, renderers should prefer this over `masters.regular` —
    /// it preserves multiple paths, strokes, transforms, and fill rules that
    /// a flattened single-path string cannot.
    var sourceSVG: String?
    var unicodeCodepoint: UInt32
    var createdAt: Date
    var updatedAt: Date
    var version: Int
    var versionHistory: [IconSnapshot]

    /// The Unicode character for this icon's codepoint
    var unicodeCharacter: String {
        guard let scalar = Unicode.Scalar(unicodeCodepoint) else { return "?" }
        return String(scalar)
    }

    /// Formatted codepoint string (e.g. "U+E000")
    var codepointHex: String {
        "U+\(String(unicodeCodepoint, radix: 16, uppercase: true))"
    }

    init(
        name: String,
        svgPath: String,
        weightMode: WeightMode = .uniform,
        tags: [String] = [],
        unicodeCodepoint: UInt32? = nil,
        sourceSVG: String? = nil
    ) {
        self.sourceSVG = sourceSVG
        self.id = UUID()
        self.name = name
        self.tags = tags
        self.weightMode = weightMode
        self.createdAt = Date()
        self.updatedAt = Date()
        self.version = 1
        self.versionHistory = []
        // Default to Private Use Area starting at U+E000
        self.unicodeCodepoint = unicodeCodepoint ?? 0xE000

        // Initialize masters based on weight mode
        switch weightMode {
        case .uniform:
            self.masters = WeightMasters(
                ultralight: svgPath,
                regular: svgPath,
                black: svgPath
            )
        case .singleGenerate(let sourceWeight):
            // Placeholder — actual generation happens in WeightCurve
            self.masters = WeightMasters(
                ultralight: svgPath,
                regular: svgPath,
                black: svgPath,
                sourceWeight: sourceWeight
            )
        case .fullControl:
            // Caller must set masters individually after init
            self.masters = WeightMasters(
                ultralight: svgPath,
                regular: svgPath,
                black: svgPath
            )
        }
    }

    /// Save the current state as a snapshot before overriding
    mutating func snapshotCurrentVersion() {
        let snapshot = IconSnapshot(
            version: version,
            masters: masters,
            weightMode: weightMode,
            savedAt: Date()
        )
        versionHistory.append(snapshot)
    }

    /// Override the icon with new path data, bumping the version
    mutating func override(with svgPath: String, weightMode: WeightMode = .uniform) {
        snapshotCurrentVersion()
        version += 1
        updatedAt = Date()
        self.weightMode = weightMode

        switch weightMode {
        case .uniform:
            masters = WeightMasters(ultralight: svgPath, regular: svgPath, black: svgPath)
        case .singleGenerate(let sourceWeight):
            masters = WeightMasters(ultralight: svgPath, regular: svgPath, black: svgPath, sourceWeight: sourceWeight)
        case .fullControl:
            masters = WeightMasters(ultralight: svgPath, regular: svgPath, black: svgPath)
        }
    }

    /// Restore a previous version from history
    mutating func restore(version targetVersion: Int) {
        guard let snapshot = versionHistory.first(where: { $0.version == targetVersion }) else { return }
        snapshotCurrentVersion()
        version += 1
        updatedAt = Date()
        masters = snapshot.masters
        weightMode = snapshot.weightMode
    }
}

/// A frozen snapshot of an icon's state at a point in time
struct IconSnapshot: Codable, Hashable {
    let version: Int
    let masters: WeightMasters
    let weightMode: WeightMode
    let savedAt: Date
}

/// The three master weight variants needed for dynamic SF Symbol templates
struct WeightMasters: Codable, Hashable {
    var ultralight: String  // SVG path data
    var regular: String     // SVG path data
    var black: String       // SVG path data
    var sourceWeight: SourceWeight?

    /// Which weight the user originally provided (for single+generate mode)
    enum SourceWeight: String, Codable, Hashable {
        case ultralight
        case regular
        case black
    }
}

/// How the user provides weight variants
enum WeightMode: Codable, Hashable {
    case uniform                              // Same icon for all weights
    case singleGenerate(SourceWeight)         // One icon, app generates the rest
    case fullControl                          // User provides all 3

    typealias SourceWeight = WeightMasters.SourceWeight
}
