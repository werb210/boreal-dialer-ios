import { create } from "axios";
import { getRuntimeEnv } from "../config/runtime";

const runtimeEnv = getRuntimeEnv();

const API_BASE =
  runtimeEnv.NODE_ENV === "test"
    ? "http://127.0.0.1:3000"
    : (runtimeEnv.API_URL ?? "");

export const api = create({
  baseURL: API_BASE,
  timeout: 5000,
  headers: {
    "Content-Type": "application/json"
  }
});
