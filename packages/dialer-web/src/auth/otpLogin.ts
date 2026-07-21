import { API_BASE, API_ENDPOINTS } from "../constants/endpoints";
import { login } from "./useDialerAuth";

// Match the portal's PhoneInput.toE164: the server texts `to: phone` via Twilio,
// which requires E.164. Bare 10-digit input was rejected (sms_failed / 500).
export function toE164(input: string): string {
  const trimmed = input.trim();
  if (trimmed.startsWith("+")) {
    return "+" + trimmed.slice(1).replace(/\D/g, "");
  }
  const digits = trimmed.replace(/\D/g, "");
  if (digits.length === 10) {
    return `+1${digits}`;
  }
  if (digits.length === 11 && digits.startsWith("1")) {
    return `+${digits}`;
  }
  return `+${digits}`;
}

export async function startOtp(phone: string): Promise<void> {
  const response = await fetch(new URL(API_ENDPOINTS.OTP_START, API_BASE).toString(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phone: toE164(phone) })
  });
  if (!response.ok) {
    throw new Error(`Could not send code (${response.status})`);
  }
}

export async function verifyOtp(phone: string, code: string): Promise<void> {
  const response = await fetch(new URL(API_ENDPOINTS.OTP_VERIFY, API_BASE).toString(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phone: toE164(phone), code })
  });
  if (!response.ok) {
    throw new Error(`Invalid code (${response.status})`);
  }
  const payload = (await response.json()) as { data?: { token?: string } };
  const token = payload?.data?.token;
  if (!token) {
    throw new Error("No token returned");
  }
  await login(token);
}
