# SF Custom Figma Plugin — Cursor AI Development Guide

## Overview

Figma plugin that captures icon vector paths from the canvas and sends them to the SF Custom macOS app (running on localhost:8787) for SF Symbol template generation and font compilation.

## Tech Stack

- **Language:** TypeScript
- **Build:** esbuild (fast, single-file bundle)
- **Platform:** Figma Plugin API v1
- **UI:** Vanilla HTML/CSS (no framework — keeps the plugin lightweight)

## File Structure

```
sf-custom-plugin/
├── manifest.json          # Figma plugin manifest
├── package.json           # npm dependencies and build scripts
├── tsconfig.json          # TypeScript config
├── src/
│   ├── code.ts            # Plugin sandbox (Figma API access, vector extraction)
│   ├── bridge.ts          # HTTP client for macOS app communication
│   └── ui/
│       └── ui.html        # Plugin UI (weight selector, preview, connection status)
└── dist/                  # Build output (gitignored)
    ├── code.js
    └── ui.html
```

## Setup

```bash
npm install
npm run build
```

Then in Figma: Plugins → Development → Import plugin from manifest → select `manifest.json`.

## How It Works

1. **code.ts** runs in Figma's sandbox — has access to the Figma API but NOT the network
2. **ui.html** runs in an iframe — has network access (for localhost fetch) but NOT Figma API access
3. Communication between them uses `postMessage`

Flow:
- User selects a vector node → code.ts exports it as SVG → extracts path data
- UI shows the captured path with weight mode selection
- User clicks "Send to SF Custom" → UI fetches `POST /api/icons` on localhost:8787
- macOS app receives the icon, generates template + font

## What Needs Implementation

### 1. Build Pipeline (P0)
The `bridge.ts` module is currently not imported in `ui.html` because the UI uses inline scripts. Either:
- Bundle bridge.ts into ui.html using esbuild's `--bundle` with HTML handling
- Or inline the fetch calls directly in the HTML (current approach — simpler)

### 2. Preview Panel (P1)
Add a lightweight SVG preview showing the captured icon at all 3 weight sizes. The preview should render the raw SVG path in 3 cells (Ultralight, Regular, Black) before sending.

### 3. Component Instance Support (P1)
Currently exports any node as SVG. For component instances, consider:
- Resolving to the main component first
- Flattening all layers into a single outlined path
- Handling boolean operations correctly

### 4. Direct SVG Download (P1)
Add a "Download Template" button that generates the SF Symbol template SVG directly in the plugin without needing the macOS app. Use the template constants from the macOS app's `TemplateConfig.swift` (replicate in TypeScript).

## API Contract with macOS App

See the macOS app's CLAUDE.md for full API documentation. Key endpoint:

```
POST http://localhost:8787/api/icons
Content-Type: application/json

{
  "name": "radar",
  "svgPath": "M128 0 C198.7 0 256 57.3...",
  "weightMode": "uniform" | "single" | "full",
  "sourceWeight": "regular",  // only for "single" mode
  "tags": ["navigation", "system"]
}
```
