import { defineConfig } from "vite";

export default defineConfig({
  root: "spike",
  server: { host: "127.0.0.1", port: 5173 },
  build: { outDir: "../dist-spike", emptyOutDir: true },
});
