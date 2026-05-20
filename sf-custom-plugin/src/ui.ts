// SF Custom — Figma plugin UI.
// Runs in an iframe with network access; talks to the sandbox via postMessage.

const BRIDGE_URL = "http://localhost:8787";

type LibraryIcon = { id: string; name: string; codepoint: number; figmaNodeId?: string };

type PluginMessage =
  | {
      kind: "selection-changed";
      name: string | null;
      svg: string | null;
      figmaNodeId: string | null;
      error: string | null;
    }
  | { kind: "ack"; ok: true };

const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

const previewEl  = el<HTMLDivElement>("preview");
const nameInput  = el<HTMLInputElement>("icon-name");
const syncEl     = el<HTMLDivElement>("sync-state");
const replaceEl  = el<HTMLSelectElement>("replace-target");
const replaceRow = el<HTMLDivElement>("replace-row");
const errorEl    = el<HTMLDivElement>("error");
const sendBtn    = el<HTMLButtonElement>("send");
const closeBtn   = el<HTMLButtonElement>("close");
const statusBox  = el<HTMLDivElement>("bridge-status");
const statusText = el<HTMLSpanElement>("bridge-status-text");

let currentSVG: string | null = null;
let currentNodeId: string | null = null;
let library: LibraryIcon[] = [];
let bridgeReachable = false;

function setError(msg: string | null) {
  errorEl.textContent = msg ?? "";
  errorEl.style.display = msg ? "block" : "none";
}

function renderPreview(svg: string | null) {
  if (!svg) {
    previewEl.innerHTML = '<div class="empty">Select an icon in Figma to preview it.</div>';
    return;
  }
  previewEl.innerHTML = svg.replace(/<\?xml[^>]*\?>/, "").trim();
}

function findLinkedIcon(): LibraryIcon | undefined {
  if (!currentNodeId) return undefined;
  return library.find((i) => i.figmaNodeId === currentNodeId);
}

function findIconByName(name: string): LibraryIcon | undefined {
  return library.find((i) => i.name === name);
}

/**
 * Decide what the Send button should do given the current state, and
 * update the sync indicator + replace dropdown to match.
 */
type IngestPlan =
  | { mode: "create"; label: string; tone: "neutral" }
  | { mode: "auto"; label: string; tone: "linked"; target: LibraryIcon }
  | { mode: "update"; label: string; tone: "warning"; target: LibraryIcon };

function computePlan(): IngestPlan {
  const linked = findLinkedIcon();
  if (linked) {
    return {
      mode: "auto",
      tone: "linked",
      label: `Update ${linked.name}`,
      target: linked,
    };
  }

  const explicitTargetId = replaceEl.value;
  if (explicitTargetId) {
    const target = library.find((i) => i.id === explicitTargetId);
    if (target) {
      return { mode: "update", tone: "warning", label: `Replace ${target.name}`, target };
    }
  }

  const nameMatch = findIconByName(nameInput.value.trim());
  if (nameMatch) {
    // Name collides but no node link → ask user.
    return {
      mode: "update",
      tone: "warning",
      label: `Replace ${nameMatch.name}`,
      target: nameMatch,
    };
  }

  return { mode: "create", tone: "neutral", label: "Send to SF Custom" };
}

function renderSyncState() {
  const plan = computePlan();

  // Sync banner above the form.
  syncEl.className = `sync ${plan.tone}`;
  if (plan.tone === "linked") {
    syncEl.innerHTML = `<span class="dot"></span>Linked to <strong>${escapeHTML(plan.target.name)}</strong> — sending will update it.`;
  } else if (plan.tone === "warning") {
    const linked = findLinkedIcon();
    if (!linked && replaceEl.value) {
      syncEl.innerHTML = `<span class="dot"></span>Will replace <strong>${escapeHTML(plan.target.name)}</strong>.`;
    } else if (!linked) {
      syncEl.innerHTML = `<span class="dot"></span>Name <strong>${escapeHTML(plan.target.name)}</strong> already exists — pick what to do.`;
    } else {
      syncEl.innerHTML = "";
    }
  } else {
    syncEl.innerHTML = "";
  }

  // Show the "replace existing" dropdown when there's no auto-link AND a
  // name conflict exists OR the user has manually picked a target.
  const showReplace = plan.tone !== "linked" && (findIconByName(nameInput.value.trim()) || replaceEl.value);
  replaceRow.style.display = showReplace && library.length > 0 ? "block" : "none";

  // Button label reflects the plan.
  sendBtn.textContent = plan.label;
  sendBtn.disabled = !currentSVG || nameInput.value.trim() === "" || !bridgeReachable;

  // Reset button when bridge offline, so it doesn't lie.
  if (!bridgeReachable) sendBtn.textContent = "Bridge offline";
}

function escapeHTML(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

function refreshReplaceOptions() {
  // Preserve current selection across refreshes.
  const prev = replaceEl.value;
  replaceEl.innerHTML = '<option value="">Choose icon to replace…</option>';
  for (const icon of [...library].sort((a, b) => a.name.localeCompare(b.name))) {
    const opt = document.createElement("option");
    opt.value = icon.id;
    opt.textContent = `${icon.name}   ${codepointDisplay(icon.codepoint)}`;
    replaceEl.appendChild(opt);
  }
  if (library.some((i) => i.id === prev)) replaceEl.value = prev;
}

function codepointDisplay(cp: number): string {
  return "U+" + cp.toString(16).toUpperCase().padStart(4, "0");
}

async function fetchLibrary() {
  if (!bridgeReachable) return;
  try {
    const res = await fetch(`${BRIDGE_URL}/api/icons`, { method: "GET" });
    const body = await res.json();
    if (body && body.ok && Array.isArray(body.icons)) {
      library = body.icons as LibraryIcon[];
      refreshReplaceOptions();
      renderSyncState();
    }
  } catch {
    // Soft-fail; sync indicator just falls back to "create".
  }
}

async function pingBridge() {
  try {
    const res = await fetch(`${BRIDGE_URL}/api/status`, { method: "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    bridgeReachable = data && data.ok === true;
    if (bridgeReachable) {
      statusBox.className = "status ok";
      statusText.textContent = `Bridge connected · ${data.iconCount ?? 0} icons in library`;
      await fetchLibrary();
    } else {
      statusBox.className = "status err";
      statusText.textContent = "Bridge reachable but returned an error.";
    }
  } catch {
    bridgeReachable = false;
    statusBox.className = "status err";
    statusText.textContent = "Can't reach SF Custom (is the macOS app open?)";
  }
  renderSyncState();
}

async function sendIcon() {
  if (!currentSVG) return;
  const name = nameInput.value.trim();
  if (!name) return;

  const plan = computePlan();
  sendBtn.disabled = true;
  sendBtn.textContent = "Sending…";
  setError(null);

  const payload: Record<string, unknown> = {
    name,
    svg: currentSVG,
    mode: plan.mode,
  };
  if (currentNodeId) payload.figmaNodeId = currentNodeId;
  if (plan.mode === "update" && "target" in plan) {
    payload.targetIconId = plan.target.id;
  }

  try {
    const res = await fetch(`${BRIDGE_URL}/api/icons`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const body = await res.json();
    if (!res.ok || !body.ok) {
      throw new Error(body.error || `HTTP ${res.status}`);
    }
    const verb = body.action === "updated" ? "Updated" : "Sent";
    parent.postMessage({ pluginMessage: { type: "notify", message: `${verb} ${body.name}` } }, "*");
    sendBtn.textContent = body.action === "updated" ? "Updated ✓" : "Sent ✓";
    await fetchLibrary();
    setTimeout(() => {
      renderSyncState();
    }, 1200);
  } catch (err) {
    setError(`Send failed: ${(err as Error).message}`);
    renderSyncState();
  }
}

window.addEventListener("message", (event) => {
  const msg = event.data?.pluginMessage as PluginMessage | undefined;
  if (!msg) return;
  if (msg.kind === "selection-changed") {
    currentSVG = msg.svg;
    currentNodeId = msg.figmaNodeId;
    renderPreview(msg.svg);
    // Only auto-fill the name field if the user hasn't typed anything,
    // or the new selection is a different node.
    if (msg.name && (!nameInput.value || msg.figmaNodeId)) {
      nameInput.value = msg.name;
    }
    setError(msg.error);
    renderSyncState();
  }
});

nameInput.addEventListener("input", renderSyncState);
replaceEl.addEventListener("change", renderSyncState);
sendBtn.addEventListener("click", sendIcon);
closeBtn.addEventListener("click", () => {
  parent.postMessage({ pluginMessage: { type: "close" } }, "*");
});

parent.postMessage({ pluginMessage: { type: "ready" } }, "*");
pingBridge();
setInterval(pingBridge, 4000);
