import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { API_BASE, API_ENDPOINTS } from "./constants/endpoints";

const freshBootMarker = `fresh-boot-${Date.now()}`;

if (typeof window !== "undefined" && import.meta.env.DEV) {
  const previousBootMarker = window.sessionStorage.getItem("dialer_fresh_boot_marker");
  if (previousBootMarker) {
    throw new Error("STALE_BUILD_DETECTED");
  }
  window.sessionStorage.setItem("dialer_fresh_boot_marker", freshBootMarker);
}

if (typeof globalThis.fetch === "function") {
  const originalFetch = globalThis.fetch.bind(globalThis);
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const rawUrl = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const resolvedUrl = new URL(rawUrl, API_BASE).toString();
    const allowedPaths = new Set<string>(Object.values(API_ENDPOINTS));
    const isAllowedPath = [...allowedPaths].some((path) => resolvedUrl.includes(path));

    if (typeof input === "string" && (!resolvedUrl.startsWith(API_BASE) || !isAllowedPath)) {
      throw new Error("NETWORK_CALL_BLOCKED");
    }

    return originalFetch(input, init);
  }) as typeof globalThis.fetch;
}

const app = document.querySelector<HTMLDivElement>("#app");

if (app) {
  createRoot(app).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
}
