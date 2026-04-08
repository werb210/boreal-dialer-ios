const JWT_PARTS = 3;

function decodeBase64Url(input: string): string {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");

  if (typeof atob === "function") {
    return atob(padded);
  }

  return Buffer.from(padded, "base64").toString("utf8");
}

export function getTokenExpiryUnix(token: string): number | null {
  const parts = token.split(".");
  if (parts.length !== JWT_PARTS) {
    return null;
  }

  try {
    const payload = JSON.parse(decodeBase64Url(parts[1])) as { exp?: unknown };
    return typeof payload.exp === "number" ? payload.exp : null;
  } catch {
    return null;
  }
}

export function isTokenExpired(token: string, nowMs = Date.now()): boolean {
  const exp = getTokenExpiryUnix(token);
  if (!exp) {
    return false;
  }

  return exp * 1000 <= nowMs;
}

export function isPlausibleJwt(token: string): boolean {
  return token.split(".").length === JWT_PARTS;
}
