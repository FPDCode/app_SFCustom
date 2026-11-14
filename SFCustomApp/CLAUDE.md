# SF Custom — macOS App

## Mission

Take any SVG → produce an Apple SF Symbol template (9 weights × 3 scales) and an installable .otf icon font. Designed to work hand-in-hand with the Figma plugin in `../sf-custom-plugin/`.

## Approach (the "Custom Symbols way")

Inspired by Custom Symbols.app. Instead of trying to *interpolate paths* between weights — which is fragile and produces ugly results — we:

1. Render the source SVG in a hidden `WKWebView`.
2. Walk every element and ask `getComputedStyle()` for the *real* stroke-width (resolves CSS, inheritance, percentages, `currentColor`, etc.).
3. Hand the baked SVG to `SFCustomEngine`, which outlines strokes at the ladder widths (default 2 · 7 · 13 template units) with a stroker that keeps the point structure identical across Ultralight / Regular / Black.
4. Write Apple's Template v7 with three filled, point-compatible anchors. Xcode interpolates the other weights.

This means:
- The visual weight progression looks correct out of the box for stroked icons.
- No path interpolation, no glyph morphing, no Apple-specific weight curve.
- The user keeps full control — what they drew is what gets shipped.

## Architecture

```
SFCustomApp/
├── Package.swift                      Swift Package Manager target
└── Sources/SFCustomApp/
    ├── SFCustomApp.swift              @main entry
    ├── AppSettings.swift              @AppStorage-backed prefs
    ├── Models/
    │   ├── Weight.swift               9 SF weights + stroke scales
    │   ├── Icon.swift                 One icon (id, name, source SVG, codepoint)
    │   └── IconLibrary.swift          Persisted to ~/Library/Application Support/SF Custom/
    ├── Engine/
    │   ├── StrokeSnooper.swift        ★ WKWebView + JS that scales stroke-widths
    │   └── TemplateGenerator.swift    Fills the 27 (9×3) template slots
    ├── Services/
    │   ├── FontCompiler.swift         Subprocesses Python + fontTools
    │   ├── FontBookInstaller.swift    CTFontManager register/unregister
    │   └── LocalServer.swift          Network.framework HTTP server for the plugin
    ├── Views/
    │   ├── ContentView.swift          NavigationSplitView shell
    │   ├── WelcomeView.swift          Empty-state hero
    │   ├── IconRow.swift              Sidebar row
    │   ├── IconDetailView.swift       9×3 live preview grid
    │   ├── SVGWebView.swift           NSViewRepresentable WKWebView renderer
    │   ├── CompileFontButton.swift    Toolbar action with diagnostics alerts
    │   ├── ServerStatusBadge.swift    Sidebar indicator + toggle
    │   ├── SearchField.swift          Sidebar search
    │   └── SettingsView.swift         Settings window (3 tabs)
    └── Resources/
        ├── sf-symbol-template.svg     Extracted from Custom Symbols.app (Template v2.0)
        ├── sf-symbol-preview-template.svg
        └── build_font.py              Python fontTools script (subprocessed)
```

## SFCustomEngine (UI-free library target)

`Sources/SFCustomEngine/` holds all symbol logic. It has no AppKit, SwiftUI or WebKit, so it builds and tests on Linux/CI. Background: `../Documentation/Research/Custom-SF-Symbols-Talk-Takeaways.md`.

| File | Role |
|---|---|
| `Geometry/PathModel.swift` | `Point`, `Segment` (always cubic), `Subpath`, `PathModel.signature()`, tight bounds |
| `Geometry/SVGPathParser.swift` | `d` → PathModel (all commands, arcs → cubics; `keepDegenerate` for templates) |
| `Geometry/SVGPathWriter.swift` | PathModel → `d` (absolute `M/C/Z` only) |
| `Geometry/SVGShapeReader.swift` | SVG doc → flattened shapes (transforms, styles, fill-rule, `insideElementWithID:`) |
| `Outline/CompatibleStroker.swift` | ★ Stroke → fill whose **structure never depends on width** |
| `Symbol/SymbolOutliner.swift` | Fills + outlined strokes → one anchor; winding plan so overlaps union and holes stay holes |
| `Symbol/StrokeLadder.swift` | Ladder presets (talk 2·7·13, legacy, custom), `AnchorWeight`, `AnchorMargins` |
| `Symbol/SymbolTemplateBuilder.swift` | Source SVG → `SymbolTemplate` (sizing, Regular-stroke normalisation, margins, mode) + Template v7 writer |
| `Symbol/SymbolInterpolator.swift` | Point-for-point blending (the 9 weights, the scrubber) |
| `Symbol/SymbolPreviewRenderer.swift` | Preview SVGs: per anchor, interpolated, onion skin |
| `Lint/CompatibilityChecker.swift` | Talk pitfalls → report (ok / fixable / broken), `CompatibilityFixer`, template-file lint/fix |
| `Export/SymbolsetExporter.swift` | `.symbolset` / `.xcassets`, `HandoffSnippet`, `FontSpec` (font masters) |

**The invariant:** `CompatibleStroker.outline(p, width: w).signature()` is identical for every `w`. Never add a branch whose *structural* outcome (number of segments or contours) depends on the width. Only coordinates may. Zero-length segments are deliberate (connectors, unlimited caps). Keep them, and read templates with `keepDegenerate: true`.

**App wiring:** `Engine/TemplateGenerator.swift` = WebKit CSS bake (`StrokeSnooper`, scale 1.0) → `SymbolTemplateBuilder`. Options come from `SymbolSettings` (UserDefaults, see `AppSettings.swift`) plus the per-icon `symbolMode` / `margins`.

**CLI:** `swift run sfcustom export|lint|preview|font …` (see `Sources/sfcustom/main.swift`).

**Assistant control:** `Services/ControlAPI.swift` adds `/api/control/*` to the bridge (token in `~/Library/Application Support/SF Custom/control-token`, header `X-SFCustom-Token`). The MCP server in `../sf-custom-mcp/` exposes it to Claude Desktop / Claude Code.

Tests: `swift test --filter SFCustomEngineTests` (32 tests, including Apple's sample templates and every talk pitfall).

## Build & run

```bash
cd SFCustomApp
swift build
swift run SFCustomApp
```

Or open `Package.swift` in Xcode.

## Critical numbers

Measured directly from Apple's pencil_dynamic.svg (Template v7.0):

| Setting | Value |
|---|---|
| Canvas | 3300 × 2200 |
| Cap height | 70.459 units |
| Column X centers | Ultralight 559.711 … Black 2933.40 (step 296.711) |
| Row baselines | Small 696, Medium 1126, Large 1556 |
| Row cap-line offset | baseline − 70.459 |
| Scale-up factor | S = 1.0, M = 1.272, L = 1.637 |
| Target icon height (S) | 140 units (≈ 2× cap height) |

The 9 weight stroke scales live in `Models/Weight.swift` as `Weight.strokeScale`.

## Font compilation

`FontCompiler` shells out to `Resources/build_font.py` via Python 3 + fontTools. It searches `/opt/homebrew/bin/python3`, `/usr/local/bin/python3`, `/usr/bin/python3` (in that order) and falls back to `$PATH`. If `fonttools` isn't installed, the UI surfaces a one-line `pip3 install --user fonttools` instruction.

Glyphs use:
- units per em: 1000
- ascent: 800, descent: -200
- One glyph per icon, mapped to a Private Use Area codepoint starting at U+E000

Glyph outlines come from the engine (strokes are outlined), so stroked icons work in the font. With Settings → Font → Variable, `build_font.py` builds one CFF2 variable font (wght 100–900, 9 named instances) from the three compatible anchors.

## Plugin bridge API

`LocalServer` listens on 127.0.0.1 (default port 8787):

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/status` | — | `{ ok, iconCount, port }` |
| POST | `/api/icons` | `{ name, svg }` | `{ ok, id, name, codepoint }` |
| OPTIONS | any | — | CORS preflight |

CORS is open (`*`) — the plugin's UI iframe origin isn't predictable.

## What I'd add next

- Per-icon stroke-ladder overrides.
- Drag handles for margins directly on the preview (currently a popover).
- **Multi-icon export** with a sheet picker (pick which icons go in the .otf).
- **Live re-installation** — currently the user must restart Figma to see a recompiled font.
