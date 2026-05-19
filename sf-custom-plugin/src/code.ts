// SF Custom — Figma plugin sandbox entry.
//
// Lives in Figma's QuickJS sandbox: has Figma API access, no network.
// All network traffic happens in the UI iframe (ui.ts).

figma.showUI(__html__, { width: 340, height: 480, themeColors: true });

type Payload =
  | { kind: "selection-changed"; name: string | null; svg: string | null; error: string | null }
  | { kind: "ack"; ok: true };

function postSelection() {
  const selection = figma.currentPage.selection;
  if (selection.length === 0) {
    figma.ui.postMessage({
      kind: "selection-changed",
      name: null,
      svg: null,
      error: null,
    } satisfies Payload);
    return;
  }

  // We only support one node at a time — keeps the plugin simple.
  const node = selection[0];
  exportSVG(node)
    .then((svg) => {
      figma.ui.postMessage({
        kind: "selection-changed",
        name: defaultName(node),
        svg,
        error: null,
      } satisfies Payload);
    })
    .catch((err) => {
      figma.ui.postMessage({
        kind: "selection-changed",
        name: defaultName(node),
        svg: null,
        error: String(err?.message ?? err),
      } satisfies Payload);
    });
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
  return new TextDecoder("utf-8").decode(bytes);
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
