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


def build_glyph(paths, viewbox):
    """Convert a list of SVG path 'd' strings into a CFF (Type 2) glyph."""
    vb_x, vb_y, vb_w, vb_h = viewbox
    if vb_w <= 0 or vb_h <= 0:
        vb_w = vb_h = 1.0

    # Fit the icon into a 1em square (UPEM tall), preserve aspect ratio,
    # flip Y because SVG is y-down and fonts are y-up, and shift onto the
    # baseline (descender = 0, ascender = UPEM).
    scale = UPEM / max(vb_w, vb_h)
    rendered_w = vb_w * scale
    rendered_h = vb_h * scale
    # Center horizontally; sit on the baseline with cap height ~= rendered_h.
    tx = (UPEM - rendered_w) / 2.0 - vb_x * scale
    ty = ASCENT - vb_y * (-scale)  # see transform below

    pen = T2CharStringPen(UPEM, None)
    # Affine: x' = scale * x + tx ; y' = -scale * y + ty
    # Built as a 2x3 matrix in TransformPen-style: (xx, xy, yx, yy, dx, dy)
    transform = (scale, 0, 0, -scale, -vb_x * scale + (UPEM - rendered_w) / 2.0, ASCENT + vb_y * scale)
    tpen = TransformPen(pen, transform)

    for d in paths:
        if not d or not d.strip():
            continue
        parse_path(d, tpen)

    return pen.getCharString(), rendered_w


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
    fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, usWinAscent=ASCENT, usWinDescent=abs(DESCENT))
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
