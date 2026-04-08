import { defineConfig } from "vite";

export default defineConfig(({ mode }) => {
  const config = {
    root: ".",
    publicDir: "public",
    build: {
      outDir: "dist"
    }
  };

  if (mode === "development" && config.root !== ".") {
    throw new Error("INVALID_VITE_ROOT");
  }

  return config;
});
