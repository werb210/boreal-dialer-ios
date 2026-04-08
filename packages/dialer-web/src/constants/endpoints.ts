const configuredApiBase = import.meta.env.VITE_API_URL;

if (!configuredApiBase || configuredApiBase.trim() === "") {
  throw new Error("MISSING_VITE_API_URL");
}

export const API_BASE = configuredApiBase;

export const API_ENDPOINTS = Object.freeze({
  VOICE_CALLS: "/api/voice/calls",
  TELEPHONY_TOKEN: "/api/telephony/token",
  OTP_START: "/api/auth/otp/start",
  OTP_VERIFY: "/api/auth/otp/verify"
} as const);

export const TelephonyEndpoint = Object.freeze({
  TOKEN: API_ENDPOINTS.TELEPHONY_TOKEN
} as const);

if (import.meta.env.DEV) {
  console.assert(Object.isFrozen(API_ENDPOINTS), "API_ENDPOINTS must be frozen");
  console.assert(Object.isFrozen(TelephonyEndpoint), "TelephonyEndpoint must be frozen");
}

export type TelephonyEndpoint = (typeof TelephonyEndpoint)[keyof typeof TelephonyEndpoint];
export const TELEPHONY_TOKEN_ENDPOINT: TelephonyEndpoint = TelephonyEndpoint.TOKEN;
