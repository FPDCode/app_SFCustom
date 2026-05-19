// SF Custom — Figma plugin UI.
// Runs in an iframe with network access; talks to the sandbox via postMessage.

const BRIDGE_URL = "http://127.0.0.1:8787";

type PluginMessage =
  | { kind: "selection-changed"; name: string | null; svg: string | null; error: string | null }
  | { kind: "ack"; ok: true };

const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

const previewEl    = el<HTMLDivElement>("preview");
const nameInput    = el<HTMLInputElement>("icon-name");
const errorEl      = el<HTMLDivElement>("error");
const sendBtn      = el<HTMLButtonElement>("send");
const closeBtn     = el<HTMLButtonElement>("close");
const statusBox    = el<HTMLDivElement>("bridge-status");
const statusText   = el<HTMLSpanElement>("bridge-status-text");

let currentSVG: string | null = null;

function setError(msg: string | null) {
  if (msg) {
    errorEl.textContent = msg;
    errorEl.style.display = "block";
  } else {
    errorEl.textContent = "";
    errorEl.style.display = "none";
  }
}

function renderPreview(svg: string | null) {
  if (!svg) {
    previewEl.innerHTML = '<div class="empty">Select an icon in Figma to preview it.</div>';
    return;
  }
  // Strip XML declaration so it doesn't trip up the iframe.
  const cleaned = svg.replace(/<\?xml[^>]*\?>/, "").trim();
  previewEl.innerHTML = cleaned;
}

function updateSendEnabled() {
  sendBtn.disabled = !currentSVG || nameInput.value.trim() === "" || !bridgeReachable;
}

let bridgeReachable = false;

async function pingBridge() {
  try {
    const res = await fetch(`${BRIDGE_URL}/api/status`, { method: "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    bridgeReachable = data && data.ok === true;
    if (bridgeReachable) {
      statusBox.className = "status ok";
      statusText.textContent = `Bridge connected · ${data.iconCount ?? 0} icons in library`;
    } else {
      statusBox.className = "status err";
      statusText.textContent = "Bridge reachable but returned an error.";
    }
  } catch {
    bridgeReachable = false;
    statusBox.className = "status err";
    statusText.textContent = "Can't reach SF Custom (is the macOS app open?)";
  }
  updateSendEnabled();
}

async function sendIcon() {
  if (!currentSVG) return;
  const name = nameInput.value.trim();
  if (!name) return;

  sendBtn.disabled = true;
  sendBtn.textContent = "Sending…";
  setError(null);

  try {
    const res = await fetch(`${BRIDGE_URL}/api/icons`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, svg: currentSVG }),
    });
    const body = await res.json();
    if (!res.ok || !body.ok) {
      throw new Error(body.error || `HTTP ${res.status}`);
    }
    parent.postMessage({ pluginMessage: { type: "notify", message: `Sent ${body.name} to SF Custom` } }, "*");
    sendBtn.textContent = "Sent ✓";
    pingBridge();
    setTimeout(() => {
      sendBtn.textContent = "Send to SF Custom";
      updateSendEnabled();
    }, 1200);
  } catch (err) {
    setError(`Send failed: ${(err as Error).message}`);
    sendBtn.textContent = "Send to SF Custom";
    updateSendEnabled();
  }
}

window.addEventListener("message", (event) => {
  const msg = event.data?.pluginMessage as PluginMessage | undefined;
  if (!msg) return;
  if (msg.kind === "selection-changed") {
    currentSVG = msg.svg;
    renderPreview(msg.svg);
    if (msg.name && !nameInput.value) nameInput.value = msg.name;
    setError(msg.error);
    updateSendEnabled();
  }
});

nameInput.addEventListener("input", updateSendEnabled);
sendBtn.addEventListener("click", sendIcon);
closeBtn.addEventListener("click", () => {
  parent.postMessage({ pluginMessage: { type: "close" } }, "*");
});

parent.postMessage({ pluginMessage: { type: "ready" } }, "*");
pingBridge();
setInterval(pingBridge, 4000);
