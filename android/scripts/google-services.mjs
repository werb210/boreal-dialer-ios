#!/usr/bin/env node
// BOREAL_ANDROID_DIALER_v1 - writes android/app/google-services.json (the Firebase file push alerts and incoming calls
// need) for the application id in android/app/build.gradle:
//   - the GOOGLE_SERVICES_JSON secret (raw JSON or base64) when it lists this application id, otherwise
//   - a build-only placeholder: the app builds and places calls, but gets no pushes and cannot ring while closed.
// Same approach as BF-client's scripts/ensure-google-services.mjs. No dependencies.
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const appDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "app");

export function applicationIdFrom(gradle) {
  const m = /applicationId\s*:\s*'([^']+)'/.exec(gradle) ?? /applicationId\s+["']([^"']+)["']/.exec(gradle);
  if (!m) throw new Error("android/app/build.gradle has no applicationId");
  return m[1];
}

export function placeholderFor(pkg) {
  return JSON.stringify({
    project_info: { project_number: "000000000000", project_id: "dialer-placeholder", storage_bucket: "dialer-placeholder.appspot.com" },
    client: [{
      client_info: { mobilesdk_app_id: "1:000000000000:android:0000000000000000000000", android_client_info: { package_name: pkg } },
      oauth_client: [],
      api_key: [{ current_key: "AIzaSyPLACEHOLDERPLACEHOLDERPLACEHOLDE" }],
      services: { appinvite_service: { other_platform_oauth_client: [] } },
    }],
    configuration_version: "1",
  }, null, 2) + "\n";
}

/** The secret's text when it is a google-services.json that lists `pkg`, else null. */
export function realFileFor(pkg, secret) {
  const raw = String(secret ?? "").trim();
  if (!raw) return null;
  let text = raw;
  if (raw[0] !== "{") {
    try { text = Buffer.from(raw, "base64").toString("utf8").trim(); } catch { return null; }
  }
  try {
    const parsed = JSON.parse(text);
    const names = (parsed.client ?? []).map((c) => c?.client_info?.android_client_info?.package_name);
    return names.includes(pkg) ? `${text}\n` : null;
  } catch {
    return null;
  }
}

function main() {
  const pkg = applicationIdFrom(readFileSync(path.join(appDir, "build.gradle"), "utf8"));
  const real = realFileFor(pkg, process.env.GOOGLE_SERVICES_JSON);
  writeFileSync(path.join(appDir, "google-services.json"), real ?? placeholderFor(pkg));
  if (real) console.log(`google-services.json: the Firebase file for ${pkg}`);
  else console.log(`::notice title=Firebase::No GOOGLE_SERVICES_JSON listing ${pkg} - built with a placeholder: no push alerts, and incoming calls cannot ring.`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `real=${real ? "true" : "false"}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
