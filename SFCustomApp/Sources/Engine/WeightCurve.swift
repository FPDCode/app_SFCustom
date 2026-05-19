import Foundation

/// Handles weight interpolation and auto-generation of weight variants
/// Based on Apple's measured non-linear weight growth curve
struct WeightCurve {

    // MARK: - Growth Factor Lookup

    /// Get the scale factor to transform from one weight to another
    /// For example, Regular → Black means scaling width by ~1.263×
    static func scaleFactor(from source: WeightLabel, to target: WeightLabel) -> Double {
        guard let sourceGrowth = TemplateConfig.weightGrowthFactors[source],
              let targetGrowth = TemplateConfig.weightGrowthFactors[target] else {
            return 1.0
        }
        return targetGrowth / sourceGrowth
    }

    // MARK: - Path Scaling

    /// Scale an SVG path uniformly (same factor for X and Y)
    /// This is the simplest approach — uniform scaling preserves proportions
    static func scalePath(_ pathData: String, factor: Double) -> String {
        var commands = SVGParser.parsePathData(pathData)
        commands = commands.map { cmd in
            var scaled = cmd
            scaled.parameters = cmd.parameters.map { $0 * factor }
            // Handle arc commands specially — flags and radii need different treatment
            if cmd.type == "A" {
                scaled.parameters = scaleArcParameters(cmd.parameters, factor: factor)
            }
            return scaled
        }
        return SVGParser.serializePathData(commands)
    }

    /// Scale a path with different X and Y factors (for weight variation)
    /// Weight changes primarily affect the horizontal axis (stroke width)
    static func scalePath(_ pathData: String, factorX: Double, factorY: Double) -> String {
        var commands = SVGParser.parsePathData(pathData)
        commands = commands.map { cmd in
            var scaled = cmd
            switch cmd.type {
            case "M", "L", "T":
                // Scale (x, y) pairs
                var i = 0
                while i + 1 < scaled.parameters.count {
                    scaled.parameters[i] *= factorX
                    scaled.parameters[i+1] *= factorY
                    i += 2
                }
            case "H":
                scaled.parameters = cmd.parameters.map { $0 * factorX }
            case "V":
                scaled.parameters = cmd.parameters.map { $0 * factorY }
            case "C":
                // Cubic: (x1,y1, x2,y2, x,y)
                var i = 0
                while i + 5 < scaled.parameters.count {
                    scaled.parameters[i] *= factorX
                    scaled.parameters[i+1] *= factorY
                    scaled.parameters[i+2] *= factorX
                    scaled.parameters[i+3] *= factorY
                    scaled.parameters[i+4] *= factorX
                    scaled.parameters[i+5] *= factorY
                    i += 6
                }
            case "Q":
                // Quadratic: (x1,y1, x,y)
                var i = 0
                while i + 3 < scaled.parameters.count {
                    scaled.parameters[i] *= factorX
                    scaled.parameters[i+1] *= factorY
                    scaled.parameters[i+2] *= factorX
                    scaled.parameters[i+3] *= factorY
                    i += 4
                }
            case "A":
                scaled.parameters = scaleArcParametersXY(cmd.parameters, fx: factorX, fy: factorY)
            default:
                break
            }
            return scaled
        }
        return SVGParser.serializePathData(commands)
    }

    // MARK: - Weight Variant Generation

    /// Generate all 3 master weight paths from a single source path
    /// Returns (ultralight, regular, black) path data
    static func generateMasters(
        from sourcePath: String,
        sourceWeight: WeightMasters.SourceWeight
    ) -> (ultralight: String, regular: String, black: String) {

        let sourceLabel: WeightLabel = {
            switch sourceWeight {
            case .ultralight: return .ultralight
            case .regular: return .regular
            case .black: return .black
            }
        }()

        let ultralightPath: String
        let regularPath: String
        let blackPath: String

        switch sourceWeight {
        case .ultralight:
            ultralightPath = sourcePath
            regularPath = scalePath(sourcePath, factor: scaleFactor(from: .ultralight, to: .regular))
            blackPath = scalePath(sourcePath, factor: scaleFactor(from: .ultralight, to: .black))
        case .regular:
            ultralightPath = scalePath(sourcePath, factor: scaleFactor(from: .regular, to: .ultralight))
            regularPath = sourcePath
            blackPath = scalePath(sourcePath, factor: scaleFactor(from: .regular, to: .black))
        case .black:
            ultralightPath = scalePath(sourcePath, factor: scaleFactor(from: .black, to: .ultralight))
            regularPath = scalePath(sourcePath, factor: scaleFactor(from: .black, to: .regular))
            blackPath = sourcePath
        }

        return (ultralightPath, regularPath, blackPath)
    }

    // MARK: - Stroke Expansion (Advanced)

    /// Expand/contract stroke width to simulate weight change
    /// This is more optically accurate than uniform scaling for outlined icons
    /// Uses the measured width delta between weights
    static func strokeDelta(from source: WeightLabel, to target: WeightLabel) -> Double {
        guard let sourceWidth = TemplateConfig.weightWidths.first(where: { $0.weight == source })?.width,
              let targetWidth = TemplateConfig.weightWidths.first(where: { $0.weight == target })?.width else {
            return 0
        }
        return targetWidth - sourceWidth
    }

    // MARK: - Arc Parameter Helpers

    private static func scaleArcParameters(_ params: [Double], factor: Double) -> [Double] {
        // Arc: (rx, ry, x-rotation, large-arc-flag, sweep-flag, x, y)
        guard params.count >= 7 else { return params }
        var result = params
        // Scale radii and endpoint
        result[0] *= factor  // rx
        result[1] *= factor  // ry
        // x-rotation stays the same (index 2)
        // flags stay the same (indices 3, 4)
        result[5] *= factor  // x
        result[6] *= factor  // y
        return result
    }

    private static func scaleArcParametersXY(_ params: [Double], fx: Double, fy: Double) -> [Double] {
        guard params.count >= 7 else { return params }
        var result = params
        result[0] *= fx  // rx
        result[1] *= fy  // ry
        result[5] *= fx  // x
        result[6] *= fy  // y
        return result
    }
}
