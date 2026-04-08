import { isPlausibleJwt, isTokenExpired } from "./token";

export type DialerAuthState = {
  token: string | null;
  initialized: boolean;
};

let authState: DialerAuthState = { token: null, initialized: false };
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
}

function validateTokenOrNull(token: string | null): string | null {
  if (!token) {
    return null;
  }

  if (!isPlausibleJwt(token) || isTokenExpired(token)) {
    clearStoredToken();
    return null;
  }

  return token;
}

export function initializeDialerAuthState(): DialerAuthState {
  if (authState.initialized) {
    return authState;
  }

  const storedToken = readStoredToken();
  authState = {
    token: validateTokenOrNull(storedToken),
    initialized: true
  };

  return authState;
}

export function login(token: string): void {
  const validated = validateTokenOrNull(token);
  if (!validated) {
    authState = { token: null, initialized: true };
    throw new Error("INVALID_AUTH_TOKEN");
  }

  writeStoredToken(validated);
  authState = { token: validated, initialized: true };
}

export function logout(): void {
  clearStoredToken();
  authState = { token: null, initialized: true };
}

export function getDialerAuthState(): DialerAuthState {
  return initializeDialerAuthState();
}

export function getValidAuthToken(): string | null {
  const state = initializeDialerAuthState();
  const valid = validateTokenOrNull(state.token);
  if (!valid && state.token) {
    authState = { token: null, initialized: true };
  }

  return valid;
}
