import { destroyDevice, initDevice } from "../twilio/deviceManager";

export type DialerAuthState = {
  token: string | null;
};

let authState: DialerAuthState = { token: null };
const WEB_TOKEN_STORAGE_KEY = "bf_jwt_token";

export async function login(token: string): Promise<void> {
  if (typeof window !== "undefined") {
    window.localStorage.setItem(WEB_TOKEN_STORAGE_KEY, token);
  }
  authState = { token };
  await initDevice(token);
}

export function logout(): void {
  if (typeof window !== "undefined") {
    window.localStorage.removeItem(WEB_TOKEN_STORAGE_KEY);
  }
  authState = { token: null };
  destroyDevice();
}

export function getDialerAuthState(): DialerAuthState {
  if (!authState.token && typeof window !== "undefined") {
    const storedToken = window.localStorage.getItem(WEB_TOKEN_STORAGE_KEY);
    if (storedToken) {
      authState = { token: storedToken };
    }
  }
  return authState;
}
