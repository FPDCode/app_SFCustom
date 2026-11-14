import Foundation
import SwiftUI
import SFCustomEngine

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("server.port")              var serverPort: Int = 8787
    @AppStorage("server.autostart")         var startServerAutomatically: Bool = true
    @AppStorage("font.familyName")          var familyName: String = "SF Custom"
    @AppStorage("font.styleName")           var styleName: String = "Regular"
    @AppStorage("preview.showGuides")       var showGuides: Bool = true
    @AppStorage("preview.darkBackground")   var darkBackground: Bool = false

    // Symbol generation (see SymbolSettings for the keys' meaning).
    @AppStorage(SymbolSettings.Key.ladderPreset)    var ladderPreset: String = StrokeLadder.Preset.talk.rawValue
    @AppStorage(SymbolSettings.Key.customUltralight) var customUltralight: Double = 2
    @AppStorage(SymbolSettings.Key.customRegular)    var customRegular: Double = 7
    @AppStorage(SymbolSettings.Key.customBlack)      var customBlack: Double = 13
    @AppStorage(SymbolSettings.Key.normalizeRegular) var normalizeRegular: Bool = true
    @AppStorage(SymbolSettings.Key.defaultMargin)    var defaultMargin: Double = AnchorMargins.standard.left
    @AppStorage(SymbolSettings.Key.variableFont)     var variableFont: Bool = false
}

/// Reads symbol settings straight from `UserDefaults` so non-UI code
/// (TemplateGenerator, Exporter, FontCompiler) uses exactly what the
/// Settings window shows, without needing the `AppSettings` object.
enum SymbolSettings {
    enum Key {
        static let ladderPreset = "symbol.ladderPreset"
        static let customUltralight = "symbol.customUltralight"
        static let customRegular = "symbol.customRegular"
        static let customBlack = "symbol.customBlack"
        static let normalizeRegular = "symbol.normalizeRegular"
        static let defaultMargin = "symbol.defaultMargin"
        static let variableFont = "font.variable"
    }

    private static var defaults: UserDefaults { .standard }

    private static func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    static var preset: StrokeLadder.Preset {
        StrokeLadder.Preset(rawValue: defaults.string(forKey: Key.ladderPreset) ?? "") ?? .talk
    }

    static var ladder: StrokeLadder {
        switch preset {
        case .talk:   return .talk
        case .legacy: return .legacy
        case .custom:
            return StrokeLadder(ultralight: max(0.1, double(Key.customUltralight, 2)),
                                regular: max(0.1, double(Key.customRegular, 7)),
                                black: max(0.1, double(Key.customBlack, 13)))
        }
    }

    static var normalizeRegular: Bool { bool(Key.normalizeRegular, true) }
    static var defaultMargin: Double { max(0, double(Key.defaultMargin, AnchorMargins.standard.left)) }
    static var variableFont: Bool { bool(Key.variableFont, false) }

    static func margins(for icon: Icon) -> [AnchorWeight: AnchorMargins] {
        var out: [AnchorWeight: AnchorMargins] = [:]
        for w in AnchorWeight.allCases {
            out[w] = icon.margins?[w.rawValue] ?? AnchorMargins(left: defaultMargin, right: defaultMargin)
        }
        return out
    }

    static func options(for icon: Icon) -> SymbolBuildOptions {
        SymbolBuildOptions(name: icon.name,
                           ladder: ladder,
                           normalizeRegularStroke: normalizeRegular,
                           margins: margins(for: icon),
                           mode: icon.symbolMode ?? .weights)
    }
}
