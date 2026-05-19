/// SF Custom Figma Plugin — Sandbox Code
///
/// Pipeline:
///   1. Clone into off-page scratch frame
///   2. Outline strokes on every stroked leaf (Figma's outlineStroke bakes
///      in inside/center/outside alignment).
///      Fallback for arc-ellipse + inside-stroke (which outlineStroke can't
///      handle): copy the stroke paint into fills.
///   3. Flatten every BOOLEAN_OPERATION → plain VectorNode (resolves the
///      Subtract/Union/Difference composition).
///   4. Walk the now-strokeless tree. For every leaf shape with a visible
///      fill, read its `fillGeometry`, apply its absolute transform (relative
///      to the captured root), and emit ONE <path> per VectorPath.
///
/// We deliberately DON'T call `figma.flatten([clone])` at the end — when
/// overlapping shapes have the same winding direction, that flatten can
/// cancel them and shapes disappear. Emitting per-leaf preserves every
/// piece.
///
/// We deliberately DON'T read `strokeGeometry` — the docs and community
/// confirm it ignores `strokeAlign`, giving wrong geometry for inside/
/// outside strokes. We outline strokes in step 2 instead.
///
/// We deliberately DON'T read FRAME fillGeometry — it returns the background
/// rect even with no visible fill, which would draw a solid square over
/// the icon.

figma.showUI(__html__, { width: 380, height: 820 });

figma.ui.onmessage = async (msg: { type: string; [key: string]: any }) => {
  switch (msg.type) {
    case "capture-selection": await captureSelection(); break;
    case "get-selection-info": sendSelectionInfo(); break;
    case "close": figma.closePlugin(); break;
  }
};

figma.on("selectionchange", () => sendSelectionInfo());
sendSelectionInfo();

function sendSelectionInfo() {
  const sel = figma.currentPage.selection;
  if (sel.length === 0) {
    figma.ui.postMessage({ type: "selection", data: null });
    return;
  }
  const node = sel[0];
  figma.ui.postMessage({
    type: "selection",
    data: {
      id: node.id,
      name: node.name,
      type: node.type,
      width: "width" in node ? node.width : 0,
      height: "height" in node ? node.height : 0,
      hasVector: true,
    },
  });
}

// ─── Affine matrices ────────────────────────────────────────────

type Mat = [number, number, number, number, number, number];
const IDENTITY: Mat = [1, 0, 0, 1, 0, 0];

function multiply(a: Mat, b: Mat): Mat {
  return [
    a[0] * b[0] + a[2] * b[1],
    a[1] * b[0] + a[3] * b[1],
    a[0] * b[2] + a[2] * b[3],
    a[1] * b[2] + a[3] * b[3],
    a[0] * b[4] + a[2] * b[5] + a[4],
    a[1] * b[4] + a[3] * b[5] + a[5],
  ];
}

function figmaTransformToMat(t: Transform): Mat {
  return [t[0][0], t[1][0], t[0][1], t[1][1], t[0][2], t[1][2]];
}

function isIdentity(m: Mat): boolean {
  return m[0] === 1 && m[1] === 0 && m[2] === 0 && m[3] === 1 && m[4] === 0 && m[5] === 0;
}

// ─── Path-data transformation ───────────────────────────────────

function transformPathData(d: string, m: Mat): string {
  if (isIdentity(m)) return d;

  const apply = (x: number, y: number): [number, number] => [
    m[0] * x + m[2] * y + m[4],
    m[1] * x + m[3] * y + m[5],
  ];
  const applyLinear = (x: number, y: number): [number, number] => [
    m[0] * x + m[2] * y,
    m[1] * x + m[3] * y,
  ];

  const cmdRegex = /([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)/g;
  const numRegex = /-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/g;

  let out = "";
  let m1: RegExpExecArray | null;
  while ((m1 = cmdRegex.exec(d)) !== null) {
    const cmd = m1[1];
    const upper = cmd.toUpperCase();
    const isRel = cmd !== upper;

    const params: number[] = [];
    const paramStr = m1[2];
    let nm: RegExpExecArray | null;
    while ((nm = numRegex.exec(paramStr)) !== null) params.push(parseFloat(nm[0]));

    const fn = isRel ? applyLinear : apply;
    const acc: number[] = [];

    switch (upper) {
      case "M":
      case "L":
      case "T":
        for (let i = 0; i + 1 < params.length; i += 2) {
          const [x, y] = fn(params[i], params[i + 1]);
          acc.push(x, y);
        }
        out += cmd + fmt(acc) + " ";
        break;
      case "H":
        for (const x of params) {
          const [tx, ty] = fn(x, 0);
          acc.push(tx, ty);
        }
        out += (isRel ? "l" : "L") + fmt(acc) + " ";
        break;
      case "V":
        for (const y of params) {
          const [tx, ty] = fn(0, y);
          acc.push(tx, ty);
        }
        out += (isRel ? "l" : "L") + fmt(acc) + " ";
        break;
      case "C":
        for (let i = 0; i + 5 < params.length; i += 6) {
          for (let j = 0; j < 6; j += 2) {
            const [x, y] = fn(params[i + j], params[i + j + 1]);
            acc.push(x, y);
          }
        }
        out += cmd + fmt(acc) + " ";
        break;
      case "S":
      case "Q":
        for (let i = 0; i + 3 < params.length; i += 4) {
          for (let j = 0; j < 4; j += 2) {
            const [x, y] = fn(params[i + j], params[i + j + 1]);
            acc.push(x, y);
          }
        }
        out += cmd + fmt(acc) + " ";
        break;
      case "A":
        for (let i = 0; i + 6 < params.length; i += 7) {
          const rx = Math.abs(params[i] * Math.hypot(m[0], m[1]));
          const ry = Math.abs(params[i + 1] * Math.hypot(m[2], m[3]));
          const [x, y] = fn(params[i + 5], params[i + 6]);
          acc.push(rx, ry, params[i + 2], params[i + 3], params[i + 4], x, y);
        }
        out += cmd + fmt(acc) + " ";
        break;
      case "Z":
        out += cmd + " ";
        break;
    }
  }
  return out.trim();
}

function fmt(arr: number[]): string {
  return arr.map(n => Number.isInteger(n) ? n.toString() : parseFloat(n.toFixed(4)).toString()).join(" ");
}

// ─── Capture ────────────────────────────────────────────────────

async function captureSelection() {
  const sel = figma.currentPage.selection;
  if (sel.length === 0) {
    figma.ui.postMessage({ type: "error", message: "Nothing selected" });
    return;
  }
  const node = sel[0];
  const w = "width" in node ? node.width : 0;
  const h = "height" in node ? node.height : 0;

  const SCRATCH_NAME = "__sf_custom_scratch__";
  for (const n of figma.currentPage.children) {
    if (n.name === SCRATCH_NAME) n.remove();
  }
  const scratch = figma.createFrame();
  scratch.name = SCRATCH_NAME;
  scratch.x = 100000;
  scratch.y = 100000;
  scratch.resize(1, 1);
  scratch.fills = [];
  scratch.clipsContent = false;
  scratch.locked = true;
  figma.currentPage.appendChild(scratch);

  try {
    const clone = node.clone();
    scratch.appendChild(clone);

    outlineAllStrokes(clone);
    flattenAllBooleanOps(clone);

    // Walk the clone (after stroke outlining + boolean flattening) and
    // emit each leaf's fillGeometry as a separate <path>. NO final
    // figma.flatten — that step does boolean-union math that can cancel
    // overlapping subpaths.
    const captured: { d: string; rule: "nonzero" | "evenodd" }[] = [];

    // The selected node is our viewBox root. Don't apply its own
    // relativeTransform — its children's transforms are already relative
    // to the selected node's origin. Start the walk with IDENTITY into
    // each child.
    if ("children" in clone) {
      for (const child of clone.children) {
        walkAndEmit(child, IDENTITY, captured);
      }
    } else {
      // Selected node is itself a leaf — emit its fillGeometry directly.
      emitLeaf(clone, IDENTITY, captured);
    }

    const body = captured.map(c => {
      const rule = c.rule === "evenodd" ? ' fill-rule="evenodd"' : "";
      return `<path${rule} d="${c.d}" fill="black"/>`;
    }).join("");

    const svgString =
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">` +
      body +
      `</svg>`;

    figma.ui.postMessage({
      type: "captured",
      data: {
        name: node.name,
        svgPath: captured.map(c => c.d).join(" "),
        fullSVG: svgString,
        width: w,
        height: h,
      },
    });
  } catch (err) {
    figma.ui.postMessage({ type: "error", message: `Capture failed: ${err}` });
  } finally {
    try { scratch.remove(); } catch { /* already removed */ }
  }
}

// ─── Tree walk + emit ───────────────────────────────────────────

function walkAndEmit(
  node: SceneNode,
  parentTransform: Mat,
  out: { d: string; rule: "nonzero" | "evenodd" }[]
): void {
  if ("visible" in node && (node as any).visible === false) return;

  const local = figmaTransformToMat(node.relativeTransform);
  const abs = multiply(parentTransform, local);

  // Containers: skip their own (FRAME) background rect, just descend.
  const isContainer =
    node.type === "FRAME" || node.type === "GROUP" ||
    node.type === "SECTION" || node.type === "COMPONENT_SET" ||
    node.type === "COMPONENT";

  if (!isContainer) {
    emitLeaf(node, abs, out);
  }

  // Don't descend into already-composed nodes.
  if (node.type === "BOOLEAN_OPERATION" || node.type === "INSTANCE") return;

  if ("children" in node) {
    for (const child of node.children) {
      walkAndEmit(child, abs, out);
    }
  }
}

function emitLeaf(
  node: SceneNode,
  transform: Mat,
  out: { d: string; rule: "nonzero" | "evenodd" }[]
): void {
  if (!hasVisibleFill(node)) return;
  if (!("fillGeometry" in node)) return;
  const paths = (node as any).fillGeometry as ReadonlyArray<VectorPath>;
  if (!paths || paths.length === 0) return;
  for (const p of paths) {
    out.push({
      d: transformPathData(p.data, transform),
      rule: p.windingRule === "EVENODD" ? "evenodd" : "nonzero",
    });
  }
}

// ─── Stroke outlining ───────────────────────────────────────────

function outlineAllStrokes(root: SceneNode): void {
  const stroked: SceneNode[] = [];
  const visit = (n: SceneNode): void => {
    if ("visible" in n && (n as any).visible === false) return;
    const isLeaf =
      n.type === "VECTOR" || n.type === "LINE" || n.type === "ELLIPSE" ||
      n.type === "RECTANGLE" || n.type === "POLYGON" || n.type === "STAR";
    if (isLeaf && hasVisibleStroke(n)) {
      stroked.push(n);
    }
    if (
      "children" in n &&
      n.type !== "BOOLEAN_OPERATION" &&
      n.type !== "INSTANCE"
    ) {
      for (const c of n.children) visit(c);
    }
  };
  visit(root);

  for (const n of stroked) {
    const fillVisible = hasVisibleFill(n);
    const strokePaint = (n as any).strokes[0];

    let outlined: SceneNode | null = null;
    try { outlined = (n as any).outlineStroke(); } catch { outlined = null; }

    // Verify outlineStroke produced actual geometry. For arc-ellipses with
    // inside-strokes Figma can return a non-null but zero-size VectorNode —
    // we treat that as a failure.
    const usable = !!outlined
      && (("width" in outlined && (outlined as any).width > 0)
          || ("height" in outlined && (outlined as any).height > 0));

    if (usable) {
      if (fillVisible) {
        (n as any).strokes = [];
      } else {
        n.remove();
      }
      continue;
    }

    if (outlined) {
      try { (outlined as any).remove(); } catch { /* ignore */ }
    }

    // Fallback for shapes Figma can't outline: copy stroke paint into fills.
    // For inside-stroke designs thick enough to fill the interior (typical
    // for icon-style strokes), this matches the visual.
    if (!fillVisible && "fills" in n && "strokes" in n) {
      (n as any).fills = [strokePaint];
      (n as any).strokes = [];
    }
  }
}

// ─── Boolean op flattening ──────────────────────────────────────

function flattenAllBooleanOps(root: SceneNode): void {
  const ops: BooleanOperationNode[] = [];
  const visit = (n: SceneNode): void => {
    if ("children" in n && n.type !== "INSTANCE") {
      for (const c of n.children) visit(c);
    }
    if (n.type === "BOOLEAN_OPERATION") {
      ops.push(n as BooleanOperationNode);
    }
  };
  visit(root);

  for (const op of ops) {
    try { figma.flatten([op]); } catch { /* skip if Figma refuses */ }
  }
}

// ─── Visibility helpers ─────────────────────────────────────────

function hasVisibleFill(n: SceneNode): boolean {
  if (!("fills" in n)) return false;
  const fills = (n as any).fills;
  if (!Array.isArray(fills)) return false;
  return fills.some((p: Paint) =>
    p.visible !== false && (p.opacity === undefined || p.opacity > 0)
  );
}

function hasVisibleStroke(n: SceneNode): boolean {
  if (!("strokes" in n)) return false;
  const strokes = (n as any).strokes;
  if (!Array.isArray(strokes) || strokes.length === 0) return false;
  return strokes.some((p: Paint) =>
    p.visible !== false && (p.opacity === undefined || p.opacity > 0)
  );
}
