# SF Custom — Cursor AI Development Guide

## Project Overview

SF Custom is a macOS app that generates custom SF Symbol template SVGs and compiles icons into an installable .otf font for use in Figma via Font Book. A companion Figma plugin (separate project at `../sf-custom-plugin/`) captures icon paths and sends them to this app via localhost HTTP.

## Tech Stack

- **Language:** Swift 5.9 / SwiftUI
- **Platform:** macOS 14+ (Sonoma)
- **Build:** Swift Package Manager (no Xcode project file — use `swift build` or open `Package.swift` in Xcode)
- **Frameworks:** CoreGraphics, CoreText, Network (NWListener)

## Architecture

```
SFCustomApp/
├── Sources/
│   ├── SFCustomApp.swift          # @main entry point
│   ├── AppState.swift             # @MainActor ObservableObject — central state
│   ├── Models/
│   │   ├── Icon.swift             # Icon, WeightMasters, WeightMode
│   │   ├── IconLibrary.swift      # Library container + persistence
│   │   └── TemplateConfig.swift   # ALL Apple template constants (critical reference)
│   ├── Engine/
│   │   ├── SVGParser.swift        # SVG path parsing, bounding boxes, serialization
│   │   ├── WeightCurve.swift      # Weight interpolation using Apple's growth curve
│   │   ├── MarginCalculator.swift # Template margin guide calculations
│   │   └── PathInterpolator.swift # Positions icons in the 3×3 template grid
│   ├── Services/
│   │   ├── TemplateGenerator.swift # Generates Apple-compliant SF Symbol template SVGs
│   │   ├── FontCompiler.swift      # Compiles icons into .otf font (SCAFFOLD — see below)
│   │   ├── FontBookInstaller.swift # CTFontManager integration for Font Book
│   │   └── LocalServer.swift       # NWListener HTTP server for Figma plugin bridge
│   └── Views/
│       ├── ContentView.swift       # Main layout: grid browser + side inspector panel
│       ├── IconGridView.swift      # ★ SF Symbols-style grid browser with context menus
│       ├── LibraryView.swift       # Legacy sidebar list view (kept for reference)
│       ├── IconEditorView.swift     # Icon property editor (name, path, tags, codepoint)
│       ├── PreviewGrid.swift        # 3×3 weight×scale preview grid
│       ├── WeightModeSelector.swift # Weight mode picker (uniform/single+generate/full control)
│       └── SettingsView.swift       # Server, font, and export settings
└── Tests/
```

## Critical Constants (TemplateConfig.swift)

These values are measured from Apple's official SF Symbol template exports (Template v7.0). Do NOT change them without re-measuring against Apple's templates.

- **Canvas:** 3300×2200 SVG units
- **Cap height:** 70.459 (constant across all scales)
- **Scale factors:** S→M = 1.272×, S→L = 1.637×
- **Scale offsets:** S→M = (dx: −10.770, dy: +430.0), S→L = (dx: −25.240, dy: +860.0)
- **Weight growth curve (from Ultralight baseline):**
  - Regular: +1.6%
  - Black: +28.4%
  - Growth is non-linear — most expansion happens past Regular weight

## What's Scaffolded vs What Needs Implementation

### Working (code is functional):
- ✅ Models (Icon with versioning, IconLibrary, TemplateConfig, WeightMode, IconSnapshot)
- ✅ SVG parsing (extract paths, parse commands, bounding boxes, serialize)
- ✅ Weight curve (scale factors, path scaling, master generation)
- ✅ Margin calculation
- ✅ Path interpolation (grid positioning, scale transforms)
- ✅ Template SVG generation (produces valid Template v7.0 SVG structure)
- ✅ Font Book installer (CTFontManager register/unregister)
- ✅ Local HTTP server (NWListener, JSON API, CORS headers)
- ✅ All SwiftUI views (library, editor, preview, weight selector, settings)
- ✅ SF Symbols-style grid browser (IconGridView) with adaptive grid + list toggle
- ✅ Right-click context menu: Copy Symbol, Copy Name, Copy Image, Copy Image As (SVG/PNG 1-3x)
- ✅ Icon versioning: override with snapshot history, restore previous versions
- ✅ Pasteboard integration: NSPasteboard for symbol/name/image/SVG copy

### SCAFFOLD — Needs Real Implementation:

#### 1. FontCompiler.swift — OTF Binary Generation (P0, BLOCKING)

The current `FontCompiler` writes a placeholder JSON file instead of a real .otf font. This is the **most critical missing piece**.

**Recommended approach:** Use Python `fonttools` via a subprocess:

```swift
// In FontCompiler.swift, replace writeFontFile() with:
func writeFontFile(...) throws {
    // 1. Write glyph SVG paths to a temp directory as individual .svg files
    // 2. Shell out to a Python script that uses fonttools:
    //    - Creates a TTFont with correct metrics (unitsPerEm=1000, ascent=800, descent=-200)
    //    - Adds cmap table mapping codepoints to glyph names
    //    - Converts SVG paths to glyf outlines using fontTools.pens
    //    - Sets name table (font name, family, etc.)
    //    - Writes the .otf file
    // 3. Read the resulting .otf back
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [scriptPath, tempDir, outputURL.path, fontName]
    try process.run()
    process.waitUntilExit()
}
```

**Alternative:** Use `opentype.js` via a Node subprocess, or find a pure Swift OpenType writer library.

**Font metrics to match SF Pro:**
- Units per em: 1000
- Ascent: 800
- Descent: -200
- Cap height: 700 (= 70.459 template units × ~10 scale)
- Line gap: 0

#### 2. Template SVG Validation (P1)

The generated template SVG needs validation against Xcode's expected format. Key things to verify:

- The `<g id="Notes">` group must contain `template-version`, `design-variation`, and `symbol-name` metadata in the exact format Xcode expects
- Margin guide IDs must follow the pattern: `left-margin-{Weight}-{Scale}` and `right-margin-{Weight}-{Scale}`
- Baseline/Capline guide IDs: `Baseline-{S|M|L}`, `Capline-{S|M|L}`
- Test by importing a generated template into Xcode 26+ and checking for validation errors

#### 3. SVG Import Robustness (P1)

The SVG parser handles basic path commands (M, L, C, Q, A, Z) but needs:
- Support for `S` (smooth cubic), `T` (smooth quad) commands
- Handle `transform` attributes on `<g>` and `<path>` elements
- Handle `<circle>`, `<rect>`, `<ellipse>`, `<polygon>` by converting to path data
- Handle nested `<g>` groups with cumulative transforms

#### 4. Drag-and-Drop SVG Import (P1)

Both `IconGridView` and `LibraryView` have drop handlers wired up but need testing. The `NSItemProvider` API for `.svg` UTType may need adjustment — test with actual SVG files dragged from Finder.

#### 5. PDF Export in Copy Image As... (P1)

The "Copy Image As… → PDF" option in the grid's context menu is stubbed. Implement using `CGContext` with a PDF media box to render the icon path into a PDF data blob for the pasteboard.

#### 6. Icon Rendering Quality (P1)

`IconThumbnail` and the NSImage renderer in `IconGridView` handle M/L/C/Z commands but skip S/Q/T/A. For full fidelity, extend the rendering to handle all SVG path commands — or render via a `WKWebView` offscreen approach.

## Icon Grid View (IconGridView.swift)

The primary view is modeled after Apple's SF Symbols app:

- **Grid mode:** Adaptive LazyVGrid with adjustable icon size (48–140px slider)
- **List mode:** Table-style list with alternating row backgrounds
- **Toolbar:** Icon count, search field, font name label, weight picker (UL/Reg/Blk), view mode toggle, size slider
- **Context menu:** Right-click any icon for Copy Symbol (Unicode char), Copy Name, Copy Image, Copy Image As (SVG/PDF/PNG 1x-3x), Duplicate, Restore Version, Delete
- **Drag & drop:** Drop SVG files onto the grid to import them
- **Selection:** Click an icon to open it in the side inspector panel

## Icon Versioning

Each `Icon` has a `version: Int` and `versionHistory: [IconSnapshot]`.

- `icon.override(with: newPath)` — snapshots the current state, bumps version, replaces path data
- `icon.restore(version: 3)` — snapshots current state, bumps version, loads masters from snapshot v3
- The context menu shows "Restore Version…" submenu when `version > 1`
- This enables the design workflow: iterate → override → if the new version doesn't work, restore previous

`IconSnapshot` stores: version number, WeightMasters, WeightMode, savedAt date.

## API Endpoints (LocalServer)

The Figma plugin communicates with these endpoints:

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/api/status` | — | `{ status, version, iconCount }` |
| POST | `/api/icons` | `{ name, svgPath, weightMode, sourceWeight?, tags? }` | `{ success, iconId, name }` |
| GET | `/api/icons` | — | `{ icons: [{ id, name }] }` |
| POST | `/api/export/template` | `{ iconId }` | `{ success, iconName }` |
| POST | `/api/export/font` | — | `{ success, fontPath }` |

All responses include CORS headers (`Access-Control-Allow-Origin: *`).

`weightMode` values: `"uniform"`, `"single"`, `"full"`
`sourceWeight` values (for single mode): `"ultralight"`, `"regular"`, `"black"`

## Running the Project

```bash
cd SFCustomApp
swift build
swift run SFCustomApp
```

Or open `Package.swift` in Xcode and run from there (recommended for SwiftUI previews).

## Testing Priorities

1. **Template generation:** Export a template SVG, import into Xcode, verify it validates
2. **Weight curve:** Compare auto-generated weight variants against Apple's pencil samples (reference files at `../SF Samples/SF Symbol_Template/`)
3. **Font compilation:** Once the real OTF builder is in place, verify the font installs and Figma can access it
4. **Server round-trip:** Start server, POST an icon from curl/Postman, verify it appears in the library

## Reference Materials

- Apple SF Symbol template samples: `../SF Samples/SF Symbol_Template/`
- PRD with full spec: `../../Claude/Projects/SF Custom/SF-Custom-PRD-v1.md`
- Apple HIG Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- SF Symbols: https://developer.apple.com/sf-symbols/
- Custom Symbol Images: https://developer.apple.com/documentation/uikit/creating-custom-symbol-images-for-your-app

## Companion Figma Plugin

The Figma plugin lives at `../sf-custom-plugin/` (to be scaffolded). It's a TypeScript project that:
1. Reads vector paths from selected Figma nodes
2. Shows a weight mode picker and preview
3. POSTs icon data to `http://localhost:8787/api/icons`
4. Shows connection status to the macOS app

See the plugin scaffold for its own README.
