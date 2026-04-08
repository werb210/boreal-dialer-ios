import { isPlausibleJwt, isTokenExpired } from "./token";

export type DialerAuthState = {
  token: string | null;
  initialized: boolean;
};

let authState: DialerAuthState = { token: null, initialized: false };
let initializing = false;
const authResetters = new Set<() => void>();
const WEB_TOKEN_STORAGE_KEY = "bf_jwt_token";

function readStoredToken(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  return window.localStorage.getItem(WEB_TOKEN_STORAGE_KEY);
}

function writeStoredToken(token: string): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(WEB_TOKEN_STORAGE_KEY, token);
}

function clearStoredToken(): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.removeItem(WEB_TOKEN_STORAGE_KEY);
  window.sessionStorage.removeItem(WEB_TOKEN_STORAGE_KEY);
}

function validateTokenOrNull(token: string | null): string | null {
  if (!token) {
    return null;
  }

  if (!isPlausibleJwt(token) || isTokenExpired(token)) {
    clearAuth();
    return null;
  }

  return token;
}

export function registerAuthResetter(resetter: () => void): () => void {
  authResetters.add(resetter);
  return () => {
    authResetters.delete(resetter);
  };
}

export function clearAuth(): void {
  clearStoredToken();
  authState = { token: null, initialized: true };
  for (const resetter of authResetters) {
    resetter();
  }
}

export function initializeDialerAuthState(): DialerAuthState {
  if (authState.initialized || initializing) {
    return authState;
  }

  initializing = true;

  try {
    const storedToken = readStoredToken();
    authState = {
      token: validateTokenOrNull(storedToken),
      initialized: true
    };

    return authState;
  } finally {
    initializing = false;
  }
}

export function login(token: string): void {
  const validated = validateTokenOrNull(token);
  if (!validated) {
    clearAuth();
    throw new Error("INVALID_AUTH_TOKEN");
  }

  writeStoredToken(validated);
  authState = { token: validated, initialized: true };
}

export function logout(): void {
  clearAuth();
}

export function getDialerAuthState(): DialerAuthState {
  return initializeDialerAuthState();
}

export function getValidAuthToken(): string | null {
  const state = initializeDialerAuthState();
  const valid = validateTokenOrNull(state.token);

  if (!valid && state.token) {
    clearAuth();
  }

  return valid;
}
