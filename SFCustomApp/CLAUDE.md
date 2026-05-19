# SF Custom — macOS App

## Mission

Take any SVG → produce an Apple SF Symbol template (9 weights × 3 scales) and an installable .otf icon font. Designed to work hand-in-hand with the Figma plugin in `../sf-custom-plugin/`.

## Approach (the "Custom Symbols way")

Inspired by Custom Symbols.app. Instead of trying to *interpolate paths* between weights — which is fragile and produces ugly results — we:

1. Render the source SVG in a hidden `WKWebView`.
2. Walk every element and ask `getComputedStyle()` for the *real* stroke-width (resolves CSS, inheritance, percentages, `currentColor`, etc.).
3. For each of the 9 SF Symbol weights, clone the SVG and multiply each element's stroke-width by a per-weight scale factor (Ultralight ≈ 0.42×, Regular = 1.0×, Black ≈ 2.5×).
4. Drop the resulting variants into Apple's SF Symbol template SVG at fixed slot coordinates.

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

**Limitation:** The font compiler only handles *filled* paths. The Figma plugin asks Figma to outline strokes on export (`svgOutlineText: true`, `svgSimplifyStroke: true`), so icons coming through the plugin work. SVGs imported by drag-and-drop should have their strokes outlined in advance.

## Plugin bridge API

`LocalServer` listens on 127.0.0.1 (default port 8787):

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/status` | — | `{ ok, iconCount, port }` |
| POST | `/api/icons` | `{ name, svg }` | `{ ok, id, name, codepoint }` |
| OPTIONS | any | — | CORS preflight |

CORS is open (`*`) — the plugin's UI iframe origin isn't predictable.

## What I'd add next

- **Adjustable weight scales** in Settings (per-icon overrides for designs that don't follow a uniform stroke-progression).
- **Variable font output** so a single OTF covers all 9 weights.
- **Multi-icon export** with a sheet picker (pick which icons go in the .otf).
- **Live re-installation** — currently the user must restart Figma to see a recompiled font.
