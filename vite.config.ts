import { defineConfig } from "vite";

// Root is the repository root rather than src/, so `godot/content/` is inside the served tree --
// content-source-web.ts globs `/godot/content/**/*.json`, and Vite can only see what is under
// the root. It is also what makes content a real module dependency, which is what gives it
// hot reload in dev.
//
// BASE_PATH exists for GitHub Pages. A project page is served from a subdirectory
// (/simplyzombies/), and Vite bakes the base into every asset URL at build time -- so a
// default-rooted build 404s on Pages while working perfectly on localhost, which is the
// failure mode that only ever shows up after deploying. Dev and preview stay at "/".
export default defineConfig({
  root: ".",
  base: process.env.BASE_PATH ?? "/",
  server: { host: "127.0.0.1", port: 5174 },
  build: { outDir: "dist", emptyOutDir: true },
});
