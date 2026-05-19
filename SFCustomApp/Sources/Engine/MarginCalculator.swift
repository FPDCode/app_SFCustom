import Foundation

/// Calculates margin positions for SF Symbol template guide lines
/// Margins define the advance width — horizontal space each glyph occupies
struct MarginCalculator {

    /// Margin positions for one weight at one scale
    struct Margins {
        let leftMargin: Double
        let rightMargin: Double
        var advanceWidth: Double { rightMargin - leftMargin }
    }

    // MARK: - Margin Calculation

    /// Calculate margins for a given weight and scale, based on the icon's bounding box
    /// The margins define the horizontal extent of the glyph cell
    static func margins(
        for pathData: String,
        weight: WeightLabel,
        scale: ScaleLabel,
        columnOrigin: Double
    ) -> Margins {
        let commands = SVGParser.parsePathData(pathData)
        let bbox = SVGParser.boundingBox(of: commands)

        // Add standard padding around the icon (proportional to scale)
        let padding = 8.0 * scale.scaleFactor

        // Position margins relative to the column origin
        let leftMargin = columnOrigin + bbox.minX - padding
        let rightMargin = columnOrigin + bbox.maxX + padding

        return Margins(leftMargin: leftMargin, rightMargin: rightMargin)
    }

    /// Calculate margins from the measured Apple reference data
    /// Used when the icon's actual path data is positioned in the template grid
    static func referenceMargins(
        for weight: WeightLabel,
        scale: ScaleLabel
    ) -> Margins? {
        guard let baseSpec = TemplateConfig.marginSpecs[weight] else {
            return nil
        }

        // Scale the margins for Medium and Large scales
        let offset = scale.offset
        let factor = scale.scaleFactor

        // The base margins are at Small scale — scale them
        let centerX = (baseSpec.leftMargin + baseSpec.rightMargin) / 2.0
        let halfWidth = baseSpec.advanceWidth / 2.0 * factor

        let scaledLeft = centerX + offset.dx - halfWidth
        let scaledRight = centerX + offset.dx + halfWidth

        return Margins(leftMargin: scaledLeft, rightMargin: scaledRight)
    }

    /// Calculate margins for a custom icon placed in the template
    /// Takes the icon's bounding box within its design space and maps it to template coordinates
    static func iconMargins(
        iconBBox: SVGParser.BoundingBox,
        weight: WeightLabel,
        scale: ScaleLabel
    ) -> Margins {
        guard let columnOrigin = TemplateConfig.columnOrigins[weight] else {
            // Fallback: use reference margins
            return referenceMargins(for: weight, scale: scale) ?? Margins(leftMargin: 0, rightMargin: 100)
        }

        let offset = scale.offset
        let factor = scale.scaleFactor

        // Scale the icon bbox to the target scale
        let scaledWidth = iconBBox.width * factor
        let padding = 8.0 * factor

        // Center the margins on the column, offset by scale
        let center = columnOrigin + offset.dx + (TemplateConfig.columnSpacing / 2.0)
        let leftMargin = center - (scaledWidth / 2.0) - padding
        let rightMargin = center + (scaledWidth / 2.0) + padding

        return Margins(leftMargin: leftMargin, rightMargin: rightMargin)
    }
}
