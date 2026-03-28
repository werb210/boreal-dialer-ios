export type ApiEnvelope<T> = {
  success: boolean;
  data?: T;
  error?: string;
};

export function assertApiResponse<T>(data: unknown): T {
  if (!data || typeof data !== "object" || typeof (data as ApiEnvelope<T>).success !== "boolean") {
    throw new Error("Invalid API response");
  }

  const envelope = data as ApiEnvelope<T>;

  if (!envelope.success) {
    throw new Error(envelope.error || "Request failed");
  }

  return envelope.data as T;
}
