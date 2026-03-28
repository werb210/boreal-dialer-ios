export type ApiEnvelope<T> = {
  success: boolean;
  data?: T;
  error?: string;
};

export function assertApiResponse<T>(res: unknown): T {
  if (!res || typeof res !== "object") {
    throw new Error("Invalid API response");
  }

  const envelope = res as ApiEnvelope<T>;

  if (envelope.success !== true) {
    throw new Error(envelope.error || "API failure");
  }

  return envelope.data as T;
}
