// Smoke test without the macOS app: a fake bridge + a real MCP client.
import http from "node:http";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const TOKEN = "t".repeat(64);
const dir = mkdtempSync(join(tmpdir(), "sfc-"));
const tokenFile = join(dir, "control-token");
writeFileSync(tokenFile, TOKEN);
const seen = [];

const bridge = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    seen.push({ method: req.method, url: req.url, body: body ? JSON.parse(body) : null });
    res.setHeader("Content-Type", "application/json");
    if (req.headers["x-sfcustom-token"] !== TOKEN) return res.end(JSON.stringify({ ok: false, error: "unauthorized" }));
    if (req.url === "/api/control/icons") return res.end(JSON.stringify({ ok: true, icons: [{ name: "heart", mode: "weights" }] }));
    return res.end(JSON.stringify({ ok: true, echo: body ? JSON.parse(body) : null }));
  });
});
await new Promise((r) => bridge.listen(0, "127.0.0.1", r));
const port = bridge.address().port;

const here = dirname(fileURLToPath(import.meta.url));
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [join(here, "..", "index.mjs")],
  env: { ...process.env, SFCUSTOM_PORT: String(port), SFCUSTOM_TOKEN_FILE: tokenFile },
});
const client = new Client({ name: "smoke", version: "1.0.0" });
await client.connect(transport);

const tools = (await client.listTools()).tools.map((t) => t.name).sort();
console.log("tools:", tools.join(", "));
const list = await client.callTool({ name: "list_icons", arguments: {} });
console.log("list_icons →", JSON.parse(list.content[0].text).icons[0].name);
const upd = await client.callTool({ name: "update_icon", arguments: { icon: "heart", mode: "scaleOnly", margins: { regular: { left: 8 } } } });
console.log("update_icon →", JSON.stringify(JSON.parse(upd.content[0].text).echo));
const bad = await client.callTool({ name: "update_icon", arguments: { icon: "heart", mode: "bogus" } });
console.log("invalid mode rejected:", !!bad.isError);

await client.close();
bridge.close();
const expected = ["check_template", "compile_font", "delete_icon", "export_icon", "get_settings", "get_template", "import_svg", "list_icons", "preview_icon", "update_icon", "update_settings"];
if (JSON.stringify(tools) !== JSON.stringify(expected)) { console.error("unexpected tool list"); process.exit(1); }
if (!seen.some((s) => s.url === "/api/control/icons/update" && s.body.mode === "scaleOnly")) { console.error("update not forwarded"); process.exit(1); }
console.log("OK");
