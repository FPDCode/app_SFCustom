import Foundation

/// Transforms and positions SVG paths within the SF Symbol template grid
/// Handles scaling, centering, and placement of icons in the 3×3 grid
struct PathInterpolator {

    /// Position an icon path within a specific cell of the template grid
    /// - Parameters:
    ///   - pathData: Original SVG path data (assumed to be in a normalized coordinate space)
    ///   - weight: Target weight column
    ///   - scale: Target scale row
    ///   - designHeight: The height of the icon in its design space (used for normalization)
    /// - Returns: Transformed SVG path data positioned in the template grid
    static func positionInGrid(
        pathData: String,
        weight: WeightLabel,
        scale: ScaleLabel,
        designHeight: Double = 100.0
    ) -> String {
        let metrics = scale.metrics
        let offset = scale.offset

        // Target height = cap height scaled for the target scale
        let targetHeight = TemplateConfig.capHeight * scale.scaleFactor

        // Scale factor to fit the icon within the target cell
        let normalizeScale = targetHeight / designHeight

        // Get column origin for this weight
        guard let columnX = TemplateConfig.columnOrigins[weight] else {
            return pathData
        }

        // Parse and transform the path
        var commands = SVGParser.parsePathData(pathData)
        let bbox = SVGParser.boundingBox(of: commands)

        // Calculate translation to center the icon in its cell
        let scaledWidth = bbox.width * normalizeScale
        let scaledHeight = bbox.height * normalizeScale

        // Target position: centered in column, sitting on baseline
        let targetCenterX = columnX + offset.dx + (TemplateConfig.columnSpacing / 2.0)
        let targetBaselineY = metrics.baselineY

        // Translation: move from bbox origin to target position
        let translateX = targetCenterX - (bbox.centerX * normalizeScale) - (scaledWidth / 2.0) + (scaledWidth / 2.0)
        let translateY = targetBaselineY - (bbox.maxY * normalizeScale)

        // Apply scale + translate to all coordinates
        commands = transformCommands(
            commands,
            scaleX: normalizeScale,
            scaleY: normalizeScale,
            translateX: translateX - (bbox.minX * normalizeScale),
            translateY: translateY
        )

        return SVGParser.serializePathData(commands)
    }

    /// Scale an icon path to a target scale (S/M/L) from its Small-scale version
    static func scaleToTarget(
        smallScalePath: String,
        targetScale: ScaleLabel
    ) -> String {
        if targetScale == .small { return smallScalePath }

        let factor = targetScale.scaleFactor
        let offset = targetScale.offset

        var commands = SVGParser.parsePathData(smallScalePath)
        commands = transformCommands(
            commands,
            scaleX: factor,
            scaleY: factor,
            translateX: offset.dx,
            translateY: offset.dy
        )

        return SVGParser.serializePathData(commands)
    }

    // MARK: - Path Transform

    /// Apply a scale + translate transformation to path commands
    private static func transformCommands(
        _ commands: [SVGParser.PathCommand],
        scaleX: Double,
        scaleY: Double,
        translateX: Double,
        translateY: Double
    ) -> [SVGParser.PathCommand] {
        commands.map { cmd in
            var transformed = cmd

            // For relative commands, only scale (translation doesn't apply)
            let tx = cmd.isRelative ? 0.0 : translateX
            let ty = cmd.isRelative ? 0.0 : translateY

            switch cmd.type {
            case "M", "L", "T":
                var i = 0
                while i + 1 < transformed.parameters.count {
                    transformed.parameters[i] = cmd.parameters[i] * scaleX + tx
                    transformed.parameters[i+1] = cmd.parameters[i+1] * scaleY + ty
                    i += 2
                }
            case "H":
                transformed.parameters = cmd.parameters.map { $0 * scaleX + tx }
            case "V":
                transformed.parameters = cmd.parameters.map { $0 * scaleY + ty }
            case "C":
                var i = 0
                while i + 5 < transformed.parameters.count {
                    transformed.parameters[i] = cmd.parameters[i] * scaleX + tx
                    transformed.parameters[i+1] = cmd.parameters[i+1] * scaleY + ty
                    transformed.parameters[i+2] = cmd.parameters[i+2] * scaleX + tx
                    transformed.parameters[i+3] = cmd.parameters[i+3] * scaleY + ty
                    transformed.parameters[i+4] = cmd.parameters[i+4] * scaleX + tx
                    transformed.parameters[i+5] = cmd.parameters[i+5] * scaleY + ty
                    i += 6
                }
            case "Q":
                var i = 0
                while i + 3 < transformed.parameters.count {
                    transformed.parameters[i] = cmd.parameters[i] * scaleX + tx
                    transformed.parameters[i+1] = cmd.parameters[i+1] * scaleY + ty
                    transformed.parameters[i+2] = cmd.parameters[i+2] * scaleX + tx
                    transformed.parameters[i+3] = cmd.parameters[i+3] * scaleY + ty
                    i += 4
                }
            case "A":
                if transformed.parameters.count >= 7 {
                    transformed.parameters[0] *= scaleX  // rx
                    transformed.parameters[1] *= scaleY  // ry
                    transformed.parameters[5] = cmd.parameters[5] * scaleX + tx  // x
                    transformed.parameters[6] = cmd.parameters[6] * scaleY + ty  // y
                }
            default:
                break
            }

            return transformed
        }
    }
}
