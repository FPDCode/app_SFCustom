// SF Custom — Figma plugin sandbox entry.
//
// Lives in Figma's QuickJS sandbox: has Figma API access, no network.
// All network traffic happens in the UI iframe (ui.ts).

figma.showUI(__html__, { width: 340, height: 480, themeColors: true });

type Payload =
  | {
      kind: "selection-changed";
      name: string | null;
      svg: string | null;
      figmaNodeId: string | null;
      error: string | null;
    }
  | { kind: "ack"; ok: true };

function postSelection() {
  const selection = figma.currentPage.selection;
  if (selection.length === 0) {
    figma.ui.postMessage({
      kind: "selection-changed",
      name: null,
      svg: null,
      figmaNodeId: null,
      error: null,
    } satisfies Payload);
    return;
  }

  // We only support one node at a time — keeps the plugin simple.
  const node = selection[0];

  // Stable identity. For component instances we use the main component's
  // id so editing the master updates the linked library icon; for any
  // other node we use the node's own id.
  const stableId = resolveStableId(node);

  exportSVG(node)
    .then((svg) => {
      figma.ui.postMessage({
        kind: "selection-changed",
        name: defaultName(node),
        svg,
        figmaNodeId: stableId,
        error: null,
      } satisfies Payload);
    })
    .catch((err) => {
      figma.ui.postMessage({
        kind: "selection-changed",
        name: defaultName(node),
        svg: null,
        figmaNodeId: stableId,
        error: String(err?.message ?? err),
      } satisfies Payload);
    });
}

function resolveStableId(node: SceneNode): string {
  if (node.type === "INSTANCE" && node.mainComponent) {
    return node.mainComponent.id;
  }
  return node.id;
}

async function exportSVG(node: SceneNode): Promise<string> {
  if (!("exportAsync" in node)) {
    throw new Error("That node can't be exported as SVG.");
  }
  // Outline strokes so they survive font compilation.
  const bytes = await node.exportAsync({
    format: "SVG",
    svgOutlineText: true,
    svgIdAttribute: false,
    svgSimplifyStroke: true,
  });
  return utf8BytesToString(bytes);
}

/**
 * UTF-8 decoder. Figma's QuickJS sandbox doesn't ship `TextDecoder`,
 * and SVG export returns a Uint8Array, so we decode by hand.
 */
function utf8BytesToString(bytes: Uint8Array): string {
  let out = "";
  let i = 0;
  const n = bytes.length;
  while (i < n) {
    const b = bytes[i++];
    if (b < 0x80) {
      out += String.fromCharCode(b);
    } else if (b < 0xc0) {
      // Stray continuation byte → replacement char
      out += "�";
    } else if (b < 0xe0 && i < n) {
      out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i++] & 0x3f));
    } else if (b < 0xf0 && i + 1 < n) {
      const c = ((b & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f);
      out += String.fromCharCode(c);
    } else if (i + 2 < n) {
      // 4-byte sequence → emit as surrogate pair
      const cp =
        ((b & 0x07) << 18) |
        ((bytes[i++] & 0x3f) << 12) |
        ((bytes[i++] & 0x3f) << 6) |
        (bytes[i++] & 0x3f);
      const adjusted = cp - 0x10000;
      out += String.fromCharCode(0xd800 | (adjusted >> 10), 0xdc00 | (adjusted & 0x3ff));
    } else {
      out += "�";
    }
  }
  return out;
}

function defaultName(node: SceneNode): string {
  return (node.name || "icon")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ".")
    .replace(/[^a-z0-9._-]/g, "");
}

figma.on("selectionchange", postSelection);
figma.on("currentpagechange", postSelection);

figma.ui.onmessage = (msg: { type: string; [key: string]: unknown }) => {
  if (msg.type === "ready") {
    postSelection();
    return;
  }
  if (msg.type === "close") {
    figma.closePlugin();
    return;
  }
  if (msg.type === "notify") {
    figma.notify(String(msg.message ?? ""));
    return;
  }
};
