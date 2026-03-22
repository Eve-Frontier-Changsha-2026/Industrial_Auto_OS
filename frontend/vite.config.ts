import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  define: { global: "globalThis" },
  css: { modules: { localsConvention: "camelCase" } },
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: [],
  },
});
