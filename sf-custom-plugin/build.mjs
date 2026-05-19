import { build, context } from "esbuild";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const isWatch = process.argv.includes("--watch");
const root = dirname(fileURLToPath(import.meta.url));
const distDir = resolve(root, "dist");
mkdirSync(distDir, { recursive: true });

// Build the plugin sandbox bundle (runs in Figma's QuickJS).
const codeOpts = {
  entryPoints: [resolve(root, "src/code.ts")],
  outfile: resolve(distDir, "code.js"),
  bundle: true,
  target: "es2017",
  format: "iife",
  minify: !isWatch,
  logLevel: "info",
};

// Inline the UI script into ui.html so the plugin loads a single file.
async function buildUI() {
  const uiTs = resolve(root, "src/ui.ts");
  const uiBundle = await build({
    entryPoints: [uiTs],
    bundle: true,
    write: false,
    target: "es2017",
    format: "iife",
    minify: !isWatch,
    logLevel: "error",
  });
  const uiJs = uiBundle.outputFiles[0].text;
  const template = readFileSync(resolve(root, "src/ui.html"), "utf8");
  const filled = template.replace("/*__UI_JS__*/", uiJs);
  writeFileSync(resolve(distDir, "ui.html"), filled);
}

if (isWatch) {
  const ctx = await context(codeOpts);
  await ctx.watch();
  await buildUI();
  // Watch UI manually
  const { watch } = await import("node:fs");
  watch(resolve(root, "src"), { recursive: true }, async (_event, filename) => {
    if (filename && (filename.endsWith(".ts") || filename.endsWith(".html"))) {
      await buildUI().catch(console.error);
      console.log("[ui] rebuilt", new Date().toLocaleTimeString());
    }
  });
  console.log("Watching…");
} else {
  await build(codeOpts);
  await buildUI();
  console.log("Built dist/code.js and dist/ui.html");
}
