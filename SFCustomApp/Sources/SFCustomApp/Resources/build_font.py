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

Icons coming from SF Custom's engine are already outlined (strokes →
fills) and carry extra keys:

    "units":   "template"           # paths are SF Symbol template units
    "masters": {"ultralight": [d], "regular": [d], "black": [d]}

Set `"variable": true` at the top level to build ONE variable font with a
`wght` axis (100 Ultralight · 400 Regular · 900 Black, plus named
instances for all 9 SF weights) from those masters. The engine guarantees
the three masters are point-compatible, which is what makes this work.

Requires Python 3.9+ and `fonttools` (4.30+).
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
    from fontTools.designspaceLib import DesignSpaceDocument, AxisDescriptor, SourceDescriptor, InstanceDescriptor
    from fontTools import varLib
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


def path_bounds(paths):
    bounds_pen = BoundsPen(None)
    for d in paths:
        if not d or not d.strip():
            continue
        try:
            parse_path(d, bounds_pen)
        except Exception:
            continue
    return bounds_pen.bounds


def glyph_transform(bounds):
    """Scale + offset that maps SVG content `bounds` into font units.

    Sizing is based on the *tight content bounding box* of the paths
    (not the SVG viewBox), so empty padding in the source SVG doesn't
    shrink the rendered glyph.
    """
    xmin, ymin, xmax, ymax = bounds
    content_w = max(xmax - xmin, 1e-6)
    content_h = max(ymax - ymin, 1e-6)

    target_size = UPEM * ICON_TARGET_FRACTION
    scale = target_size / max(content_w, content_h)
    rendered_h = content_h * scale

    # SVG y-down → font y-up flip handled by the negative y scale.
    # Vertically centre the content's bounding box on ICON_CENTER_Y so
    # icons of different aspect ratios align consistently with SF Pro.
    # In font space: y' = -scale*y + ty. We want SVG-ymin → font-target_top.
    target_top = ICON_CENTER_Y + rendered_h / 2.0
    ty = target_top + scale * ymin
    return scale, ty


def draw_glyph(paths, scale, ty, bounds, optimize=True):
    """Draw `paths` with a shared scale/ty; horizontally centre using this
    path set's own `bounds`. Returns (charstring, advance).

    `optimize=False` keeps every curve a curve (no rlineto/hhcurveto
    shortcuts), which variable-font masters need to stay compatible."""
    xmin, _, xmax, _ = bounds
    rendered_w = max(xmax - xmin, 1e-6) * scale
    # Advance width hugs the icon plus side padding on each side.
    advance = int(round(rendered_w + 2 * ICON_SIDE_PADDING))
    tx = (advance - rendered_w) / 2.0 - scale * xmin

    pen = T2CharStringPen(advance, None)
    tpen = TransformPen(pen, (scale, 0, 0, -scale, tx, ty))
    for d in paths:
        if not d or not d.strip():
            continue
        try:
            parse_path(d, tpen)
        except Exception as exc:
            sys.stderr.write(f"PATH_FAILED:{exc}\n")
            continue
    return pen.getCharString(optimize=optimize), advance


def build_glyph(paths, viewbox):
    """Convert a list of SVG path 'd' strings into a CFF (Type 2) glyph."""
    bounds = path_bounds(paths)
    if bounds is None:
        # No drawable content — return an empty glyph.
        return T2CharStringPen(UPEM, None).getCharString(), UPEM
    scale, ty = glyph_transform(bounds)
    return draw_glyph(paths, scale, ty, bounds)


MASTERS = [("ultralight", "Ultralight", 100), ("regular", "Regular", 400), ("black", "Black", 900)]
INSTANCES = [("Ultralight", 100), ("Thin", 200), ("Light", 300), ("Regular", 400), ("Medium", 500),
             ("Semibold", 600), ("Bold", 700), ("Heavy", 800), ("Black", 900)]


def master_glyphs(icon):
    """Per-master (charstring, advance) for one icon. All masters share the
    Regular sizing so the weights grow around the same centre. Icons
    without compatible masters reuse the Regular outline everywhere."""
    regular = icon.get("paths", [])
    masters = icon.get("masters") or {}
    use_masters = bool(masters) and icon.get("compatible", True)
    reg_paths = masters.get("regular", regular) if use_masters else regular
    reg_bounds = path_bounds(reg_paths)
    out = {}
    for key, _, _ in MASTERS:
        paths = masters.get(key, reg_paths) if use_masters else reg_paths
        if reg_bounds is None:
            out[key] = (T2CharStringPen(UPEM, None).getCharString(), UPEM)
            continue
        scale, ty = glyph_transform(reg_bounds)
        out[key] = draw_glyph(paths, scale, ty, path_bounds(paths) or reg_bounds, optimize=False)
    return out


def assemble_font(icons, family, style, glyphs, output):
    """glyphs: {name: (charstring, advance)}"""
    glyph_order = [".notdef"] + [icon["name"] for icon in icons]

    fb = FontBuilder(UPEM, isTTF=False)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap({icon["codepoint"]: icon["name"] for icon in icons})

    charstrings = {".notdef": T2CharStringPen(UPEM, None).getCharString()}
    advances = {".notdef": UPEM}
    for icon in icons:
        cs, advance = glyphs[icon["name"]]
        charstrings[icon["name"]] = cs
        advances[icon["name"]] = int(round(advance)) or UPEM

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


def build_font(spec):
    icons = spec["icons"]
    family = spec.get("family_name", "SF Custom")
    style = spec.get("style_name", "Regular")
    output = spec["output"]

    if spec.get("variable"):
        return build_variable_font(icons, family, output)

    glyphs = {}
    for icon in icons:
        try:
            glyphs[icon["name"]] = build_glyph(icon["paths"], icon.get("viewbox"))
        except Exception as exc:
            sys.stderr.write(f"GLYPH_FAILED:{icon['name']}:{exc}\n")
            glyphs[icon["name"]] = (T2CharStringPen(UPEM, None).getCharString(), UPEM)
    return assemble_font(icons, family, style, glyphs, output)


def build_variable_font(icons, family, output):
    """Three master OTFs → designspace → CFF2 variable font (wght axis)."""
    import os
    import tempfile

    per_icon = {}
    for icon in icons:
        try:
            per_icon[icon["name"]] = master_glyphs(icon)
        except Exception as exc:
            sys.stderr.write(f"GLYPH_FAILED:{icon['name']}:{exc}\n")
            empty = (T2CharStringPen(UPEM, None).getCharString(), UPEM)
            per_icon[icon["name"]] = {k: empty for k, _, _ in MASTERS}

    with tempfile.TemporaryDirectory() as tmp:
        doc = DesignSpaceDocument()
        axis = AxisDescriptor()
        axis.name, axis.tag = "Weight", "wght"
        axis.minimum, axis.default, axis.maximum = 100, 400, 900
        doc.addAxis(axis)

        for key, label, wght in MASTERS:
            path = os.path.join(tmp, f"master-{key}.otf")
            assemble_font(icons, family, label, {n: g[key] for n, g in per_icon.items()}, path)
            src = SourceDescriptor()
            src.path, src.name = path, f"master.{key}"
            src.familyName, src.styleName = family, label
            src.location = {"Weight": wght}
            doc.addSource(src)

        for label, wght in INSTANCES:
            inst = InstanceDescriptor()
            inst.familyName, inst.styleName = family, label
            inst.location = {"Weight": wght}
            doc.addInstance(inst)

        varfont, _, _ = varLib.build(doc)
        varfont.save(output)
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
