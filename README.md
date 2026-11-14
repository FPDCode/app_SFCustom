# SF Custom

Turn any SVG into an Apple SF Symbol template (9 weights × 3 scales) and an installable .otf icon font you can use in Figma, Keynote, Xcode — anywhere.

| | What it does |
|---|---|
| **[SFCustomApp/](SFCustomApp/)**: macOS app (Swift/SwiftUI) | Imports SVGs, builds SF Symbol templates whose weights interpolate cleanly, checks/fixes templates, exports `.symbolset`, compiles a static or variable .otf |
| **SFCustomApp/Sources/SFCustomEngine**: engine (Swift, no UI) | SVG parsing, width-independent stroke outlining, compatibility checker, template writer. Builds on macOS and Linux |
| **`sfcustom`**: CLI | `export`, `lint`, `preview`, `font` for CI and scripts |
| **[sf-custom-plugin/](sf-custom-plugin/)**: Figma plugin (TypeScript) | One click in Figma sends the selected vector to the desktop app |
| **[sf-custom-mcp/](sf-custom-mcp/)**: MCP server | Lets Claude Desktop / Claude Code (your own Claude account, no API key) control the app |

## The trick

SF Symbols only needs three weights (Ultralight, Regular, Black) and blends the rest, **but only if all three have exactly the same points, order and start points**. That's where hand-made symbols usually break (see the [talk notes](Documentation/Research/Custom-SF-Symbols-Talk-Takeaways.md)).

SF Custom draws the weights from your strokes (default 2 · 7 · 13 units, the talk's recipe) with its own stroke-outliner. Its structure never depends on the width, so the three anchors are compatible by construction. A built-in checker verifies every template (and any template you drew yourself) and auto-fixes start points, part order and direction.

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

# 4. Engine tests (macOS or Linux)
cd ../SFCustomApp && swift test --filter SFCustomEngineTests

# 5. Optional: let Claude control the app (see sf-custom-mcp/README.md)
cd ../sf-custom-mcp && npm install
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
- Claude control (MCP): [sf-custom-mcp/README.md](sf-custom-mcp/README.md)
- Talk takeaways + roadmap: [Documentation/Research/Custom-SF-Symbols-Talk-Takeaways.md](Documentation/Research/Custom-SF-Symbols-Talk-Takeaways.md)
- Original product spec: [Documentation/PRD_V1/SF-Custom-PRD-v1.md](Documentation/PRD_V1/SF-Custom-PRD-v1.md)

## License

Personal project. Apple SF Symbol template structure © Apple. The bundled template SVG was extracted from Custom Symbols.app (App Store ID 1566662030) by Bret Lester for reference.
