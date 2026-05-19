import SwiftUI

struct WelcomeView: View {
    var onImport: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "scribble.variable")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)

            Text("SF Custom")
                .font(.largeTitle.weight(.semibold))
            Text("Turn your SVGs into SF Symbol templates and an installable font.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 12) {
                Row(num: 1, text: "Drop an SVG (or import from Figma).")
                Row(num: 2, text: "Preview live across 9 weights × 3 scales.")
                Row(num: 3, text: "Export the template SVG or compile an .otf font.")
            }
            .padding(.top, 12)

            Button(action: onImport) {
                Label("Import SVG…", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private struct Row: View {
        var num: Int
        var text: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(num)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                Text(text)
                    .font(.body)
            }
        }
    }
}

#if canImport(AppKit)
import AppKit
#endif
