import Foundation

/// Writes an Xcode asset-catalog symbol (`<name>.symbolset/`).
///
/// Drag the folder into any `.xcassets` — or point `write` at an
/// `.xcassets` folder directly — and use it with `Image("<name>")`.
public enum SymbolsetExporter {

    public static func contentsJSON(svgFilename: String) -> String {
        """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          },
          "symbols" : [
            {
              "filename" : "\(svgFilename)",
              "idiom" : "universal"
            }
          ]
        }

        """
    }

    /// Asset names can't contain path separators; keep dots and dashes
    /// (SF Symbol style names like `heart.circle.fill` are fine).
    public static func assetName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return s.isEmpty ? "symbol" : s
    }

    /// - Parameter directory: any folder, or an `.xcassets` catalog (a
    ///   catalog `Contents.json` is created when missing).
    /// - Returns: URL of the written `.symbolset` folder.
    @discardableResult
    public static func write(templateSVG: String, name: String, to directory: URL) throws -> URL {
        let fm = FileManager.default
        let asset = assetName(name)
        if directory.pathExtension == "xcassets" {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let catalogContents = directory.appendingPathComponent("Contents.json")
            if !fm.fileExists(atPath: catalogContents.path) {
                try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalogContents, atomically: true, encoding: .utf8)
            }
        }
        let folder = directory.appendingPathComponent("\(asset).symbolset", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let svgName = "\(asset).svg"
        try templateSVG.write(to: folder.appendingPathComponent(svgName), atomically: true, encoding: .utf8)
        try contentsJSON(svgFilename: svgName).write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        return folder
    }
}

/// Copy-paste code for developers, following the talk's advice: use the
/// symbol like an SF Symbol and align on the first text baseline — no
/// `.renderingMode`, `@ScaledMetric` or frame workarounds needed.
public enum HandoffSnippet {

    public static func swiftUI(name: String) -> String {
        let asset = SymbolsetExporter.assetName(name)
        return """
        // Custom SF Symbol — scales and changes weight with the text.
        HStack(alignment: .firstTextBaseline) {
            Image("\(asset)")
            Text("Label")
        }
        // Or inline: Label("Label", image: "\(asset)")
        // Weight follows the font: .font(.body.weight(.semibold))
        """
    }

    public static func uiKit(name: String) -> String {
        let asset = SymbolsetExporter.assetName(name)
        return """
        let config = UIImage.SymbolConfiguration(textStyle: .body)
        let image = UIImage(named: "\(asset)", in: nil, with: config)
        imageView.image = image
        imageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
        """
    }

    /// Short how-to for the designer → developer handoff.
    public static func instructions(name: String) -> String {
        let asset = SymbolsetExporter.assetName(name)
        return """
        1. Drag \(asset).symbolset into your Assets.xcassets.
        2. Use Image("\(asset)") anywhere you'd use Image(systemName:).
        3. Align with text on .firstTextBaseline; size and weight follow the font.
        """
    }
}

/// Builds the per-icon payload for `build_font.py`.
public enum FontSpec {

    /// - Returns: JSON-compatible dictionary. `paths` holds the Regular
    ///   outline (static font); `masters` holds all three anchors with
    ///   identical structure (variable font). Coordinates are template
    ///   units, y down, baseline at 0, cap line at −70.459.
    public static func icon(name: String, codepoint: Int, template: SymbolTemplate) -> [String: Any] {
        var masters: [String: Any] = [:]
        var advances: [String: Double] = [:]
        for a in template.anchors {
            masters[a.weight.rawValue] = [SVGPathWriter.write(a.path, precision: 4)]
            advances[a.weight.rawValue] = a.slotWidth
        }
        let reg = template.anchor(.regular)
        return [
            "name": glyphName(name),
            "codepoint": codepoint,
            "units": "template",
            "cap_height": SymbolTemplateBuilder.capHeight,
            "paths": [SVGPathWriter.write(reg.path, precision: 4)],
            "advance": reg.slotWidth,
            "masters": masters,
            "master_advances": advances,
            "compatible": template.compatibility.status == .ok,
        ]
    }

    /// PostScript-safe glyph name.
    public static func glyphName(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        var s = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if let f = s.first, f.isNumber || f == "." { s = "g" + s }
        return s.isEmpty ? "glyph" : String(s.prefix(60))
    }
}
