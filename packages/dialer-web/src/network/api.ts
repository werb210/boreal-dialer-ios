import axios from "axios";

const mode = import.meta.env.MODE;
const configuredApiUrl = import.meta.env.VITE_API_URL;

const API_BASE =
  mode === "test"
    ? "http://127.0.0.1:3000"
    : (() => {
        if (!configuredApiUrl || configuredApiUrl.trim().length === 0) {
          throw new Error("MISSING_VITE_API_URL");
        }

        return configuredApiUrl;
      })();

export const api = axios.create({
  baseURL: API_BASE,
  timeout: 5000,
  headers: {
    "Content-Type": "application/json"
  }
});
