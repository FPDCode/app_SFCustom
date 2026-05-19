import Foundation

/// All Apple SF Symbol template constants extracted from Template v7.0
/// Based on analysis of pencil_dynamic.svg and pencil_static.svg exports
struct TemplateConfig {

    // MARK: - Canvas

    static let canvasWidth: Double = 3300
    static let canvasHeight: Double = 2200

    // MARK: - Typography Constants

    /// Cap height in SVG units — constant across all scales
    static let capHeight: Double = 70.459

    // MARK: - Scale Baselines

    struct ScaleMetrics {
        let baselineY: Double
        let caplineY: Double
        let referenceWidth: Double   // Regular weight width at this scale
        let referenceHeight: Double  // Regular weight height at this scale
    }

    static let small = ScaleMetrics(
        baselineY: 696.0,
        caplineY: 625.541,
        referenceWidth: 61.96,
        referenceHeight: 61.52
    )

    static let medium = ScaleMetrics(
        baselineY: 1126.0,
        caplineY: 1055.54,
        referenceWidth: 78.83,
        referenceHeight: 78.34
    )

    static let large = ScaleMetrics(
        baselineY: 1556.0,
        caplineY: 1485.54,
        referenceWidth: 101.44,
        referenceHeight: 100.89
    )

    // MARK: - Scale Factors (relative to Small)

    static let scaleFactorMedium: Double = 1.272  // M/S
    static let scaleFactorLarge: Double = 1.637    // L/S

    // MARK: - Scale Position Offsets (relative to Small)

    struct ScaleOffset {
        let dx: Double
        let dy: Double
    }

    static let smallToMediumOffset = ScaleOffset(dx: -10.770, dy: 430.0)
    static let smallToLargeOffset = ScaleOffset(dx: -25.240, dy: 860.0)

    // MARK: - Weight Column Positions

    /// X-origin for each master weight column (at Small scale)
    static let columnOrigins: [WeightLabel: Double] = [
        .ultralight: 520.0,
        .regular: 1410.0,
        .black: 2886.0
    ]

    /// Column spacing between weight columns
    static let columnSpacing: Double = 296.7

    // MARK: - Weight Growth Curve

    /// Width at Small scale for each of the 9 standard weights
    /// Used for interpolation and auto-generation of weight variants
    static let weightWidths: [(weight: WeightLabel, width: Double, advanceWidth: Double?)] = [
        (.ultralight, 60.96, 77.98),
        (.thin,       61.19, nil),
        (.light,      61.63, nil),
        (.regular,    61.96, 78.67),
        (.medium,     64.90, nil),
        (.semibold,   67.15, nil),
        (.bold,       70.12, nil),
        (.heavy,      74.42, nil),
        (.black,      78.27, 94.54),
    ]

    /// Growth factor from Ultralight baseline for each weight
    static let weightGrowthFactors: [WeightLabel: Double] = [
        .ultralight: 1.0,
        .thin:       1.004,   // +0.4%
        .light:      1.011,   // +1.1%
        .regular:    1.016,   // +1.6%
        .medium:     1.065,   // +6.5%
        .semibold:   1.102,   // +10.2%
        .bold:       1.150,   // +15.0%
        .heavy:      1.221,   // +22.1%
        .black:      1.284,   // +28.4%
    ]

    // MARK: - Template Metadata

    static let templateVersion = "Template v7.0"
    static let designVariation = "Dynamic"

    // MARK: - Margin Widths (per weight at Small scale)

    /// Advance widths define the total horizontal space for each weight
    struct MarginSpec {
        let leftMargin: Double
        let rightMargin: Double
        var advanceWidth: Double { rightMargin - leftMargin }
    }

    /// Measured margin positions from the pencil dynamic template
    static let marginSpecs: [WeightLabel: MarginSpec] = [
        .ultralight: MarginSpec(leftMargin: 520.721, rightMargin: 598.702),
        .regular:    MarginSpec(leftMargin: 1410.51, rightMargin: 1489.18),
        .black:      MarginSpec(leftMargin: 2886.13, rightMargin: 2980.67),
    ]
}

// MARK: - Weight Labels

enum WeightLabel: String, CaseIterable, Codable {
    case ultralight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    /// The three masters used in dynamic templates
    static let dynamicMasters: [WeightLabel] = [.ultralight, .regular, .black]
}

// MARK: - Scale Labels

enum ScaleLabel: String, CaseIterable, Codable {
    case small = "S"
    case medium = "M"
    case large = "L"

    var metrics: TemplateConfig.ScaleMetrics {
        switch self {
        case .small:  return TemplateConfig.small
        case .medium: return TemplateConfig.medium
        case .large:  return TemplateConfig.large
        }
    }

    var scaleFactor: Double {
        switch self {
        case .small:  return 1.0
        case .medium: return TemplateConfig.scaleFactorMedium
        case .large:  return TemplateConfig.scaleFactorLarge
        }
    }

    var offset: TemplateConfig.ScaleOffset {
        switch self {
        case .small:  return TemplateConfig.ScaleOffset(dx: 0, dy: 0)
        case .medium: return TemplateConfig.smallToMediumOffset
        case .large:  return TemplateConfig.smallToLargeOffset
        }
    }
}
