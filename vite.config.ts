import { defineConfig } from "vite";

// The game. The throwaway spike has its own config (vite.spike.config.ts).
//
// Root is the repository root rather than src/, so `content/` is inside the served tree --
// content-source-web.ts globs `/content/**/*.json`, and Vite can only see what is under
// the root. It is also what makes content a real module dependency, which is what gives it
// hot reload in dev.
export default defineConfig({
  root: ".",
  server: { host: "127.0.0.1", port: 5174 },
  build: { outDir: "dist", emptyOutDir: true },
});
