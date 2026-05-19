/// SF Custom Bridge — HTTP client for macOS app communication
/// Sends icon data to the locally running SF Custom macOS app

const DEFAULT_PORT = 8787;
const BASE_URL = `http://localhost:${DEFAULT_PORT}`;

export interface IconPayload {
  name: string;
  svgPath: string;
  weightMode: "uniform" | "single" | "full";
  sourceWeight?: "ultralight" | "regular" | "black";
  tags?: string[];
}

export interface ServerStatus {
  status: string;
  version: string;
  iconCount: number;
}

export interface ApiResponse {
  success?: boolean;
  error?: string;
  [key: string]: any;
}

/// Check if the macOS app is running
export async function checkConnection(): Promise<ServerStatus | null> {
  try {
    const response = await fetch(`${BASE_URL}/api/status`, {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });
    if (response.ok) {
      return await response.json();
    }
    return null;
  } catch {
    return null;
  }
}

/// Send an icon to the macOS app
export async function sendIcon(payload: IconPayload): Promise<ApiResponse> {
  try {
    const response = await fetch(`${BASE_URL}/api/icons`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    return await response.json();
  } catch (err) {
    return { error: `Connection failed: ${err}` };
  }
}

/// List all icons in the macOS app library
export async function listIcons(): Promise<ApiResponse> {
  try {
    const response = await fetch(`${BASE_URL}/api/icons`, {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });
    return await response.json();
  } catch (err) {
    return { error: `Connection failed: ${err}` };
  }
}

/// Export the font from the macOS app
export async function exportFont(): Promise<ApiResponse> {
  try {
    const response = await fetch(`${BASE_URL}/api/export/font`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
    });
    return await response.json();
  } catch (err) {
    return { error: `Connection failed: ${err}` };
  }
}
