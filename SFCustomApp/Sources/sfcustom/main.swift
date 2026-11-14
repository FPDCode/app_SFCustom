import Foundation
import SFCustomEngine

// sfcustom — SF Custom's engine on the command line (CI-friendly).
//
//   sfcustom export icon.svg… [--out DIR] [--ladder talk|legacy|UL,REG,BLACK]
//                   [--no-normalize] [--margin L,R] [--scale-only]
//                   [--symbolset | --xcassets PATH] [--lint strict]
//   sfcustom lint template.svg… [--fix]
//   sfcustom preview icon.svg… [--out DIR]   (onion skin + all 9 weights)
//   sfcustom font icon.svg… --out Font.otf [--variable] [--family NAME]
//                   [--script build_font.py] [--python python3]
//
// Exit codes: 0 ok · 1 compatibility failure · 2 usage / IO error.

struct CLIError: Error, CustomStringConvertible { var description: String }

func stderr(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let usage = """
usage:
  sfcustom export <icon.svg>... [--out DIR] [--ladder talk|legacy|UL,REG,BLACK]
                  [--no-normalize] [--margin L,R] [--scale-only]
                  [--symbolset | --xcassets PATH] [--lint strict]
  sfcustom lint <template.svg>... [--fix]
  sfcustom font <icon.svg>... --out Font.otf [--variable] [--family NAME]
                  [--script build_font.py] [--python python3]
"""

struct Args {
    var command: String
    var files: [String] = []
    var flags: [String: String] = [:]
    var switches: Set<String> = []

    static let valued: Set<String> = ["--out", "--ladder", "--margin", "--xcassets", "--lint", "--family", "--script", "--python", "--start-codepoint"]

    init(_ argv: [String]) throws {
        guard let cmd = argv.first else { throw CLIError(description: usage) }
        command = cmd
        var i = 1
        while i < argv.count {
            let a = argv[i]
            if Self.valued.contains(a) {
                guard i + 1 < argv.count else { throw CLIError(description: "\(a) needs a value") }
                flags[a] = argv[i + 1]; i += 2
            } else if a.hasPrefix("--") {
                switches.insert(a); i += 1
            } else {
                files.append(a); i += 1
            }
        }
    }
}

func readFile(_ path: String) throws -> String {
    do { return try String(contentsOfFile: path, encoding: .utf8) }
    catch { throw CLIError(description: "can't read \(path): \(error.localizedDescription)") }
}

func baseName(_ path: String) -> String {
    URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
}

func options(for name: String, _ args: Args) throws -> SymbolBuildOptions {
    var o = SymbolBuildOptions(name: name)
    switch args.flags["--ladder"] ?? "talk" {
    case "talk": o.ladder = .talk
    case "legacy": o.ladder = .legacy
    case let v:
        let parts = v.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { throw CLIError(description: "--ladder expects talk, legacy or UL,REG,BLACK") }
        o.ladder = StrokeLadder(ultralight: parts[0], regular: parts[1], black: parts[2])
    }
    o.normalizeRegularStroke = !args.switches.contains("--no-normalize")
    if let m = args.flags["--margin"] {
        let parts = m.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { throw CLIError(description: "--margin expects L,R") }
        let margins = AnchorMargins(left: parts[0], right: parts[1])
        for w in AnchorWeight.allCases { o.margins[w] = margins }
    }
    if args.switches.contains("--scale-only") { o.mode = .scaleOnly }
    return o
}

func printReport(_ name: String, _ r: CompatibilityReport) {
    let mark = r.status == .ok ? "✓" : (r.status == .fixable ? "~" : "✗")
    print("\(mark) \(name): \(r.summary)")
    for i in r.issues { print("    - \(i.message)\(i.isAutoFixable ? " (auto-fixable)" : "")") }
}

func runExport(_ args: Args) throws -> Int32 {
    guard !args.files.isEmpty else { throw CLIError(description: usage) }
    let out = URL(fileURLWithPath: args.flags["--out"] ?? ".", isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var failed = false
    for file in args.files {
        let name = baseName(file)
        let template = try SymbolTemplateBuilder.build(sourceSVG: readFile(file), options: options(for: name, args))
        printReport(name, template.compatibility)
        for w in template.warnings { print("    ! \(w)") }
        if template.compatibility.status == .broken { failed = true }
        if let catalog = args.flags["--xcassets"] {
            let url = try SymbolsetExporter.write(templateSVG: template.svg, name: name, to: URL(fileURLWithPath: catalog, isDirectory: true))
            print("    → \(url.path)")
        } else if args.switches.contains("--symbolset") {
            let url = try SymbolsetExporter.write(templateSVG: template.svg, name: name, to: out)
            print("    → \(url.path)")
        } else {
            let url = out.appendingPathComponent("\(SymbolsetExporter.assetName(name)).svg")
            try template.svg.write(to: url, atomically: true, encoding: .utf8)
            print("    → \(url.path)")
        }
    }
    return failed && args.flags["--lint"] == "strict" ? 1 : 0
}

func runLint(_ args: Args) throws -> Int32 {
    guard !args.files.isEmpty else { throw CLIError(description: usage) }
    var failed = false
    for file in args.files {
        let svg = try readFile(file)
        let report = CompatibilityChecker.check(templateSVG: svg)
        printReport(file, report)
        if args.switches.contains("--fix"), let fixed = CompatibilityFixer.fix(templateSVG: svg) {
            try fixed.write(toFile: file, atomically: true, encoding: .utf8)
            let after = CompatibilityChecker.check(templateSVG: fixed)
            print("    fixed → \(after.summary)")
            if after.status != .ok { failed = true }
        } else if report.status != .ok {
            failed = true
        }
    }
    return failed ? 1 : 0
}

func runFont(_ args: Args) throws -> Int32 {
    guard !args.files.isEmpty, let output = args.flags["--out"] else { throw CLIError(description: usage) }
    var codepoint = Int(args.flags["--start-codepoint"] ?? "") ?? 0xE000
    var icons: [[String: Any]] = []
    for file in args.files {
        let name = baseName(file)
        let template = try SymbolTemplateBuilder.build(sourceSVG: readFile(file), options: options(for: name, args))
        icons.append(FontSpec.icon(name: name, codepoint: codepoint, template: template))
        codepoint += 1
    }
    let family = args.flags["--family"] ?? "SF Custom"
    let spec: [String: Any] = [
        "family_name": family, "style_name": "Regular", "output": output,
        "variable": args.switches.contains("--variable"), "icons": icons,
    ]
    let specURL = FileManager.default.temporaryDirectory.appendingPathComponent("sfcustom-spec-\(UUID().uuidString).json")
    try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys]).write(to: specURL)

    let script = args.flags["--script"] ?? "Sources/SFCustomApp/Resources/build_font.py"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [args.flags["--python"] ?? "python3", script, "--spec", specURL.path]
    try p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? 0 : 2
}

func runPreview(_ args: Args) throws -> Int32 {
    guard !args.files.isEmpty else { throw CLIError(description: usage) }
    let out = URL(fileURLWithPath: args.flags["--out"] ?? ".", isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for file in args.files {
        let name = baseName(file)
        let t = try SymbolTemplateBuilder.build(sourceSVG: readFile(file), options: options(for: name, args))
        let onion = SymbolPreviewRenderer.onionSkin(t)
        try onion.svg.write(to: out.appendingPathComponent("\(name)-onion.svg"), atomically: true, encoding: .utf8)
        // 9 interpolated weights side by side.
        var x = 0.0, cells = "", h = 0.0, top = 0.0
        for (label, pos) in SymbolInterpolator.weightPositions {
            guard let p = SymbolPreviewRenderer.interpolatedPreview(at: pos, in: t) else { continue }
            h = p.viewBoxHeight; top = -p.baselineFromTop
            let inner = p.svg.replacingOccurrences(of: "<svg xmlns=\"http://www.w3.org/2000/svg\"", with: "<svg x=\"\(x)\" y=\"\(top)\" width=\"\(p.viewBoxWidth)\" height=\"\(p.viewBoxHeight)\"")
            cells += inner + "<text x=\"\(x + p.viewBoxWidth / 2)\" y=\"\(top + h + 12)\" font-size=\"9\" text-anchor=\"middle\" font-family=\"sans-serif\">\(label)</text>"
            x += p.viewBoxWidth
        }
        let strip = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 \(top) \(x) \(h + 16)\" color=\"black\">\(cells)</svg>"
        try strip.write(to: out.appendingPathComponent("\(name)-weights.svg"), atomically: true, encoding: .utf8)
        print("\(name): \(t.compatibility.summary) → \(name)-onion.svg, \(name)-weights.svg")
    }
    return 0
}

do {
    let args = try Args(Array(CommandLine.arguments.dropFirst()))
    let code: Int32
    switch args.command {
    case "export": code = try runExport(args)
    case "lint": code = try runLint(args)
    case "font": code = try runFont(args)
    case "preview": code = try runPreview(args)
    case "help", "--help", "-h": print(usage); code = 0
    default: throw CLIError(description: usage)
    }
    exit(code)
} catch {
    stderr("sfcustom: \(error)")
    exit(2)
}
