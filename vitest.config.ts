import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["packages/dialer-web/src/**/*.test.ts"],
    environment: "node"
  }
});
