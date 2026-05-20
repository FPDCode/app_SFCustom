#!/usr/bin/env python3
"""
Build an .otf font from a list of SVG path icons.

Invoked by SFCustomApp's FontCompiler. Reads a JSON spec on stdin describing
the family + a list of glyphs (name, codepoint, viewBox, path 'd'), then
writes the resulting .otf to `--output`.

Input JSON shape:
{
  "family_name": "SF Custom",
  "style_name":  "Regular",
  "output":      "/path/to/font.otf",
  "icons": [
    { "name": "radar", "codepoint": 57344,
      "viewbox": [x, y, w, h],
      "paths":   ["M ... Z", "M ... Z"]
    },
    ...
  ]
}

Requires Python 3.9+ and `fonttools` (4.30+).
Designed for filled SVG paths. Strokes are ignored (outline them in your
design tool first if you need them in the font).
"""

import json
import sys
import argparse

try:
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.t2CharStringPen import T2CharStringPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.svgLib.path import parse_path
except ImportError as exc:
    sys.stderr.write(
        "FONTOOLS_MISSING: This script needs the 'fonttools' Python package. "
        "Install it with: pip3 install --user fonttools\n"
        f"(import error: {exc})\n"
    )
    sys.exit(2)

UPEM = 1000
ASCENT = 800
DESCENT = -200

# Target visual size of the icon as a fraction of the em box.
# Sized to sit alongside native SF Pro symbols at the same point size.
ICON_TARGET_FRACTION = 1.45

# Vertical center of the icon, in UPEM units. (ascent + descent) / 2 =
# (800 + (-200)) / 2 = 300 — the visual center of a line of text. The
# icon overshoots cap-line and baseline symmetrically, matching how
# SF Pro symbols extend slightly past those lines.
ICON_CENTER_Y = 300

# Horizontal padding around the icon's content, in UPEM units. Adds
# breathing room before the next glyph so icons can be set next to text
# without colliding. (Roughly the same as SF Pro symbol sidebearings.)
ICON_SIDE_PADDING = 100


def build_glyph(paths, viewbox):
    """Convert a list of SVG path 'd' strings into a CFF (Type 2) glyph.

    Sizing is based on the *tight content bounding box* of the paths
    (not the SVG viewBox), so empty padding in the source SVG doesn't
    shrink the rendered glyph.
    """
    # Pass 1: measure the tight bounds of the actual path content.
    bounds_pen = BoundsPen(None)
    for d in paths:
        if not d or not d.strip():
            continue
        try:
            parse_path(d, bounds_pen)
        except Exception:
            continue

    if bounds_pen.bounds is None:
        # No drawable content — return an empty glyph.
        return T2CharStringPen(UPEM, None).getCharString(), UPEM

    xmin, ymin, xmax, ymax = bounds_pen.bounds
    content_w = max(xmax - xmin, 1e-6)
    content_h = max(ymax - ymin, 1e-6)

    target_size = UPEM * ICON_TARGET_FRACTION
    scale = target_size / max(content_w, content_h)

    rendered_w = content_w * scale
    rendered_h = content_h * scale

    # Advance width hugs the icon's width plus side padding on each side
    # — so the glyph's selection box wraps the icon tightly while
    # leaving breathing room before the next character.
    advance = int(round(rendered_w + 2 * ICON_SIDE_PADDING))

    # Horizontally centre the icon inside its advance box. SVG y-down →
    # font y-up flip handled by the negative y scale. Vertically centre
    # the content's bounding box on ICON_CENTER_Y so icons of different
    # aspect ratios still align consistently with SF Pro symbols.
    tx = (advance - rendered_w) / 2.0 - scale * xmin
    target_top = ICON_CENTER_Y + rendered_h / 2.0
    # In font space: y' = -scale*y + ty. We want SVG-ymin → font-target_top.
    # → target_top = -scale*ymin + ty  ⇒  ty = target_top + scale*ymin
    ty = target_top + scale * ymin

    pen = T2CharStringPen(UPEM, None)
    transform = (scale, 0, 0, -scale, tx, ty)
    tpen = TransformPen(pen, transform)

    for d in paths:
        if not d or not d.strip():
            continue
        try:
            parse_path(d, tpen)
        except Exception as exc:
            sys.stderr.write(f"PATH_FAILED:{exc}\n")
            continue

    return pen.getCharString(), advance


def build_font(spec):
    icons = spec["icons"]
    family = spec.get("family_name", "SF Custom")
    style = spec.get("style_name", "Regular")
    output = spec["output"]

    glyph_order = [".notdef"] + [icon["name"] for icon in icons]

    fb = FontBuilder(UPEM, isTTF=False)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap({icon["codepoint"]: icon["name"] for icon in icons})

    notdef = T2CharStringPen(UPEM, None).getCharString()
    charstrings = {".notdef": notdef}
    advances = {".notdef": UPEM}

    for icon in icons:
        try:
            cs, advance = build_glyph(icon["paths"], icon["viewbox"])
            charstrings[icon["name"]] = cs
            advances[icon["name"]] = int(round(advance)) or UPEM
        except Exception as exc:
            sys.stderr.write(
                f"GLYPH_FAILED:{icon['name']}:{exc}\n"
            )
            charstrings[icon["name"]] = T2CharStringPen(UPEM, None).getCharString()
            advances[icon["name"]] = UPEM

    fb.setupCFF(
        psName=f"{family}-{style}".replace(" ", ""),
        fontInfo={
            "FullName": f"{family} {style}",
            "FamilyName": family,
        },
        charStringsDict=charstrings,
        privateDict={},
    )

    metrics = {name: (advances[name], 0) for name in glyph_order}
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    # Expand winAscent/winDescent so the larger-than-em icons don't get
    # clipped by Windows-style renderers (Figma respects these on macOS too).
    half_icon = UPEM * ICON_TARGET_FRACTION / 2.0
    fb.setupOS2(
        sTypoAscender=ASCENT,
        sTypoDescender=DESCENT,
        usWinAscent=int(ICON_CENTER_Y + half_icon) + 50,
        usWinDescent=int(half_icon - ICON_CENTER_Y) + 50,
    )
    fb.setupNameTable({
        "familyName":   family,
        "styleName":    style,
        "uniqueFontIdentifier": f"{family} {style} v1.0",
        "fullName":     f"{family} {style}",
        "psName":       f"{family}-{style}".replace(" ", ""),
        "version":      "Version 1.0",
    })
    fb.setupPost()

    fb.save(output)
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True, help="Path to JSON spec file")
    args = parser.parse_args()

    with open(args.spec, "r", encoding="utf-8") as f:
        spec = json.load(f)

    out = build_font(spec)
    print(f"OK:{out}")


if __name__ == "__main__":
    main()
