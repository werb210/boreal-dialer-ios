import { isPlausibleJwt, isTokenExpired } from "./token";

export type DialerAuthState = {
  token: string | null;
  initialized: boolean;
};

const STORAGE_KEYS = {
  AUTH: "bf_auth_token"
} as const;

let authState: DialerAuthState = { token: null, initialized: false };
let initPromise: Promise<void> | null = null;
const authResetters = new Set<() => void>();

function logInvariantViolation(error: unknown): void {
  console.error("[INVARIANT_VIOLATION]", error);
}

function readStoredToken(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  return window.localStorage.getItem(STORAGE_KEYS.AUTH);
}

function writeStoredToken(token: string): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(STORAGE_KEYS.AUTH, token);
}

function clearStoredToken(): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.removeItem(STORAGE_KEYS.AUTH);
  window.sessionStorage.removeItem(STORAGE_KEYS.AUTH);
}

function validateTokenOrNull(token: string | null): string | null {
  if (!token) {
    return null;
  }

  if (!isPlausibleJwt(token) || isTokenExpired(token)) {
    throw new Error("INVALID_AUTH_TOKEN");
  }

  return token;
}

async function init(): Promise<void> {
  try {
    const storedToken = readStoredToken();
    authState = {
      token: storedToken ? validateTokenOrNull(storedToken) : null,
      initialized: true
    };
  } catch (error) {
    logInvariantViolation(error);
    clearAuth();
    throw error;
  }
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

export async function initializeDialerAuthState(): Promise<DialerAuthState> {
  if (!initPromise) {
    initPromise = init();
  }

  await initPromise;
  return authState;
}

export async function login(token: string): Promise<void> {
  try {
    const validated = validateTokenOrNull(token);
    if (!validated) {
      throw new Error("INVALID_AUTH_TOKEN");
    }

    writeStoredToken(validated);
    authState = { token: validated, initialized: true };
  } catch (error) {
    clearAuth();
    logInvariantViolation(error);
    throw error;
  }
}

export function logout(): void {
  clearAuth();
}

export function getDialerAuthState(): DialerAuthState {
  if (!authState.initialized) {
    throw new Error("AUTH_NOT_INITIALIZED");
  }

  return authState;
}

export function getValidAuthToken(): string | null {
  if (!authState.initialized) {
    throw new Error("AUTH_NOT_INITIALIZED");
  }

  try {
    return validateTokenOrNull(authState.token);
  } catch (error) {
    clearAuth();
    logInvariantViolation(error);
    throw error;
  }
}
