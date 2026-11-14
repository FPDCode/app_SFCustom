#!/usr/bin/env node
// SF Custom MCP server — lets Claude Desktop / Claude Code drive the
// SF Custom app through its local bridge (http://127.0.0.1:8787).
//
// Runs on your Mac under your own Claude account: Claude calls these tools
// in your conversation; nothing here talks to the Anthropic API.
//
// Auth: the app writes a random token to
//   ~/Library/Application Support/SF Custom/control-token
// and only accepts /api/control/* requests that send it back.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const PORT = Number(process.env.SFCUSTOM_PORT || 8787);
const BASE = `http://127.0.0.1:${PORT}`;
const TOKEN_FILE = process.env.SFCUSTOM_TOKEN_FILE ||
  join(homedir(), "Library", "Application Support", "SF Custom", "control-token");

function token() {
  if (process.env.SFCUSTOM_TOKEN) return process.env.SFCUSTOM_TOKEN;
  try {
    return readFileSync(TOKEN_FILE, "utf8").trim();
  } catch {
    throw new Error(`SF Custom token not found at ${TOKEN_FILE}. Open the SF Custom app (with the plugin bridge running) once to create it.`);
  }
}

async function call(method, route, body) {
  let res;
  try {
    res = await fetch(`${BASE}/api/control${route}`, {
      method,
      headers: { "Content-Type": "application/json", "X-SFCustom-Token": token() },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new Error(`Can't reach SF Custom on ${BASE}. Is the app open and the plugin bridge running (Settings → Plugin Bridge)?`);
  }
  const json = await res.json().catch(() => ({ ok: false, error: `HTTP ${res.status}` }));
  if (!json.ok) throw new Error(json.error || "SF Custom returned an error");
  return json;
}

const text = (obj) => ({ content: [{ type: "text", text: typeof obj === "string" ? obj : JSON.stringify(obj, null, 2) }] });
const fail = (e) => ({ isError: true, content: [{ type: "text", text: String(e.message || e) }] });
const wrap = (fn) => async (args) => { try { return text(await fn(args ?? {})); } catch (e) { return fail(e); } };
const iconRef = (icon) => ({ id: icon, name: icon });

const iconArg = z.string().describe("Icon name (as shown in the sidebar) or its id");
const margin = z.object({ left: z.number().min(0).optional(), right: z.number().min(0).optional() });

const server = new McpServer({ name: "sf-custom", version: "1.0.0" });

server.tool("list_icons",
  "List the icons in the SF Custom library with their mode (weights / scaleOnly) and margins.",
  {}, wrap(() => call("GET", "/icons")));

server.tool("import_svg",
  "Add an SVG to the SF Custom library. Pass the SVG markup, or a path to an .svg file on this Mac.",
  { name: z.string().describe("Icon name, e.g. heart.circle"),
    svg: z.string().optional().describe("SVG markup"),
    path: z.string().optional().describe("Path to an .svg file") },
  wrap(({ name, svg, path }) => {
    const markup = svg ?? (path ? readFileSync(path.replace(/^~/, homedir()), "utf8") : null);
    if (!markup) throw new Error("Pass svg or path");
    return call("POST", "/icons/import", { name, svg: markup });
  }));

server.tool("get_template",
  "Build the SF Symbol template for an icon and report whether Ultralight / Regular / Black interpolate cleanly (issues, warnings, stroke widths). Set include_svg to also get the template SVG.",
  { icon: iconArg, include_svg: z.boolean().optional() },
  wrap(({ icon, include_svg }) => call("POST", "/icons/template", { ...iconRef(icon), includeSVG: !!include_svg })));

server.tool("preview_icon",
  "Get preview SVGs for an icon: the onion skin (3 anchors overlaid with start points and part order) and all 9 interpolated weights.",
  { icon: iconArg },
  wrap(({ icon }) => call("POST", "/icons/preview", iconRef(icon))));

server.tool("update_icon",
  "Change an icon: mode ('weights' = stroke weights, 'scaleOnly' = same shape at every weight), per-weight margins (template units, 8–10 recommended), rename, or reset margins.",
  { icon: iconArg,
    mode: z.enum(["weights", "scaleOnly"]).optional(),
    margins: z.object({ ultralight: margin.optional(), regular: margin.optional(), black: margin.optional() }).optional(),
    rename: z.string().optional(),
    reset_margins: z.boolean().optional() },
  wrap(({ icon, mode, margins, rename, reset_margins }) =>
    call("POST", "/icons/update", { ...iconRef(icon), mode, margins, rename, resetMargins: reset_margins })));

server.tool("delete_icon",
  "Delete an icon from the library. Ask the user before calling this.",
  { icon: iconArg },
  wrap(({ icon }) => call("POST", "/icons/delete", iconRef(icon))));

server.tool("export_icon",
  "Export an icon. Without directory: template.svg, source.svg and <name>.symbolset into ~/SFCustomExports/<name>/. With directory: only the .symbolset there — pass an app's Assets.xcassets to add it straight to Xcode.",
  { icon: iconArg, directory: z.string().optional() },
  wrap(({ icon, directory }) => call("POST", "/icons/export", { ...iconRef(icon), directory })));

server.tool("check_template",
  "Check any SF Symbol template SVG for interpolation problems (point counts, start points, part order, line/curve mismatches). With fix=true, auto-fixes what it can and saves to save_path (or returns the fixed SVG).",
  { path: z.string().optional(), svg: z.string().optional(), fix: z.boolean().optional(), save_path: z.string().optional() },
  wrap(({ path, svg, fix, save_path }) => call("POST", "/templates/check", { path, svg, fix, savePath: save_path })));

server.tool("get_settings",
  "Read the symbol settings: stroke ladder (Ultralight / Regular / Black widths), Regular normalisation, default margin, variable font.",
  {}, wrap(() => call("GET", "/settings")));

server.tool("update_settings",
  "Change symbol settings. ladder_preset: 'talk' (2·7·13, Apple-like), 'legacy', or 'custom' with ladder widths.",
  { ladder_preset: z.enum(["talk", "legacy", "custom"]).optional(),
    ladder: z.object({ ultralight: z.number().positive(), regular: z.number().positive(), black: z.number().positive() }).optional(),
    normalize_regular: z.boolean().optional(),
    default_margin: z.number().min(0).optional(),
    variable_font: z.boolean().optional() },
  wrap((a) => call("POST", "/settings", {
    ladderPreset: a.ladder_preset, ladder: a.ladder, normalizeRegular: a.normalize_regular,
    defaultMargin: a.default_margin, variableFont: a.variable_font })));

server.tool("compile_font",
  "Compile all icons into an .otf and install it in Font Book. variable=true builds one variable font (Ultralight → Black).",
  { variable: z.boolean().optional(), install: z.boolean().optional() },
  wrap(({ variable, install }) => call("POST", "/font/compile", { variable, install })));

await server.connect(new StdioServerTransport());
