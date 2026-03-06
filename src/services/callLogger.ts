import { getDialerAuthState } from "../auth/useDialerAuth";

type CallLogPayload = {
  staff_id: string;
  client_id: string | null;
  phone_number: string;
  call_duration: number;
  call_direction: "inbound" | "outbound";
  timestamp: string;
};

export async function logCall(payload: CallLogPayload): Promise<void> {
  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL;
  if (!apiBaseUrl) {
    throw new Error("Missing VITE_API_BASE_URL");
  }

  const { token } = getDialerAuthState();
  const headers: HeadersInit = {
    "Content-Type": "application/json"
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  await fetch(`${apiBaseUrl}/api/calls/log`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload)
  });
}
