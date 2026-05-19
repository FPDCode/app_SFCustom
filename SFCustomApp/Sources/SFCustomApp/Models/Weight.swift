import Foundation

/// The 9 SF Symbol weights, ordered Ultralight → Black.
/// `strokeScale` is the multiplier applied to the source SVG's stroke widths
/// to produce the variant for that weight. These values are calibrated to
/// match Apple's SF Pro weight progression: Regular = 1.0, with a non-linear
/// growth curve so most expansion happens past Regular (matches Apple's
/// "Design Variations" guidance).
enum Weight: String, CaseIterable, Codable, Identifiable {
    case ultralight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultralight: return "Ultralight"
        case .thin:       return "Thin"
        case .light:      return "Light"
        case .regular:    return "Regular"
        case .medium:     return "Medium"
        case .semibold:   return "Semibold"
        case .bold:       return "Bold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        }
    }

    /// Multiplier on stroke-width relative to the source SVG.
    /// Calibrated against Custom Symbols.app output for Regular = 1.0.
    var strokeScale: Double {
        switch self {
        case .ultralight: return 0.42
        case .thin:       return 0.58
        case .light:      return 0.79
        case .regular:    return 1.00
        case .medium:     return 1.18
        case .semibold:   return 1.42
        case .bold:       return 1.71
        case .heavy:      return 2.08
        case .black:      return 2.50
        }
    }

    /// Template `<g>` id suffix used in Apple's SF Symbol template SVG.
    var templateID: String {
        switch self {
        case .ultralight: return "Ultralight"
        case .thin:       return "Thin"
        case .light:      return "Light"
        case .regular:    return "Regular"
        case .medium:     return "Medium"
        case .semibold:   return "Semibold"
        case .bold:       return "Bold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        }
    }
}

/// The 3 SF Symbol scale variants.
enum Scale: String, CaseIterable, Codable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    /// Suffix used in template group ids: -S / -M / -L.
    var templateSuffix: String {
        switch self {
        case .small:  return "S"
        case .medium: return "M"
        case .large:  return "L"
        }
    }

    /// Cap-height ratio. Apple's template centers each row on cap-height anchors;
    /// Small is the reference at 1.0, Medium = 1.272, Large = 1.637.
    var sizeScale: Double {
        switch self {
        case .small:  return 1.0
        case .medium: return 1.272
        case .large:  return 1.637
        }
    }

    /// Y-anchor (baseline) of this row inside the 3300×2200 template canvas.
    /// Measured directly from Apple's template v7.0 export.
    var baselineY: Double {
        switch self {
        case .small:  return 696
        case .medium: return 1126
        case .large:  return 1556
        }
    }

    /// Cap-height line Y in the canvas, used for vertical alignment.
    var capLineY: Double {
        switch self {
        case .small:  return 625.541
        case .medium: return 1055.541
        case .large:  return 1485.541
        }
    }
}
