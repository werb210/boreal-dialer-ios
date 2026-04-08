import { create } from "axios";

const API_BASE =
  import.meta.env.MODE === "test"
    ? "http://127.0.0.1:3000"
    : (import.meta.env.VITE_API_URL ?? "");

export const api = create({
  baseURL: API_BASE,
  timeout: 5000,
  headers: {
    "Content-Type": "application/json"
  }
});
