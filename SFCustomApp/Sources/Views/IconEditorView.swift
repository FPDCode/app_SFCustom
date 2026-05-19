import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Detail view for editing a single icon's properties and SVG path data
struct IconEditorView: View {
    @Binding var icon: Icon
    @EnvironmentObject var appState: AppState
    @State private var rawPathText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Name & metadata
                metadataSection

                Divider()

                // Weight mode selector
                WeightModeSelector(
                    weightMode: $icon.weightMode,
                    masters: $icon.masters,
                    onGenerate: generateWeights,
                    onExportTemplate: exportTemplate
                )

                Divider()

                // SVG path editor
                pathEditorSection

                Divider()

                // Tags
                tagsSection

                Divider()

                // Unicode codepoint
                codepointSection
            }
            .padding(20)
        }
        .onAppear {
            rawPathText = icon.masters.regular
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon Details")
                .font(.headline)

            HStack {
                TextField("Icon Name", text: $icon.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                // Large thumbnail
                IconThumbnail(icon: icon, size: 64)
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )
            }

            HStack(spacing: 16) {
                Label("Created: \(icon.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                Label("Updated: \(icon.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Path Editor

    private var pathEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SVG Path Data")
                    .font(.headline)
                Spacer()
                Button("Apply") {
                    icon.masters.regular = rawPathText
                    icon.updatedAt = Date()

                    // Re-generate other weights if in uniform or single mode
                    if icon.weightMode == .uniform {
                        icon.masters.ultralight = rawPathText
                        icon.masters.black = rawPathText
                    }
                }
                .buttonStyle(.bordered)
                .disabled(rawPathText == icon.masters.regular)
            }

            TextEditor(text: $rawPathText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 160)
                .border(.quaternary)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            HStack {
                ForEach(icon.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption)
                        Button {
                            icon.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(4)
                }

                AddTagButton { newTag in
                    if !icon.tags.contains(newTag) {
                        icon.tags.append(newTag)
                    }
                }
            }
        }
    }

    // MARK: - Unicode Codepoint

    private var codepointSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unicode Codepoint")
                .font(.headline)

            HStack {
                Text("U+\(String(icon.unicodeCodepoint, radix: 16, uppercase: true))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("(Private Use Area)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Weight Generation

    private func generateWeights() {
        guard case .singleGenerate(let sourceWeight) = icon.weightMode else { return }

        let (ul, reg, blk) = WeightCurve.generateMasters(
            from: icon.masters.regular,
            sourceWeight: sourceWeight
        )

        icon.masters.ultralight = ul
        icon.masters.regular = reg
        icon.masters.black = blk
        icon.updatedAt = Date()
    }

    // MARK: - Template Export

    private func exportTemplate() {
        do {
            let data = try appState.exportTemplate(for: icon)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.svg]
            panel.nameFieldStringValue = "\(icon.name)_dynamic.svg"
            panel.canCreateDirectories = true
            panel.title = "Export SF Symbol Template"

            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                appState.statusMessage = "Template exported: \(url.lastPathComponent)"
            }
        } catch {
            appState.statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Add Tag Button

struct AddTagButton: View {
    let onAdd: (String) -> Void
    @State private var isEditing = false
    @State private var newTag = ""

    var body: some View {
        if isEditing {
            HStack(spacing: 4) {
                TextField("Tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit {
                        if !newTag.isEmpty {
                            onAdd(newTag)
                            newTag = ""
                            isEditing = false
                        }
                    }
                Button {
                    isEditing = false
                    newTag = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                isEditing = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }
}
