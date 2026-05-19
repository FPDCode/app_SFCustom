# SF Custom

Turn any SVG into an Apple SF Symbol template (9 weights × 3 scales) and an installable .otf icon font you can use in Figma, Keynote, Xcode — anywhere.

Two pieces:

| | What it does |
|---|---|
| **[SFCustomApp/](SFCustomApp/)** — macOS app (Swift/SwiftUI) | Imports SVGs, generates 9 weight variants via WebKit, exports SF Symbol template SVGs, compiles a Font Book–installable .otf |
| **[sf-custom-plugin/](sf-custom-plugin/)** — Figma plugin (TypeScript) | One click in Figma sends the selected vector to the desktop app |

## The trick

Rather than synthesize weights by interpolating paths (fragile, ugly), SF Custom mimics the approach proven by [Custom Symbols.app](https://apps.apple.com/nl/app/custom-symbols/id1566662030): render the SVG in a `WKWebView`, ask the browser for each element's computed stroke-width, then clone the SVG and multiply stroke-widths by a per-weight scale. Same source SVG, nine accurate weight variants in milliseconds.

## Quick start

```bash
# 1. Build & run the macOS app
cd SFCustomApp
swift run SFCustomApp

# 2. Build the Figma plugin
cd ../sf-custom-plugin
npm install && npm run build

# 3. In Figma desktop: Plugins → Development → Import plugin from manifest…
#    → select sf-custom-plugin/manifest.json
```

## Requirements

- macOS 14+ (Sonoma)
- Swift 5.9+
- Node 18+ (for the plugin build)
- Python 3 + fontTools, for .otf compilation:
  ```bash
  pip3 install --user fonttools
  ```

## Documentation

- App architecture & API: [SFCustomApp/CLAUDE.md](SFCustomApp/CLAUDE.md)
- Plugin internals: [sf-custom-plugin/CLAUDE.md](sf-custom-plugin/CLAUDE.md)
- Original product spec: [Documentation/PRD_V1/SF-Custom-PRD-v1.md](Documentation/PRD_V1/SF-Custom-PRD-v1.md)

## License

Personal project. Apple SF Symbol template structure © Apple. The bundled template SVG was extracted from Custom Symbols.app (App Store ID 1566662030) by Bret Lester for reference.
