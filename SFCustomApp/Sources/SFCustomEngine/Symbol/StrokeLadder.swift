import Foundation

/// Stroke widths for the three SF Symbol anchors, in template units
/// (cap height = 70.459).
///
/// The default is the recipe from Bruno Scheele's talk "Custom SF
/// Symbols; fun, but not easy!": Ultralight 2 · Regular 7 · Black 13.
public struct StrokeLadder: Hashable, Codable, Sendable {
    public var ultralight: Double
    public var regular: Double
    public var black: Double

    public init(ultralight: Double, regular: Double, black: Double) {
        self.ultralight = ultralight
        self.regular = regular
        self.black = black
    }

    /// Talk recipe — closest to Apple's own symbols at cap height 70.
    public static let talk = StrokeLadder(ultralight: 2, regular: 7, black: 13)
    /// The original SF Custom multipliers (0.42× / 1× / 2.5×).
    public static let legacy = StrokeLadder(ultralight: 0.42 * 7, regular: 7, black: 2.5 * 7)

    public enum Preset: String, CaseIterable, Codable, Sendable {
        case talk, legacy, custom

        public var displayName: String {
            switch self {
            case .talk:   return "Apple-like (2 · 7 · 13)"
            case .legacy: return "Legacy (0.42× · 1× · 2.5×)"
            case .custom: return "Custom"
            }
        }
    }

    /// Multiplier relative to Regular for an anchor.
    public func ratio(for w: AnchorWeight) -> Double {
        guard regular > 0 else { return 1 }
        switch w {
        case .ultralight: return ultralight / regular
        case .regular:    return 1
        case .black:      return black / regular
        }
    }

    public func width(for w: AnchorWeight) -> Double {
        switch w {
        case .ultralight: return ultralight
        case .regular:    return regular
        case .black:      return black
        }
    }
}

/// The three weights a designer provides; Apple interpolates the rest.
public enum AnchorWeight: String, CaseIterable, Codable, Sendable, Hashable {
    case ultralight, regular, black

    /// Group id suffix used in the template: `Ultralight-S` etc.
    public var templateID: String {
        switch self {
        case .ultralight: return "Ultralight"
        case .regular:    return "Regular"
        case .black:      return "Black"
        }
    }

    public var displayName: String { templateID }
}

/// Left / right side bearing between the glyph and its margin guides,
/// in template units. The talk recommends 8–10; Apple's exports use 9.77.
public struct AnchorMargins: Hashable, Codable, Sendable {
    public var left: Double
    public var right: Double

    public init(left: Double, right: Double) {
        self.left = left
        self.right = right
    }

    public static let standard = AnchorMargins(left: 9.76562, right: 9.76562)
}
