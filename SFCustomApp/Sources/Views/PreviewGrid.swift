import SwiftUI

/// Shows the icon across all 3 master weights and 3 scales in a grid
/// Mimics Apple's SF Symbol template layout for visual verification
struct PreviewGrid: View {
    let icon: Icon

    @State private var showGuides = true
    @State private var previewScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Toggle("Guides", isOn: $showGuides)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            // 3×3 Grid: Weights (columns) × Scales (rows)
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("")
                            .frame(width: 40)
                        ForEach(WeightLabel.dynamicMasters, id: \.self) { weight in
                            Text(weight.rawValue.capitalized)
                                .font(.caption.bold())
                                .frame(width: 120)
                        }
                    }
                    .padding(.bottom, 4)

                    // Grid rows
                    ForEach(ScaleLabel.allCases, id: \.self) { scale in
                        HStack(spacing: 0) {
                            // Row label
                            Text(scale.rawValue)
                                .font(.caption.bold())
                                .frame(width: 40)

                            ForEach(WeightLabel.dynamicMasters, id: \.self) { weight in
                                previewCell(weight: weight, scale: scale)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Size comparison
            sizeComparison
        }
        .padding()
    }

    // MARK: - Preview Cell

    private func previewCell(weight: WeightLabel, scale: ScaleLabel) -> some View {
        let pathData: String = {
            switch weight {
            case .ultralight: return icon.masters.ultralight
            case .regular:    return icon.masters.regular
            case .black:      return icon.masters.black
            default:          return icon.masters.regular
            }
        }()

        let cellSize: CGFloat = {
            switch scale {
            case .small:  return 60
            case .medium: return 76
            case .large:  return 98
            }
        }()

        return ZStack {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.controlBackgroundColor))

            // Guide lines
            if showGuides {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.blue.opacity(0.2))
                        .frame(height: 0.5)
                        .offset(y: -cellSize * 0.15) // Baseline approximation
                }
            }

            // Icon — pass the full sourceSVG so SwiftDraw renders every shape
            // (including outlined-stroke wedges/rings), not just `masters.regular`.
            IconThumbnail(pathData: pathData, sourceSVG: icon.sourceSVG, size: cellSize * 0.7)
        }
        .frame(width: 120, height: cellSize + 20)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.quaternary)
        )
    }

    // MARK: - Size Comparison

    private var sizeComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Metrics")
                .font(.subheadline.bold())

            HStack(spacing: 20) {
                metricLabel("UL Width", value: widthForWeight(.ultralight))
                metricLabel("Reg Width", value: widthForWeight(.regular))
                metricLabel("Blk Width", value: widthForWeight(.black))
            }

            // Growth indicator
            let growth = growthPercentage()
            Text("Growth UL→Blk: \(String(format: "%.1f", growth))%")
                .font(.caption)
                .foregroundColor(abs(growth - 28.4) < 5 ? .green : .orange)

            Text(abs(growth - 28.4) < 5 ? "Within Apple's reference range" : "Check: Apple's reference is ~28.4%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func metricLabel(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func widthForWeight(_ weight: WeightLabel) -> Double {
        let pathData: String
        switch weight {
        case .ultralight: pathData = icon.masters.ultralight
        case .regular:    pathData = icon.masters.regular
        case .black:      pathData = icon.masters.black
        default:          pathData = icon.masters.regular
        }
        let commands = SVGParser.parsePathData(pathData)
        let bbox = SVGParser.boundingBox(of: commands)
        return bbox.width
    }

    private func growthPercentage() -> Double {
        let ulWidth = widthForWeight(.ultralight)
        guard ulWidth > 0 else { return 0 }
        let blkWidth = widthForWeight(.black)
        return ((blkWidth - ulWidth) / ulWidth) * 100.0
    }
}
