# SF Custom — Product Requirements Document

**Author:** Frans — Impala Studios
**Version:** 1.0 — Initial Spec
**Date:** May 19, 2026
**Status:** Draft
**Platform:** macOS + Figma Plugin

---

## Problem Statement

Designers building for Apple platforms need custom SF Symbol icons that work seamlessly in both **Xcode (for developers)** and **Figma (for designers)**. Today this requires stitching together 4+ disconnected tools: Apple's SF Symbols app for template export, a vector editor for drawing glyphs, manual annotation of weight/scale variants, and a separate font tool to package icons as a typeface. The pipeline is fragmented, error-prone, and burns hours of skilled design time on mechanical busywork.

The core insight is that a single designed icon should produce **two outputs from one source of truth**: an SF Symbol template (.svg) that developers drop into Xcode, and a font glyph (.otf/.ttf) that designers install via Font Book and use in Figma as regular text. No custom Figma plugins for consumption, no manual format conversion, no broken handoffs.

**Impact of not solving:** Each custom icon currently takes 1–2 hours to produce across the full pipeline. Teams resort to workaround icon libraries that don't match SF Pro's optical weight system, creating visual inconsistency between system and custom icons. Designer-developer handoff relies on manual file sharing with no single source of truth.

---

## Goals

- **Unified pipeline:** Design one icon, export both an SF Symbol template and a font glyph from a single tool.
- **Dynamic templating:** Generate Apple's 3-master dynamic template (Ultralight, Regular, Black × S/M/L) so Xcode handles interpolation to all 9 weights.
- **Flexible weight input:** Support three modes — uniform icon, single-master with auto-generation, or user-provided 3 masters — so the tool adapts to different skill levels and needs.
- **Instant Figma iteration:** Re-export font → update Font Book → Figma reflects changes. Target: under 30 seconds from edit to Figma preview.
- **Apple spec compliance:** Output templates that pass Xcode's SF Symbol validation with correct cap heights (70.459), margins, and annotation format (Template v7.0).

---

## Non-Goals

- **Full typeface design:** SF Custom creates icon fonts, not text typefaces. Designing new letterforms that optically match SF Pro's full character set is a different product. *(Too complex, separate domain)*
- **Static template export in v1:** The 27-variant static template (9 weights × 3 scales) is deferred. Dynamic templating covers the use case with 9 variants instead. *(Leaner for the user)*
- **Figma consumption plugin:** Icons reach Figma via the font — no Figma plugin needed on the consumption side. A library/catalog plugin may come in v2. *(Font approach is simpler)*
- **Cloud sync or team features:** v1 is a local tool. No accounts, no cloud storage, no multi-user collaboration. *(Premature for internal tool)*
- **Windows or Linux support:** macOS only. The app relies on Font Book integration and Apple's template format. *(Platform-native by design)*

---

## System Architecture

SF Custom consists of two components connected via a local HTTP bridge:

### Figma Plugin (Input Pipeline)

The Figma plugin is the lightweight front-end for icon capture and preview.

- **Read vector paths:** Extract SVG path data from selected Figma nodes (e.g., icons in a design system like DSystem-HELIOS).
- **Weight mode selection:** Let the user choose between the three weight input modes (uniform, single-master + generate, provide all 3).
- **Live preview:** Show how the icon will render across the 3 master weights and 3 scales before committing.
- **Send to macOS app:** POST vector data + weight configuration to the macOS app's local HTTP server.
- **Direct SVG download:** Option to download the SF Symbol template .svg directly from the plugin as a fallback.

### macOS App (Engine)

The macOS app is the processing engine and icon library manager.

- **Weight interpolation:** Generate missing weight masters from a single input using stroke expansion/contraction based on Apple's measured weight curves.
- **Template generation:** Produce Apple-compliant SF Symbol template SVGs with correct guide lines, margins, and annotation metadata.
- **Font compilation:** Add icon glyphs to an .otf/.ttf font file using the SF Pro metric system (cap height 70.459, consistent baselines).
- **Font Book integration:** Auto-install/update the compiled font in macOS Font Book for instant availability in Figma and other apps.
- **Icon library:** Manage a catalog of all custom icons with metadata, tags, and version history.
- **Preview panel:** Show icons across all weights and scales with side-by-side comparison to native SF Symbols.

### Local HTTP Bridge

The Figma plugin communicates with the macOS app via a local HTTP server running on **localhost**. No cloud, no accounts, no external dependencies. The plugin POSTs vector data; the app processes it and returns status. Font updates happen on the filesystem and propagate to Figma via Font Book.

---

## Technical Specification: SF Symbol Templates

Analysis of Apple's SF Symbol template format (Template v7.0, Xcode 26+) based on the pencil symbol exports.

### Template Grid

| Property | Value | Unit | Notes |
|---|---|---|---|
| Canvas | 3300 × 2200 | SVG units | Fixed for all symbols |
| Cap height | 70.459 | SVG units | Constant across all scales |
| Column spacing | ~296.7 | SVG units | Between weight columns |
| Row spacing | 430.0 | SVG units | Between scale rows |

### Scale Baselines

| Scale | Baseline Y | Capline Y | Width (Reg) | Height (Reg) | Factor vs S |
|---|---|---|---|---|---|
| Small | 696.0 | 625.541 | 61.96 | 61.52 | 1.00× |
| Medium | 1126.0 | 1055.54 | 78.83 | 78.34 | 1.27× |
| Large | 1556.0 | 1485.54 | 101.44 | 100.89 | 1.64× |

### Weight Growth Curve

The growth from Ultralight to Black is non-linear. Most expansion happens past Regular:

| Weight | Width (S) | Growth | Adv. Width | Role in Dynamic |
|---|---|---|---|---|
| **Ultralight** | 60.96 | baseline | 77.98 | **Master 1 (lightest)** |
| Thin | 61.19 | +0.4% | — | Interpolated by Xcode |
| Light | 61.63 | +1.1% | — | Interpolated by Xcode |
| **Regular** | 61.96 | +1.6% | 78.67 | **Master 2 (middle)** |
| Medium | 64.90 | +6.5% | — | Interpolated by Xcode |
| Semibold | 67.15 | +10.2% | — | Interpolated by Xcode |
| Bold | 70.12 | +15.0% | — | Interpolated by Xcode |
| Heavy | 74.42 | +22.1% | — | Interpolated by Xcode |
| **Black** | 78.27 | +28.4% | 94.54 | **Master 3 (heaviest)** |

### Scale Position Offsets

| Offset | X-shift | Y-shift |
|---|---|---|
| Small → Medium | −10.770 | +430.000 |
| Small → Large | −25.240 | +860.000 |

---

## User Stories

### Designer (Icon Author)

- As a **designer**, I want to select an icon in my Figma design system and send it to SF Custom so that I don't need to manually export and re-import SVGs.
- As a **designer**, I want to choose whether my icon looks the same at all weights or varies across Ultralight/Regular/Black so that I control the level of craftsmanship per icon.
- As a **designer**, I want to preview how my icon will render at all 3 weights and 3 scales before generating the template so that I can catch issues early.
- As a **designer**, I want the generated font to auto-install in Font Book so that I can use it in Figma immediately without manual steps.
- As a **designer**, I want to iterate on an icon and see the updated version in Figma within 30 seconds so that my design workflow stays fast.

### Developer (Template Consumer)

- As a **developer**, I want to receive an SF Symbol template .svg that passes Xcode's validation so that I can add custom icons without debugging template formatting.
- As a **developer**, I want the template to use dynamic templating (3 masters) so that Xcode automatically interpolates all 9 weights for me.
- As a **developer**, I want the template to follow Apple's Template v7.0 spec with correct cap heights and margins so that custom icons align perfectly with built-in SF Symbols.

### Design System Maintainer

- As a **design system maintainer**, I want to manage a library of all custom icons in one place so that I can track what exists, tag icons, and maintain version history.
- As a **design system maintainer**, I want to bulk-export all icons as both templates and a font so that I can distribute updates to the whole team at once.

---

## Requirements

### Must-Have (P0)

*The minimum viable product. SF Custom cannot ship without these.*

#### R1: Figma Plugin — Icon Capture

The Figma plugin reads vector path data from a selected node and extracts clean SVG paths suitable for SF Symbol template generation.

- [ ] Given a selected vector node in Figma, when the user clicks "Capture Icon," then the plugin extracts the SVG path data and displays it in the plugin panel.
- [ ] Given a complex icon with multiple layers/groups, when captured, then all paths are flattened and merged into a single outlined path.
- [ ] Given a node that is not a vector (e.g., text, image), when the user tries to capture, then the plugin shows a clear error message.

#### R2: Weight Mode Selection

The user chooses how to provide weight variants:

- **Mode A — Uniform:** One icon used identically across all 3 master weights. Simplest option.
- **Mode B — Single + Generate:** User provides one icon and specifies which weight it represents (Ultralight, Regular, or Black). The app generates the other two masters using stroke expansion/contraction based on Apple's measured growth curve.
- **Mode C — Full Control:** User provides all 3 master icons (Ultralight, Regular, Black) manually.

- [ ] Given the weight mode selector, when the user picks Mode B and designates their icon as "Regular," then the app generates Ultralight (−1.6% width) and Black (+26.3% width) variants automatically.
- [ ] Given Mode C, when the user provides 3 separate icons, then each is validated against the expected bounding box proportions for its weight.

#### R3: Dynamic Template Generation

Generate an Apple-compliant SF Symbol template SVG using the dynamic format (3 masters × 3 scales = 9 variants).

- [ ] The output SVG uses a 3300×2200 canvas with correct Baseline/Capline guide lines (cap height 70.459).
- [ ] The template includes correct margin lines for each master weight at each scale.
- [ ] The SVG includes the Notes group with Template v7.0 metadata, weight/scale labels, and design variation instructions.
- [ ] The generated template validates in Xcode 26+ without errors.

#### R4: Font Compilation

Compile custom icons into an OpenType font (.otf) file that can be installed in macOS Font Book and used in Figma.

- [ ] Given one or more icons, when the user exports the font, then the app produces a valid .otf file with each icon mapped to a Unicode codepoint in the Private Use Area (U+E000–U+F8FF).
- [ ] The font uses SF Pro's metric system: consistent cap height, baseline, and ascender/descender values.
- [ ] The font supports at least the Regular weight for v1.

#### R5: Font Book Auto-Install

Automatically install or update the compiled font in macOS Font Book.

- [ ] Given a newly compiled font, when the user clicks "Install Font," then the font is installed to ~/Library/Fonts/ and is immediately available in Figma's font picker.
- [ ] Given an updated font (new icon added), when re-installed, then Figma reflects the updated glyphs within 30 seconds.

#### R6: Local HTTP Bridge

The macOS app runs a local HTTP server that the Figma plugin connects to.

- [ ] The server starts automatically when the macOS app launches and listens on a configurable localhost port.
- [ ] The Figma plugin detects whether the macOS app is running and shows connection status.
- [ ] POST /api/icons accepts vector data + weight config and returns a success/error response within 5 seconds.

#### R7: Output Preview

Show the user how their icon will look across weights and scales before committing.

- [ ] The preview shows the icon in all 3 master weights (Ultralight, Regular, Black) at the Medium scale.
- [ ] The preview is available in both the Figma plugin (lightweight) and the macOS app (full fidelity).

### Nice-to-Have (P1)

*Significantly improves the experience. Fast follows after v1 launch.*

#### R8: Icon Library Management

A catalog of all custom icons within the macOS app with search, tags, and metadata.

#### R9: Batch Export

Export all icons in the library as both SF Symbol templates and a single font file in one action.

#### R10: Glyph Name Mapping

Let users assign human-readable names and Unicode codepoints to each icon, with a visual reference sheet that maps characters to icons.

#### R11: Multi-Weight Font

Export the font with multiple weight variants (Regular, Bold, Black) so Figma's font weight selector works with the custom icon font.

### Future Considerations (P2)

*Out of scope for v1 but the architecture should not preclude these.*

#### R12: Static Template Export

Generate the full 27-variant static template (9 weights × 3 scales) for teams that need per-weight control.

#### R13: Figma Library Plugin

A Figma-side plugin that displays the icon catalog, enables drag-and-drop insertion, and auto-updates when the font changes.

#### R14: Variable Font Support

Compile icons as a variable font with a weight axis, enabling continuous weight interpolation in Figma and CSS.

#### R15: Design Token Integration

Export icon metadata as design tokens (JSON) for integration with design systems like Tokens Studio.

---

## Success Metrics

### Leading Indicators (first 2 weeks)

| Metric | Target | Measurement |
|---|---|---|
| Icon creation time | < 5 min per icon (vs 1–2 hrs today) | Time from Figma select to both outputs |
| Template validation rate | 100% pass Xcode validation | Xcode import test per template |
| Figma refresh latency | < 30 seconds edit-to-preview | Stopwatch: edit → font install → Figma shows update |
| Weight generation accuracy | < 5% deviation from hand-drawn | Overlay comparison with Apple's pencil variants |

### Lagging Indicators (first 2 months)

| Metric | Target | Measurement |
|---|---|---|
| Icons in library | 50+ custom icons | Library count |
| Handoff friction | Zero "wrong icon" bugs filed | Bug tracker |
| Team adoption | Custom font installed on all design machines | Font Book audit |

---

## Open Questions

| # | Question | Owner | Blocking? |
|---|---|---|---|
| 1 | What Unicode codepoint range should we use for the icon font? PUA (U+E000) or a custom namespace? | Engineering | **Yes** |
| 2 | Should the Figma plugin support capturing icons from component instances, or only from direct vector nodes? | Design | No |
| 3 | How should the auto-generated weight variants handle icons with variable stroke widths (some paths thick, some thin)? | Engineering | **Yes** |
| 4 | Should the font include ligature support so typing icon names (e.g., "radar") renders the glyph? | Design | No |
| 5 | What is the minimum macOS version to support? Font Book APIs differ across versions. | Engineering | **Yes** |
| 6 | Should the localhost bridge use a fixed port or auto-discover? Fixed is simpler but may conflict with other tools. | Engineering | No |

---

## Timeline

- **Phase 1 — Core Engine (weeks 1–4):** macOS app with template generation, font compilation, and Font Book integration. No Figma plugin yet — icons imported via SVG drag-and-drop.
- **Phase 2 — Figma Plugin (weeks 5–7):** Plugin with icon capture, weight mode selection, preview, and localhost bridge to the macOS app.
- **Phase 3 — Polish & Library (weeks 8–10):** Icon library management, batch export, glyph naming, and the full edit-to-Figma iteration loop under 30 seconds.

**Dependencies:** Figma Plugin API access (already available via DSystem-HELIOS project), macOS Font Book APIs (CTFontManager), OpenType font compilation library (platform TBD: native Swift vs opentype.js in a Node subprocess).

**Hard constraints:** Apple's SF Symbol template format is the spec — we conform to it, not the other way around. Template v7.0 targeting Xcode 26+.

---

## Proposed File Structure

### macOS App (Swift/SwiftUI)

```
SFCustomApp/
├── Models/
│   ├── Icon.swift
│   ├── IconLibrary.swift
│   ├── WeightMode.swift
│   └── TemplateConfig.swift
├── Views/
│   ├── LibraryView.swift
│   ├── IconEditorView.swift
│   ├── PreviewGrid.swift
│   └── WeightModeSelector.swift
├── Services/
│   ├── TemplateGenerator.swift
│   ├── FontCompiler.swift
│   ├── FontBookInstaller.swift
│   └── LocalServer.swift
├── Engine/
│   ├── SVGParser.swift
│   ├── PathInterpolator.swift
│   ├── WeightCurve.swift
│   └── MarginCalculator.swift
└── Resources/
    ├── template-base.svg
    └── weight-curve-data.json
```

### Figma Plugin (TypeScript)

```
sf-custom-plugin/
├── src/
│   ├── code.ts          # Plugin sandbox (vector extraction, Figma API)
│   ├── ui/              # Plugin UI (weight selector, preview, connection status)
│   └── bridge.ts        # Localhost HTTP client for macOS app communication
└── manifest.json        # Figma plugin manifest
```

---

*End of document. Version 1.0 — May 19, 2026*
