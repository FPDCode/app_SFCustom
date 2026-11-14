import Foundation
import SFCustomEngine

/// Lets an assistant (Claude Desktop / Claude Code via the `sf-custom-mcp`
/// server) drive the app: list icons, build/check templates, change mode,
/// margins and settings, export, compile fonts.
///
/// All routes live under `/api/control/` on the existing local bridge and
/// require the `X-SFCustom-Token` header. The token is a random secret in
/// `~/Library/Application Support/SF Custom/control-token` (mode 0600), so
/// web pages in a browser — which can reach localhost but can't read your
/// files — can't use these routes. No Anthropic API is involved: the
/// assistant runs under your own Claude account and calls these locally.
enum ControlToken {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SF Custom/control-token")
    }

    /// Reads the token, creating it on first use.
    static func current() -> String {
        if let s = try? String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           s.count >= 32 {
            return s
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? token.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return token
    }

    /// Constant-time comparison.
    static func matches(_ candidate: String?) -> Bool {
        guard let candidate else { return false }
        let a = Array(current().utf8), b = Array(candidate.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in a.indices { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

@MainActor
enum ControlAPI {

    typealias JSON = [String: Any]

    static func handle(method: String, path: String, body: Data?, library: IconLibrary) async -> JSON {
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? JSON) ?? [:]
        let route = String(path.dropFirst("/api/control".count))
        do {
            switch (method, route) {
            case ("GET", "/icons"):            return ["ok": true, "icons": library.icons.map(describe)]
            case ("POST", "/icons/import"):    return try importIcon(input, library)
            case ("POST", "/icons/template"):  return try await template(input, library)
            case ("POST", "/icons/preview"):   return try await preview(input, library)
            case ("POST", "/icons/update"):    return try update(input, library)
            case ("POST", "/icons/delete"):    return try delete(input, library)
            case ("POST", "/icons/export"):    return try await export(input, library)
            case ("POST", "/templates/check"): return try checkTemplate(input)
            case ("GET", "/settings"):         return ["ok": true, "settings": settings()]
            case ("POST", "/settings"):        return try updateSettings(input)
            case ("POST", "/font/compile"):    return try await compileFont(input, library)
            default:
                return ["ok": false, "error": "unknown_route", "route": route]
            }
        } catch let e as ControlError {
            return ["ok": false, "error": e.message]
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }

    struct ControlError: Error { var message: String }

    // MARK: Icons

    static func describe(_ icon: Icon) -> JSON {
        var d: JSON = [
            "id": icon.id.uuidString,
            "name": icon.name,
            "codepoint": String(format: "U+%04X", icon.codepoint),
            "mode": (icon.symbolMode ?? .weights).rawValue,
        ]
        let m = SymbolSettings.margins(for: icon)
        d["margins"] = Dictionary(uniqueKeysWithValues: m.map { ($0.key.rawValue, ["left": $0.value.left, "right": $0.value.right]) })
        if let node = icon.figmaNodeID { d["figmaNodeId"] = node }
        return d
    }

    static func resolve(_ input: JSON, _ library: IconLibrary) throws -> Icon {
        if let id = (input["id"] as? String).flatMap(UUID.init(uuidString:)), let icon = library.find(byID: id) { return icon }
        if let name = input["name"] as? String, let icon = library.find(byName: name) { return icon }
        throw ControlError(message: "icon_not_found (pass an existing id or name)")
    }

    static func importIcon(_ input: JSON, _ library: IconLibrary) throws -> JSON {
        guard let name = input["name"] as? String, let svg = input["svg"] as? String, svg.contains("<svg") else {
            throw ControlError(message: "expected { name, svg }")
        }
        let icon = library.add(name: name, sourceSVG: svg)
        return ["ok": true, "icon": describe(icon)]
    }

    static func template(_ input: JSON, _ library: IconLibrary) async throws -> JSON {
        let icon = try resolve(input, library)
        let t = try await TemplateGenerator().build(for: icon)
        var out: JSON = [
            "ok": true,
            "icon": describe(icon),
            "compatibility": report(t.compatibility),
            "warnings": t.warnings,
            "strokeWidths": Dictionary(uniqueKeysWithValues: t.anchors.compactMap { a in a.strokeWidth.map { (a.weight.rawValue, $0) } }),
        ]
        if (input["includeSVG"] as? Bool) == true { out["svg"] = t.svg }
        return out
    }

    static func preview(_ input: JSON, _ library: IconLibrary) async throws -> JSON {
        let icon = try resolve(input, library)
        let t = try await TemplateGenerator().build(for: icon)
        var weights: JSON = [:]
        for (name, pos) in SymbolInterpolator.weightPositions {
            if let p = SymbolPreviewRenderer.interpolatedPreview(at: pos, in: t) { weights[name] = p.svg }
        }
        return ["ok": true, "onionSkinSVG": SymbolPreviewRenderer.onionSkin(t).svg, "weightSVGs": weights,
                "compatibility": report(t.compatibility)]
    }

    static func update(_ input: JSON, _ library: IconLibrary) throws -> JSON {
        var icon = try resolve(input, library)
        if let mode = input["mode"] as? String {
            guard let m = SymbolMode(rawValue: mode) else { throw ControlError(message: "mode must be weights or scaleOnly") }
            icon.symbolMode = m
        }
        if input["resetMargins"] as? Bool == true { icon.margins = nil }
        if let margins = input["margins"] as? JSON {
            var all = icon.margins ?? [:]
            let current = SymbolSettings.margins(for: icon)
            for (key, value) in margins {
                guard let w = AnchorWeight(rawValue: key), let v = value as? JSON else {
                    throw ControlError(message: "margins keys: ultralight, regular, black → { left, right }")
                }
                var m = current[w] ?? .standard
                if let l = (v["left"] as? NSNumber)?.doubleValue { m.left = max(0, l) }
                if let r = (v["right"] as? NSNumber)?.doubleValue { m.right = max(0, r) }
                all[w.rawValue] = m
            }
            icon.margins = all
        }
        library.update(icon)
        if let newName = input["rename"] as? String, !newName.isEmpty {
            library.rename(icon, to: newName)
        }
        let refreshed = library.find(byID: icon.id) ?? icon
        return ["ok": true, "icon": describe(refreshed)]
    }

    static func delete(_ input: JSON, _ library: IconLibrary) throws -> JSON {
        let icon = try resolve(input, library)
        library.delete(icon)
        return ["ok": true, "deleted": icon.name]
    }

    /// Default: `~/SFCustomExports/<name>/` (template.svg, source.svg,
    /// <name>.symbolset). With `directory`: just the `.symbolset` there
    /// (pass an `.xcassets` folder to add it to a catalog).
    static func export(_ input: JSON, _ library: IconLibrary) async throws -> JSON {
        let icon = try resolve(input, library)
        if let dir = input["directory"] as? String, !dir.isEmpty {
            let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
            let svg = try await TemplateGenerator().generate(for: icon)
            let out = try SymbolsetExporter.write(templateSVG: svg, name: icon.name, to: url)
            return ["ok": true, "symbolset": out.path]
        }
        let r = try await Exporter().export(icon: icon)
        return ["ok": true, "folder": r.iconFolder.path, "template": r.templateURL.path, "symbolset": r.symbolsetURL.path]
    }

    // MARK: Templates

    static func checkTemplate(_ input: JSON) throws -> JSON {
        let svg: String
        if let s = input["svg"] as? String { svg = s }
        else if let p = input["path"] as? String {
            svg = try String(contentsOfFile: (p as NSString).expandingTildeInPath, encoding: .utf8)
        } else { throw ControlError(message: "expected { svg } or { path }") }
        var out: JSON = ["ok": true, "compatibility": report(CompatibilityChecker.check(templateSVG: svg))]
        if input["fix"] as? Bool == true, let fixed = CompatibilityFixer.fix(templateSVG: svg) {
            out["fixedCompatibility"] = report(CompatibilityChecker.check(templateSVG: fixed))
            if let save = input["savePath"] as? String {
                let url = URL(fileURLWithPath: (save as NSString).expandingTildeInPath)
                try fixed.write(to: url, atomically: true, encoding: .utf8)
                out["savedTo"] = url.path
            } else {
                out["fixedSVG"] = fixed
            }
        }
        return out
    }

    static func report(_ r: CompatibilityReport) -> JSON {
        ["status": r.status.rawValue, "summary": r.summary,
         "issues": r.issues.map { ["weight": $0.weight.rawValue, "part": $0.part ?? 0, "message": $0.message, "autoFixable": $0.isAutoFixable] }]
    }

    // MARK: Settings

    static func settings() -> JSON {
        let l = SymbolSettings.ladder
        return ["ladderPreset": SymbolSettings.preset.rawValue,
                "ladder": ["ultralight": l.ultralight, "regular": l.regular, "black": l.black],
                "normalizeRegular": SymbolSettings.normalizeRegular,
                "defaultMargin": SymbolSettings.defaultMargin,
                "variableFont": SymbolSettings.variableFont]
    }

    static func updateSettings(_ input: JSON) throws -> JSON {
        let d = UserDefaults.standard
        if let p = input["ladderPreset"] as? String {
            guard StrokeLadder.Preset(rawValue: p) != nil else { throw ControlError(message: "ladderPreset: talk, legacy or custom") }
            d.set(p, forKey: SymbolSettings.Key.ladderPreset)
        }
        if let l = input["ladder"] as? JSON {
            if let v = (l["ultralight"] as? NSNumber)?.doubleValue { d.set(v, forKey: SymbolSettings.Key.customUltralight) }
            if let v = (l["regular"] as? NSNumber)?.doubleValue { d.set(v, forKey: SymbolSettings.Key.customRegular) }
            if let v = (l["black"] as? NSNumber)?.doubleValue { d.set(v, forKey: SymbolSettings.Key.customBlack) }
            if input["ladderPreset"] == nil { d.set(StrokeLadder.Preset.custom.rawValue, forKey: SymbolSettings.Key.ladderPreset) }
        }
        if let v = input["normalizeRegular"] as? Bool { d.set(v, forKey: SymbolSettings.Key.normalizeRegular) }
        if let v = (input["defaultMargin"] as? NSNumber)?.doubleValue { d.set(max(0, v), forKey: SymbolSettings.Key.defaultMargin) }
        if let v = input["variableFont"] as? Bool { d.set(v, forKey: SymbolSettings.Key.variableFont) }
        return ["ok": true, "settings": settings()]
    }

    // MARK: Font

    static func compileFont(_ input: JSON, _ library: IconLibrary) async throws -> JSON {
        let defaults = UserDefaults.standard
        let family = defaults.string(forKey: "font.familyName") ?? "SF Custom"
        let style = defaults.string(forKey: "font.styleName") ?? "Regular"
        let variable = (input["variable"] as? Bool) ?? SymbolSettings.variableFont
        let result = try await FontCompiler().compile(icons: library.icons, familyName: family,
                                                      styleName: style, variable: variable)
        if (input["install"] as? Bool) ?? true {
            try FontBookInstaller().install(fontAt: result.fontURL)
        }
        return ["ok": true, "font": result.fontURL.path, "glyphs": result.glyphCount, "variable": variable]
    }
}
