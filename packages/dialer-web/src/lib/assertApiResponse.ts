export type ApiEnvelope<T> = {
  success: boolean;
  data: T;
  error?: string;
};

export function assertApiResponse<T>(res: unknown): T {
  if (!res || typeof res !== "object") {
    throw new Error("INVALID API RESPONSE");
  }

  const envelope = res as Partial<ApiEnvelope<T>>;

  if (envelope.success !== true) {
    throw new Error("INVALID API RESPONSE");
  }

  if (!("data" in envelope)) {
    throw new Error("MALFORMED_API_RESPONSE");
  }

  if (!envelope.data || typeof envelope.data !== "object") {
    throw new Error("INVALID_DATA_PAYLOAD");
  }

  return envelope.data;
}
