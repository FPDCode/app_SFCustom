# Custom SF Symbols — talk takeaways → SF Custom roadmap

**Source:** Bruno Scheele (Binary Adventures), *"Custom SF Symbols; fun, but not easy!"* (2026)
Slides: https://www.binaryadventures.eu/speaking/2026/custom-sfsymbols/ · Example repo: https://codeberg.org/SpacyRicochet/symbols
Tools mentioned: [SwiftDraw](https://github.com/swhitty/SwiftDraw) · [Custom Symbols](https://bretlester.com/app_content/CustomSymbols/) · [McKinley](https://mckinleysymbols.com/)

---

## 1. What the talk says (condensed)

**The rules of a custom symbol**
- You only provide **3 anchors**: `Ultralight-S`, `Regular-S`, `Black-S`. Apple works out the other 6 weights and the M/L scales from them.
- Anchors must be **closed paths or basic shapes**, i.e. filled outlines, no strokes.
- All 3 anchors must have **the same number of points**, in the same structure.

**His manual recipe ("onion skinning")**
| Step | Value |
|---|---|
| Canvas line height | **70 pt** |
| Canvas width (incl. spacing) | **90 pt** |
| Regular stroke | **7 pt** |
| Ultralight stroke | **2 pt** |
| Black stroke | **13 pt** |
| Side margins | **8–10 pt** |
| Then | 50 % opacity onion skin → place in template → outline → group as `Symbols/Ultralight-S…` |

**The pitfalls (where it breaks)**
1. **Different point counts.** "Convert to outlines" algorithms behave badly and add points at some widths but not others.
2. **Black has fewer points.** Inner corner radii collapse at heavy weights and their points disappear.
3. **Different starting point.** Same point count, but each path starts at a different place.
4. **Wrong / switched path order.** Same parts (e.g. two circles) in a different order. *This doesn't show when you look at the 3 anchors.* You only see it in the weights Apple interpolates in between.
5. **Handles count too.** Bézier control points are points. A `L` in one weight against a `C` in another breaks it.

**Developer side**
- Plain icons need workarounds: `.renderingMode(.template)`, `@ScaledMetric` sizing, top alignment.
- Symbols replace all of that with one line: `Image(systemName:)` / `Image("custom")` + `HStack(alignment: .firstTextBaseline)`.
- "Work together with your designer!"

**Indie tools**
- *SwiftDraw*: CLI, `--format sfsymbol --insets`, made for CI.
- *Custom Symbols*: generates Ultralight/Black, easy guide adjustment, batch conversion.
- *McKinley*: real vector drawing, **"strokes stay strokes"**, fine-tune each variant.

---

## 2. Where SF Custom stands today

| Talk topic | SF Custom today | Gap |
|---|---|---|
| 3 anchors only | ✅ `TemplateGenerator.anchorWeights = [.ultralight, .regular, .black]` | — |
| Template v7 layout, guides, H-reference | ✅ | — |
| **Filled outlines in anchors** | ❌ Anchors contain **stroked** elements with scaled `stroke-width` (`StrokeSnooper`). Apple's samples (`calendar.svg`: 1 path × 119 cmds in every weight) are pure fills. | **Critical.** SF Symbols / Xcode can't interpolate strokes, so the user still has to outline by hand and runs straight into pitfalls 1–5. |
| Same point count / order / start | ❌ Not checked at all | **Critical.** There is no feedback when a template will interpolate wrongly. |
| Stroke ladder | Ultralight 0.42× / Black 2.50× of the source stroke | Talk recipe is 2 / 7 / 13 → **0.286× / 1.857×**. The source stroke is also never normalised to 7 at cap height 70. |
| Margins | Fixed `sideBearing = 9.76562` | No per-weight adjustment (Custom Symbols' selling point). No `--insets`. |
| Onion skin / in-between preview | CompareView shows 3 anchors side by side | No overlay, no interpolated in-between weights. Pitfall 4 stays invisible. |
| Xcode handoff | Exports `template.svg` into `~/SFCustomExports/<name>/` | No `.symbolset` (drop-in asset catalog). No Swift snippet. |
| Batch / CI | Single icon via UI or plugin | No CLI or batch export. |
| Font | `.otf`, one weight, fills only | Variable font is on the wishlist. **It needs exactly the same compatible outlines (§3.1).** |

---

## 3. Recommendations (prioritised)

### P0-1 · Compatible Outliner: valid anchors by construction
**Problem:** Generic stroke-to-outline converters (Illustrator, Figma, `CGPath.copy(strokingWithWidth:)`) produce different topology at different widths. The talk calls these "badly behaved algorithms", and they're the root cause of pitfalls 1, 2, 3 and 5.

**Idea:** Write our own deterministic stroker. Because *we* control the algorithm, the same source path at 2, 7 or 13 units always gives the **same command sequence**, and only the coordinates change. That's the McKinley philosophy ("strokes stay strokes"): the stroke-based SVG stays the master, and outlines are only an export artifact.

**Rules the stroker must follow**
- Normalise first: `rect / circle / ellipse / line / polyline / polygon` → `path`; bake all transforms; convert `Q`, `A`, `H`, `V`, `S`, `T` → `C` / `L`.
- **Every** segment becomes cubic (`L` → `C` with collinear handles at 1/3 and 2/3), so there's never a C-versus-L mismatch.
- Offset each input segment into a **fixed** number of cubic segments per side (e.g. 2), whatever the width.
- Joins: always emit the same structure per join type (round join = fixed 2 cubic arcs; miter = fixed 1 point plus a zero-length cubic when the miter limit is hit, never a different structure).
- Caps: butt/round/square, always the same number of segments.
- **Inner-radius collapse (pitfall 2):** when the inner offset would invert, clamp those points onto one location (a degenerate segment). *Never delete them.*
- Start point: the outline always starts at the offset of the source path's first point, outer side. Subpath order = source element order (pitfalls 3 and 4 fixed by construction).
- Output: one `<path>` per source subpath, `fill-rule="nonzero"`, closed with `Z`.

**Acceptance:** for every sample in `SF Samples/`, the 3 anchors have identical `[(subpathIndex, commandLetters)]` signatures. The Compatibility Checker (P0-2) passes, and SF Symbols.app imports the template with smooth interpolation through all 9 weights.

### P0-2 · Compatibility Checker ("Interpolation Lint")
Runs on every generated template **and** on any SVG template the user imports (so it also helps people who draw anchors by hand in Figma or Illustrator).

| Check | Pitfall | Auto-fix |
|---|---|---|
| Same number of subpaths | 1 | — (report) |
| Same command count per subpath | 1, 2 | — (report, highlight where) |
| Same command letters per subpath (C vs L) | 5 | Promote `L` → `C` (collinear handles) |
| Start point matches (normalised position within the subpath bbox, tolerance ~15 %) | 3 | Rotate the start index to the best match |
| Subpath order matches (match by centroid + area, Hungarian / greedy) | 4 | Reorder subpaths |
| Same winding direction per subpath | (related) | Reverse the subpath |

**UX:** a status pill in the detail toolbar: 🟢 *Interpolates cleanly* / 🟠 *Auto-fixable (3)* / 🔴 *Won't interpolate*. Click it to open a list. Each row highlights the offending subpath in the onion-skin view (P1-1). Wording follows the talk: "Black has fewer points in path 2", "Path 1 starts at a different point".

### P1-1 · Onion Skin + Weight Scrubber (CompareView)
- **Onion skin:** overlay Ultralight / Regular / Black at 50 % opacity in 3 tints (the talk's core technique).
- **Start-point dots + order numbers** per subpath, so pitfalls 3 and 4 become *visible*.
- **Scrubber 0 → 1 → 2** (Ultralight → Regular → Black) that linearly interpolates path coordinates in JS inside the existing `WKWebView`. This is a preview of what Xcode will render for Thin, Light, Medium and the rest. Bad compatibility shows up instantly as twisting or exploding shapes. This is exactly the "test *all* variants!" advice, automated.

### P1-2 · Calibrated stroke ladder + normalised Regular stroke
- After scaling to cap height (70.459), **normalise the Regular stroke to 7 units** (≈ 10 % of cap height), then apply the ladder.
- New default ladder (talk recipe): **Ultralight 2 · Regular 7 · Black 13**, i.e. scales `0.286 / 1.0 / 1.857`.
- Settings → *Stroke ladder* preset: `Talk / Apple-like (2·7·13)`, `Legacy (0.42·1·2.5)`, `Custom…`. Per-icon override in the detail inspector.
- The 9-weight `Weight.strokeScale` table is still used for previews and the static font. Derive it by interpolating between the 3 anchors so previews match what Xcode will interpolate.

### P1-3 · Adjustable margin guides (insets)
- Default side margins **8–10 units** (keep 9.77 as the default).
- Per-anchor left/right margin handles in the detail view, saved per icon.
- Same concept as SwiftDraw `--insets top,left,bottom,right`, so the CLI (P2-1) can share it.

### P1-4 · Xcode-ready export + developer handoff card
- Export `<name>.symbolset/` next to `template.svg`:
  ```json
  { "info": { "author": "xcode", "version": 1 },
    "symbols": [ { "filename": "<name>.svg", "idiom": "universal" } ] }
  ```
  Drag it into any `.xcassets` and you're done.
- "Copy for developer" button with a SwiftUI snippet that follows the talk's advice:
  ```swift
  HStack(alignment: .firstTextBaseline) {
      Image("<name>")          // custom SF Symbol — scales & weights with text
      Text("Mark as Favorite")
  }
  ```

### P2-1 · CLI + batch export (CI-friendly)
`swift run sfcustom export icons/*.svg --out Symbols.xcassets --ladder 2,7,13 --insets 0,9.77,0,9.77 --lint strict`
- The same engine as the app (put the Engine in its own SPM library target).
- `--lint strict` exits non-zero when compatibility fails, so it can gate a pipeline.

### P2-2 · "Scale-only" mode for filled icons
The talk's "easiest" option is copying the same icon into all three anchors. It adjusts to text size, but not weight. CompareView already detects identical anchors through `innerXMLHash`. Turn this into an explicit, labelled mode ("Scale-only symbol: same weight at every setting") instead of an unexplained result.

### P2-3 · Variable font (free bonus after P0-1)
Once the 3 anchors are point-compatible, `fontTools.varLib` can build **one variable `.otf` with a `wght` axis** from them. That ticks off "Variable font output" from the existing wishlist with very little extra work.

---

## 4. Proposed file structure

```
SFCustomApp/
├── Package.swift                         + library target "SFCustomEngine", + executable "sfcustom" (P2-1)
└── Sources/
    ├── SFCustomEngine/                   ← moved/new, UI-free, unit-testable
    │   ├── Geometry/
    │   │   ├── PathModel.swift           Subpath / Segment (all cubic) / Point
    │   │   ├── SVGPathParser.swift       d-string → PathModel, shapes → path, transforms baked
    │   │   └── SVGPathWriter.swift       PathModel → d-string
    │   ├── Outline/
    │   │   └── CompatibleStroker.swift   P0-1
    │   ├── Lint/
    │   │   ├── CompatibilityChecker.swift  P0-2 checks
    │   │   └── CompatibilityFixer.swift    rotate start / reorder / promote L→C / reverse
    │   ├── StrokeLadder.swift            P1-2 presets + normalisation
    │   └── SymbolsetExporter.swift       P1-4
    ├── SFCustomApp/
    │   ├── Engine/TemplateGenerator.swift   uses CompatibleStroker for anchors
    │   └── Views/
    │       ├── CompareView.swift            + onion skin + scrubber (P1-1)
    │       ├── CompatibilityPill.swift      P0-2 UI
    │       └── HandoffCard.swift            P1-4
    └── sfcustom/main.swift               P2-1 CLI
Tests/SFCustomEngineTests/
    ├── CompatibleStrokerTests.swift      signature equality at 2 / 7 / 13 for every sample
    └── CompatibilityCheckerTests.swift   fixtures for each of the 5 pitfalls
```

---

## 5. Cursor instructions (paste one block per task, in order)

**Task 1: Engine split + path model**
> Read `SFCustomApp/CLAUDE.md` and `Documentation/Research/Custom-SF-Symbols-Talk-Takeaways.md`. Create an SPM library target `SFCustomEngine` (no AppKit/SwiftUI imports). Implement `PathModel` (closed/open subpaths of cubic segments only), `SVGPathParser` (supports M L H V C S Q T A Z, absolute and relative, plus rect/circle/ellipse/line/polyline/polygon, and bakes `transform` attributes), and `SVGPathWriter`. Add `func signature() -> [[Character]]` on PathModel. Unit-test it with every SVG in `SF Samples/`: the Ultralight-S, Regular-S and Black-S groups of Apple's samples must have equal signatures.

**Task 2: CompatibleStroker (P0-1)**
> In `SFCustomEngine/Outline/CompatibleStroker.swift`, implement `func outline(_ path: PathModel, width: Double, join: Join, cap: Cap, miterLimit: Double) -> PathModel` following the rules in §3.1 of the takeaways doc. Key invariant: the output `signature()` depends only on the input path, join and cap, **never on width**. Collapsed inner offsets clamp to degenerate points; never drop them. Test: for every source path in `SF Samples/` and widths [2, 7, 13], signatures are equal and every output subpath is closed.

**Task 3: Wire into TemplateGenerator + ladder (P1-2)**
> Change `TemplateGenerator.buildAnchorSlots` so anchors contain **filled outlines from CompatibleStroker** instead of stroked elements. Keep `StrokeSnooper` for resolving computed stroke widths/joins/caps only. Normalise the Regular stroke to 7 units at cap height 70.459 and apply a `StrokeLadder` (default 2/7/13; presets in `AppSettings`). Original filled shapes in the source pass through unchanged (but still go through the normaliser so all segments are cubic).

**Task 4: CompatibilityChecker + pill (P0-2)**
> Implement the checks and auto-fixes from the §3.2 table. Add `CompatibilityPill` to the IconDetailView toolbar (green / orange / red), with a popover that lists issues in plain designer language. Run it on generated templates and on SVG templates imported via drag-and-drop.

**Task 5: Onion skin + scrubber (P1-1)**
> In `CompareView`, add an "Onion skin" toggle that overlays the 3 anchors at 50 % opacity (blue/neutral/red tints) with start-point dots and subpath order numbers. Add a slider 0…2 that linearly interpolates anchor coordinates (0 = Ultralight, 1 = Regular, 2 = Black) and renders the result live in the existing WKWebView. Disable the slider and show the pill's red state when signatures don't match.

**Task 6: Margins, symbolset, handoff (P1-3, P1-4)**
> Add per-anchor left/right margin handles (default 9.77, saved on `Icon`). Extend `Exporter` to also write `<name>.symbolset/{Contents.json,<name>.svg}`. Add a "Copy for developer" button that copies the `firstTextBaseline` SwiftUI snippet from §3.4.

**Task 7 (later): CLI, scale-only mode, variable font (P2)**
> Add the `sfcustom` executable using `SFCustomEngine` with the flags in §3.5. Add an explicit "Scale-only" mode. Extend `build_font.py` to build a variable font from the 3 compatible anchors with `fontTools.varLib` (wght axis 100–900, Ultralight = 100, Regular = 400, Black = 900).
