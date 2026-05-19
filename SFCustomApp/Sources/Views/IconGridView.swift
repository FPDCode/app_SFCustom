import SwiftUI
import AppKit

/// SF Symbols-style grid browser for the icon library
/// Shows all icons as a scrollable grid with thumbnails, names, search,
/// and a right-click context menu for copying symbol/name/image
struct IconGridView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedIcon: Icon?

    @State private var searchText = ""
    @State private var gridIconSize: CGFloat = 80
    @State private var displayWeight: WeightLabel = .regular
    @State private var viewMode: ViewMode = .grid
    @State private var isTargeted = false

    enum ViewMode: String, CaseIterable {
        case grid = "square.grid.2x2"
        case list = "list.bullet"
    }

    private var filteredIcons: [Icon] {
        if searchText.isEmpty {
            return appState.library.icons
        }
        return appState.library.search(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            gridToolbar
            Divider()

            // Grid or list
            if filteredIcons.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .grid:
                    gridContent
                case .list:
                    listContent
                }
            }
        }
        .onDrop(of: [.svg, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isTargeted {
                ZStack {
                    Color.blue.opacity(0.05)
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        Text("Drop SVG to import")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Toolbar

    private var gridToolbar: some View {
        HStack(spacing: 12) {
            // Icon count
            HStack(spacing: 4) {
                Text("All")
                    .font(.headline)
                Text("\(appState.library.icons.count) Symbols")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .cornerRadius(6)

            Divider()
                .frame(height: 20)

            // Font name label
            Text(appState.library.fontName)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Weight picker
            Picker("Weight", selection: $displayWeight) {
                ForEach(WeightLabel.dynamicMasters, id: \.self) { weight in
                    Text(weight.rawValue.capitalized).tag(weight)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Divider()
                .frame(height: 20)

            // View mode toggle
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Image(systemName: mode.rawValue)
                        .foregroundColor(viewMode == mode ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Grid size slider
            Slider(value: $gridIconSize, in: 48...140, step: 8)
                .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: gridIconSize + 24), spacing: 8)],
                spacing: 8
            ) {
                ForEach(filteredIcons) { icon in
                    gridCell(for: icon)
                }
            }
            .padding(16)
        }
    }

    private func gridCell(for icon: Icon) -> some View {
        let isSelected = selectedIcon?.id == icon.id
        let pathData = pathForDisplayWeight(icon)

        return VStack(spacing: 4) {
            // Icon thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.controlBackgroundColor))

                IconThumbnail(pathData: pathData, sourceSVG: icon.sourceSVG, size: gridIconSize * 0.65)
                    .foregroundColor(isSelected ? .accentColor : .primary)
            }
            .frame(width: gridIconSize, height: gridIconSize)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )

            // Icon name
            Text(icon.name)
                .font(.system(size: max(9, gridIconSize * 0.11)))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .frame(width: gridIconSize + 16)
        }
        .onTapGesture {
            selectedIcon = icon
        }
        .contextMenu {
            iconContextMenu(for: icon)
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List(filteredIcons, selection: Binding(
            get: { selectedIcon?.id },
            set: { id in
                selectedIcon = appState.library.icons.first { $0.id == id }
            }
        )) { icon in
            listRow(for: icon)
                .contextMenu {
                    iconContextMenu(for: icon)
                }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func listRow(for icon: Icon) -> some View {
        HStack(spacing: 12) {
            IconThumbnail(pathData: pathForDisplayWeight(icon), sourceSVG: icon.sourceSVG, size: 28)
                .frame(width: 32, height: 32)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 1) {
                Text(icon.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text(icon.codepointHex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    if icon.version > 1 {
                        Text("v\(icon.version)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            // Weight mode badge
            weightModeLabel(icon.weightMode)

            // Tags
            if !icon.tags.isEmpty {
                Text(icon.tags.prefix(2).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Context Menu (matches SF Symbols app)

    @ViewBuilder
    private func iconContextMenu(for icon: Icon) -> some View {
        Button {
            copySymbol(icon)
        } label: {
            Label("Copy Symbol", systemImage: "doc.on.doc")
        }

        Button {
            copyName(icon)
        } label: {
            Label("Copy Name", systemImage: "textformat")
        }

        Button {
            copyImage(icon)
        } label: {
            Label("Copy Image", systemImage: "photo")
        }

        Menu("Copy Image As...") {
            Button("SVG") { copySVG(icon) }
            Button("PDF") { copyPDF(icon) }
            Button("PNG (1x)") { copyPNG(icon, scale: 1) }
            Button("PNG (2x)") { copyPNG(icon, scale: 2) }
            Button("PNG (3x)") { copyPNG(icon, scale: 3) }
        }

        Divider()

        Button {
            duplicateIcon(icon)
        } label: {
            Label("Duplicate as Custom Symbol", systemImage: "plus.square.on.square")
        }

        if icon.version > 1 {
            Menu("Restore Version...") {
                ForEach(icon.versionHistory, id: \.version) { snapshot in
                    Button("v\(snapshot.version) — \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))") {
                        restoreVersion(icon: icon, version: snapshot.version)
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            appState.removeIcon(icon)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Copy Actions

    /// Copy the Unicode character to pasteboard (like SF Symbols "Copy Symbol")
    private func copySymbol(_ icon: Icon) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(icon.unicodeCharacter, forType: .string)
        appState.statusMessage = "Copied symbol \(icon.codepointHex)"
    }

    /// Copy the icon's name (like SF Symbols "Copy Name")
    private func copyName(_ icon: Icon) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(icon.name, forType: .string)
        appState.statusMessage = "Copied name \"\(icon.name)\""
    }

    /// Copy icon as image to pasteboard
    private func copyImage(_ icon: Icon) {
        guard let image = renderIconToNSImage(icon, size: 256) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        appState.statusMessage = "Copied image for \(icon.name)"
    }

    /// Copy icon as SVG string
    private func copySVG(_ icon: Icon) {
        let pathData = pathForDisplayWeight(icon)
        let commands = SVGParser.parsePathData(pathData)
        let bbox = SVGParser.boundingBox(of: commands)
        let padding: Double = 4
        let vx = bbox.minX - padding
        let vy = bbox.minY - padding
        let vw = bbox.width + padding * 2
        let vh = bbox.height + padding * 2

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(vx) \(vy) \(vw) \(vh)" width="\(Int(vw))" height="\(Int(vh))">
          <path d="\(pathData)" fill="currentColor"/>
        </svg>
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(svg, forType: .string)
        appState.statusMessage = "Copied SVG for \(icon.name)"
    }

    /// Copy icon as PDF data
    private func copyPDF(_ icon: Icon) {
        // TODO(Cursor): Implement PDF export using CGContext + PDF context
        appState.statusMessage = "PDF export — coming soon"
    }

    /// Copy icon as PNG at given scale
    private func copyPNG(_ icon: Icon, scale: Int) {
        let size = 64 * scale
        guard let image = renderIconToNSImage(icon, size: CGFloat(size)) else { return }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        appState.statusMessage = "Copied PNG (\(scale)x) for \(icon.name)"
    }

    // MARK: - Rendering Helper

    private func renderIconToNSImage(_ icon: Icon, size: CGFloat) -> NSImage? {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let pathData = pathForDisplayWeight(icon)
        let commands = SVGParser.parsePathData(pathData)
        let bbox = SVGParser.boundingBox(of: commands)

        guard bbox.width > 0, bbox.height > 0 else {
            image.unlockFocus()
            return nil
        }

        let scale = min(size / bbox.width, size / bbox.height) * 0.75
        let offsetX = (size - bbox.width * scale) / 2.0 - bbox.minX * scale
        let offsetY = (size - bbox.height * scale) / 2.0 - bbox.minY * scale

        let path = NSBezierPath()
        var curX: CGFloat = 0, curY: CGFloat = 0

        for cmd in commands {
            let p = cmd.parameters.map { CGFloat($0) }
            switch cmd.type {
            case "M":
                if p.count >= 2 {
                    let x = p[0] * scale + offsetX
                    let y = p[1] * scale + offsetY
                    path.move(to: NSPoint(x: x, y: y))
                    curX = p[0]; curY = p[1]
                }
            case "L":
                var i = 0
                while i + 1 < p.count {
                    path.line(to: NSPoint(x: p[i] * scale + offsetX, y: p[i+1] * scale + offsetY))
                    curX = p[i]; curY = p[i+1]
                    i += 2
                }
            case "C":
                var i = 0
                while i + 5 < p.count {
                    path.curve(
                        to: NSPoint(x: p[i+4] * scale + offsetX, y: p[i+5] * scale + offsetY),
                        controlPoint1: NSPoint(x: p[i] * scale + offsetX, y: p[i+1] * scale + offsetY),
                        controlPoint2: NSPoint(x: p[i+2] * scale + offsetX, y: p[i+3] * scale + offsetY)
                    )
                    curX = p[i+4]; curY = p[i+5]
                    i += 6
                }
            case "Z":
                path.close()
            default:
                break
            }
        }

        NSColor.labelColor.setFill()
        path.fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Helpers

    private func pathForDisplayWeight(_ icon: Icon) -> String {
        switch displayWeight {
        case .ultralight: return icon.masters.ultralight
        case .black:      return icon.masters.black
        default:          return icon.masters.regular
        }
    }

    private func weightModeLabel(_ mode: WeightMode) -> some View {
        Group {
            switch mode {
            case .uniform:
                Image(systemName: "equal.circle")
            case .singleGenerate:
                Image(systemName: "wand.and.stars")
            case .fullControl:
                Image(systemName: "slider.horizontal.3")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary)
            Text("No Symbols")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Drag SVG files here, use the Figma plugin,\nor click + to create a new icon.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func duplicateIcon(_ icon: Icon) {
        var copy = Icon(name: "\(icon.name).copy", svgPath: icon.masters.regular)
        copy.masters = icon.masters
        copy.weightMode = icon.weightMode
        copy.tags = icon.tags
        appState.addIcon(copy)
    }

    private func restoreVersion(icon: Icon, version: Int) {
        guard var mutable = appState.library.icons.first(where: { $0.id == icon.id }) else { return }
        mutable.restore(version: version)
        if let index = appState.library.icons.firstIndex(where: { $0.id == icon.id }) {
            appState.library.icons[index] = mutable
            appState.selectedIcon = mutable
            appState.saveLibrary()
            appState.statusMessage = "Restored \(icon.name) to v\(version)"
        }
    }

    // MARK: - Drag & Drop Import

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      url.pathExtension.lowercased() == "svg" else { return }
                Task { @MainActor in
                    importSVG(from: url)
                }
            }
        }
        return true
    }

    private func importSVG(from url: URL) {
        do {
            let svgContent = try String(contentsOf: url, encoding: .utf8)
            let paths = try SVGParser.extractPaths(from: svgContent)
            let mergedPath = SVGParser.mergePaths(paths)
            let name = url.deletingPathExtension().lastPathComponent
            let icon = Icon(name: name, svgPath: mergedPath)
            appState.addIcon(icon)
        } catch {
            appState.statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
