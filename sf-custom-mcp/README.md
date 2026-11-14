# sf-custom-mcp: let Claude control SF Custom

An MCP server that lets **Claude Desktop** or **Claude Code**, signed in with your normal Claude account (Pro, Team or Enterprise), control the SF Custom app. Claude calls the tools during your conversation. The app makes **no Anthropic API calls and needs no API key**.

It uses the official [Model Context Protocol TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) (`@modelcontextprotocol/sdk`, pinned to 1.32.2). It runs locally over stdio and talks to the app's bridge on `127.0.0.1:8787`.

## What Claude can do

| Tool | What it does |
|---|---|
| `list_icons` | List the library (mode, margins, codepoint) |
| `import_svg` | Add an SVG (markup or file path) |
| `get_template` | Build the SF Symbol template and report whether the weights interpolate |
| `preview_icon` | Onion-skin SVG plus all 9 interpolated weights |
| `update_icon` | Mode (`weights` / `scaleOnly`), per-weight margins, rename |
| `delete_icon` | Remove an icon (Claude is told to ask you first) |
| `export_icon` | Template + `.symbolset`, or straight into an `Assets.xcassets` |
| `check_template` | Check or auto-fix any template SVG on disk |
| `get_settings` / `update_settings` | Stroke ladder (2·7·13…), normalisation, default margin, variable font |
| `compile_font` | Build and install the `.otf` (optionally the variable font) |

Example prompts:
- "Import ~/Desktop/bell.svg as bell, check it interpolates, and export it into ~/Code/MyApp/MyApp/Assets.xcassets."
- "Which of my icons won't interpolate, and why?"
- "Set the ladder to 1.5 · 6 · 12 and compile a variable font."

## Setup (once)

1. **Install** (Node 18+):
   ```bash
   cd sf-custom-mcp
   npm install
   ```
2. **Open SF Custom** with the plugin bridge running (Settings → Plugin Bridge). On first start the app creates a secret token at `~/Library/Application Support/SF Custom/control-token`. Only programs that can read that file (like this server) can control the app; web pages in your browser can't.
3. **Connect Claude.** Pick one or both:

   **Claude Desktop:** open Settings → Developer → Edit Config and add:
   ```json
   {
     "mcpServers": {
       "sf-custom": {
         "command": "node",
         "args": ["/ABSOLUTE/PATH/TO/app_SFCustom/sf-custom-mcp/index.mjs"]
       }
     }
   }
   ```
   Then restart Claude Desktop. "sf-custom" appears in the tools menu.

   **Claude Code:**
   ```bash
   claude mcp add sf-custom -- node /ABSOLUTE/PATH/TO/app_SFCustom/sf-custom-mcp/index.mjs
   ```

Optional environment variables: `SFCUSTOM_PORT` (if you changed the bridge port), `SFCUSTOM_TOKEN_FILE`.

## Without the app: the CLI

For CI or scripting, the `sfcustom` command line tool uses the same engine and doesn't need the app running:

```bash
cd SFCustomApp
swift run sfcustom export icons/*.svg --xcassets ../MyApp/Assets.xcassets --lint strict
swift run sfcustom lint MyTemplate.svg --fix
swift run sfcustom font icons/*.svg --out SFCustom.otf --variable
```

## Test

```bash
npm test   # fake bridge + real MCP client; no macOS app needed
```
