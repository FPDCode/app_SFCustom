import Foundation

/// Compiles a set of icons into a single .otf font by shelling out to a
/// bundled Python script that uses `fontTools`.
///
/// The font carries one glyph per icon, mapped to a Private Use Area
/// codepoint so it can be typed/used as a single character (typical
/// icon-font workflow — works in Figma, Keynote, etc.).
@MainActor
final class FontCompiler {

    enum CompileError: Error, LocalizedError {
        case noPythonFound
        case fontToolsMissing
        case scriptMissing
        case noIcons
        case scriptFailed(String)
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .noPythonFound:
                return "Couldn't find Python 3. Install it from python.org or Homebrew."
            case .fontToolsMissing:
                return "The Python package 'fonttools' isn't installed. Run: pip3 install --user fonttools"
            case .scriptMissing:
                return "Bundled font builder script is missing from the app."
            case .noIcons:
                return "Add at least one icon to your library before compiling a font."
            case .scriptFailed(let msg):
                return "Font compilation failed: \(msg)"
            case .outputMissing:
                return "Font compilation finished but no .otf was produced."
            }
        }
    }

    struct CompileResult {
        var fontURL: URL
        var glyphCount: Int
    }

    /// Best-effort search: prefer Homebrew Pythons (more likely to have
    /// fonttools), fall back to system Python at /usr/bin/python3.
    private static let pythonCandidates: [String] = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    /// Where compiled fonts get saved by default.
    static var defaultOutputDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SF Custom/Fonts", isDirectory: true)
    }

    /// Run the bundled `build_font.py` against the given library.
    func compile(
        icons: [Icon],
        familyName: String = "SF Custom",
        styleName: String = "Regular",
        outputDirectory: URL? = nil
    ) throws -> CompileResult {
        guard !icons.isEmpty else { throw CompileError.noIcons }

        let python = try findPython()
        try ensureFontToolsInstalled(python: python)

        guard let scriptURL = Bundle.module.url(forResource: "build_font", withExtension: "py") else {
            throw CompileError.scriptMissing
        }

        let outDir = outputDirectory ?? Self.defaultOutputDirectory
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("\(familyName.replacingOccurrences(of: " ", with: ""))-\(styleName).otf")

        let spec: [String: Any] = [
            "family_name": familyName,
            "style_name":  styleName,
            "output":      outURL.path,
            "icons":       icons.map(buildIconPayload),
        ]
        let specURL = try writeSpec(spec)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptURL.path, "--spec", specURL.path]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            if stderr.contains("FONTOOLS_MISSING") {
                throw CompileError.fontToolsMissing
            }
            throw CompileError.scriptFailed(stderr.isEmpty ? "exit code \(process.terminationStatus)" : stderr)
        }

        guard FileManager.default.fileExists(atPath: outURL.path) else {
            throw CompileError.outputMissing
        }

        return CompileResult(fontURL: outURL, glyphCount: icons.count)
    }

    /// Returns the path of a Python 3 with fonttools installed, or throws.
    /// Made `public` so the UI can probe and surface a setup helper.
    func diagnose() -> Diagnosis {
        guard let python = (try? findPython()) else { return .noPython }
        do {
            try ensureFontToolsInstalled(python: python)
            return .ready(pythonPath: python)
        } catch {
            return .fontToolsMissing(pythonPath: python)
        }
    }

    enum Diagnosis: Equatable {
        case ready(pythonPath: String)
        case fontToolsMissing(pythonPath: String)
        case noPython
    }

    // MARK: - Private helpers

    private func buildIconPayload(_ icon: Icon) -> [String: Any] {
        let extract = SVGSurface.extract(from: icon.sourceSVG)
        return [
            "name":      icon.name,
            "codepoint": Int(icon.codepoint),
            "viewbox":   [extract.viewBox.x, extract.viewBox.y, extract.viewBox.width, extract.viewBox.height],
            "paths":     extract.paths,
        ]
    }

    private func writeSpec(_ spec: [String: Any]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sfcustom-spec-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func findPython() throws -> String {
        for candidate in Self.pythonCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Fall back to PATH lookup via /usr/bin/env
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0,
           let str = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
           let line = str.split(separator: "\n").first {
            return String(line)
        }
        throw CompileError.noPythonFound
    }

    private func ensureFontToolsInstalled(python: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", "import fontTools"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CompileError.fontToolsMissing
        }
    }
}

/// Minimal SVG inspector used by the font compiler to pull each icon's
/// path 'd' attributes and a viewBox. This intentionally does NOT try to
/// be a full SVG parser — the font glyph workflow only needs raw fill
/// path data.
enum SVGSurface {
    struct ViewBox {
        var x: Double = 0
        var y: Double = 0
        var width: Double = 100
        var height: Double = 100
    }

    struct Extract {
        var viewBox: ViewBox
        var paths: [String]
    }

    static func extract(from svg: String) -> Extract {
        return Extract(viewBox: parseViewBox(svg), paths: parsePathDs(svg))
    }

    private static func parseViewBox(_ svg: String) -> ViewBox {
        var vb = ViewBox()
        if let value = attributeValue(named: "viewBox", in: svg) {
            let parts = value.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if parts.count == 4 {
                vb.x = parts[0]; vb.y = parts[1]; vb.width = parts[2]; vb.height = parts[3]
                return vb
            }
        }
        if let w = attributeValue(named: "width", in: svg).flatMap(parseLength),
           let h = attributeValue(named: "height", in: svg).flatMap(parseLength) {
            vb.width = w; vb.height = h
        }
        return vb
    }

    private static func parsePathDs(_ svg: String) -> [String] {
        var out: [String] = []
        var idx = svg.startIndex
        while let r = svg.range(of: "<path", range: idx..<svg.endIndex) {
            guard let close = svg.range(of: ">", range: r.upperBound..<svg.endIndex) else { break }
            let pathTag = String(svg[r.lowerBound..<close.upperBound])
            if let d = attributeValue(named: "d", in: pathTag), !d.isEmpty {
                out.append(d)
            }
            idx = close.upperBound
        }
        return out
    }

    private static func attributeValue(named name: String, in source: String) -> String? {
        guard let range = source.range(of: "\(name)=\"") else {
            guard let range2 = source.range(of: "\(name)='") else { return nil }
            guard let end = source.range(of: "'", range: range2.upperBound..<source.endIndex) else { return nil }
            return String(source[range2.upperBound..<end.lowerBound])
        }
        guard let end = source.range(of: "\"", range: range.upperBound..<source.endIndex) else { return nil }
        return String(source[range.upperBound..<end.lowerBound])
    }

    private static func parseLength(_ str: String) -> Double? {
        let cleaned = str
            .replacingOccurrences(of: "px", with: "")
            .replacingOccurrences(of: "pt", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}
