import axios from "axios";

const configuredApiUrl = import.meta.env.VITE_API_URL;

if (!configuredApiUrl || configuredApiUrl.trim().length === 0) {
  throw new Error("MISSING_VITE_API_URL");
}

export const api = axios.create({
  baseURL: configuredApiUrl,
  timeout: 5000,
  headers: {
    "Content-Type": "application/json"
  }
});
