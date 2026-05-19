# SF Custom — Figma plugin

Minimal companion plugin for the SF Custom macOS app. Captures the selected node as SVG and POSTs it to the local bridge at `http://127.0.0.1:8787`.

## File map

```
sf-custom-plugin/
├── manifest.json        Figma plugin manifest
├── package.json         npm deps (esbuild + @figma/plugin-typings)
├── tsconfig.json        TypeScript config
├── build.mjs            esbuild build script (bundles code.ts and inlines ui.ts into ui.html)
├── src/
│   ├── code.ts          Sandbox bundle — Figma API access, no network
│   ├── ui.html          Single-page UI template (with /*__UI_JS__*/ placeholder)
│   └── ui.ts            UI script — has network, posts to localhost
└── dist/                Build output (gitignored)
    ├── code.js
    └── ui.html
```

## Setup

```bash
cd sf-custom-plugin
npm install
npm run build      # or npm run watch
```

In Figma desktop: **Plugins → Development → Import plugin from manifest…** and select `manifest.json`.

## How it works

1. **code.ts** lives in Figma's QuickJS sandbox. On every selection change it calls `node.exportAsync({ format: "SVG", svgOutlineText: true, svgSimplifyStroke: true })`, then sends the SVG string + a default name to the UI via `postMessage`.
2. **ui.html / ui.ts** runs in an iframe with network access. It renders a live preview, polls `http://127.0.0.1:8787/api/status` every 4s for the bridge status badge, and POSTs to `/api/icons` when the user clicks **Send**.

Stroke outlining is enabled on export so the macOS font compiler — which only handles fills — gets clean filled paths.

## Why a single selection

We intentionally only handle one node at a time. Multi-select would either require batching (which complicates the UI and macOS app library reconciliation) or sequential sends (the user can just do that themselves). Keep it simple.

## Bridge API

Defined in the macOS app — see `../SFCustomApp/CLAUDE.md`. Short version:

- `GET /api/status` → `{ ok, iconCount, port }`
- `POST /api/icons` ← `{ name, svg }` → `{ ok, id, name, codepoint }`
