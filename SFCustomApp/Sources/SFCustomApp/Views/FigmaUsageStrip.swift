import SwiftUI

/// "Use this icon in Figma" helper strip — three click-to-copy chips
/// (symbol character, codepoint, name) plus a one-line instruction.
struct FigmaUsageStrip: View {
    @EnvironmentObject var settings: AppSettings
    var icon: Icon
    @Binding var copiedHint: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use in Figma")
                    .font(.caption.weight(.semibold))
                Text("Set a text layer's font to **\(settings.familyName)** and paste the symbol.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            chip(
                title: "Symbol",
                value: icon.symbolCharacter.isEmpty ? "—" : icon.symbolCharacter,
                monospaced: false,
                isPrimary: true,
                hint: "copied symbol"
            ) {
                CopyAction.symbol(icon)
            }

            chip(
                title: "Codepoint",
                value: icon.codepointString,
                monospaced: true,
                isPrimary: false,
                hint: "copied codepoint"
            ) {
                CopyAction.codepoint(icon)
            }

            chip(
                title: "Name",
                value: icon.name,
                monospaced: true,
                isPrimary: false,
                hint: "copied name"
            ) {
                CopyAction.name(icon)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.02)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .topTrailing) {
            if let hint = copiedHint {
                Text("✓ \(hint)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.9)))
                    .foregroundStyle(.white)
                    .padding(.trailing, 16)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: copiedHint)
    }

    @ViewBuilder
    private func chip(
        title: String,
        value: String,
        monospaced: Bool,
        isPrimary: Bool,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation { copiedHint = hint }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { copiedHint = nil }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Group {
                        if monospaced {
                            Text(value).font(.system(.callout, design: .monospaced))
                        } else {
                            Text(value).font(.system(size: 18, weight: .medium))
                        }
                    }
                    .lineLimit(1)
                }
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Click to copy \(title.lowercased())")
    }
}

#if canImport(AppKit)
import AppKit
#endif
