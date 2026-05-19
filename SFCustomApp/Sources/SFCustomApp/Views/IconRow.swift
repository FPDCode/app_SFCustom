import SwiftUI

struct IconRow: View {
    var icon: Icon

    var body: some View {
        HStack(spacing: 10) {
            SVGThumbnail(svg: icon.sourceSVG)
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(icon.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(String(format: "U+%04X", icon.codepoint))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

#if canImport(AppKit)
import AppKit
#endif
