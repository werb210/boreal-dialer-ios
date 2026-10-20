// BOREAL_v833_CERT_CLEANUP - every cloud "Upload iOS build" run makes Xcode create a new "Apple Development" certificate
// ("Created via API") for the company team, and Apple allows only a few. Once the limit was hit, archiving failed. This
// deletes those leftover API-made development certificates through the App Store Connect API, just before the archive,
// so each run cleans up after the earlier ones (its own is cleaned up by the next run, in any of the three apps).
//
// It never touches anything else: only certificate types DEVELOPMENT / IOS_DEVELOPMENT whose name says "Created via
// API". The cloud-managed Distribution certificate, Andrew Polturak's own development certificate and the VoIP push
// certificates are all kept (they are other types, or named for a person). Every certificate is listed in the log
// with what was done to it. One made in the last 75 minutes (the longest an upload can run) is kept: another app's upload may be using it.
// It never fails the workflow: a problem is printed as a warning.
//
// Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the .p8 text). Optional: DRY_RUN=1 lists without deleting.
import crypto from "node:crypto";

const API = "https://api.appstoreconnect.apple.com/v1";
const DEV_TYPES = new Set(["DEVELOPMENT", "IOS_DEVELOPMENT"]);
const PROTECTED = [/polturak/i, /andrew/i, /distribution/i, /voip/i, /push/i];

/** A development certificate lasts a year, so it was made about a year before it expires. */
const YEAR_MS = 365 * 24 * 3600 * 1000;
/** Another repo's upload may be archiving with a certificate made minutes ago: leave recent ones alone. */
export const RECENT_MS = 75 * 60 * 1000;

export function isLeftoverApiDevCert(cert, now = Date.now()) {
  const a = cert?.attributes ?? {};
  const type = String(a.certificateType ?? "");
  const label = `${a.name ?? ""} ${a.displayName ?? ""}`;
  if (!DEV_TYPES.has(type)) return false;
  if (PROTECTED.some((re) => re.test(label))) return false;
  if (!/created via api/i.test(label)) return false;
  const expires = Date.parse(String(a.expirationDate ?? ""));
  if (Number.isFinite(expires) && expires - YEAR_MS > now - RECENT_MS) return false;
  return true;
}

function b64url(buf) {
  return Buffer.from(buf).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function ascToken({ keyId, issuerId, p8, now = Math.floor(Date.now() / 1000) }) {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: issuerId, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" }));
  const signature = crypto.sign("sha256", Buffer.from(`${header}.${payload}`), { key: p8, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(signature)}`;
}

async function main() {
  const { ASC_KEY_ID: keyId, ASC_ISSUER_ID: issuerId, ASC_KEY_P8: p8 } = process.env;
  if (!keyId || !issuerId || !p8) {
    console.log("::warning::Certificate cleanup skipped: the App Store Connect key is not set.");
    return;
  }
  const dryRun = process.env.DRY_RUN === "1";
  const token = ascToken({ keyId, issuerId, p8 });
  const headers = { Authorization: `Bearer ${token}` };
  const certs = [];
  let url = `${API}/certificates?limit=200&fields[certificates]=name,displayName,certificateType,expirationDate`;
  while (url) {
    const res = await fetch(url, { headers });
    if (!res.ok) {
      console.log(`::warning::Certificate cleanup skipped: listing certificates answered ${res.status} ${await res.text()}`);
      return;
    }
    const body = await res.json();
    certs.push(...(body.data ?? []));
    url = body.links?.next ?? null;
  }
  let deleted = 0;
  for (const cert of certs) {
    const a = cert.attributes ?? {};
    const label = `${a.certificateType} "${a.displayName ?? a.name ?? cert.id}" (expires ${a.expirationDate ?? "?"})`;
    if (!isLeftoverApiDevCert(cert)) {
      console.log(`keep    ${label}`);
      continue;
    }
    if (dryRun) {
      console.log(`would delete ${label}`);
      continue;
    }
    const res = await fetch(`${API}/certificates/${cert.id}`, { method: "DELETE", headers });
    if (res.ok || res.status === 404) {
      deleted += 1;
      console.log(`deleted ${label}`);
    } else {
      console.log(`::warning::Could not delete ${label}: ${res.status} ${await res.text()}`);
    }
  }
  console.log(`Certificate cleanup: ${deleted} leftover API development certificate(s) deleted, ${certs.length - deleted} kept.`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => console.log(`::warning::Certificate cleanup failed: ${err?.message ?? err}`));
}
