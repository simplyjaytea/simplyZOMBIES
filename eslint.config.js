import js from "@eslint/js";
import tseslint from "typescript-eslint";

/**
 * docs/19-architecture.md#sim--the-hard-rules lists the constraints sim/ runs under and
 * says they are "enforced by lint rules and CI, not by good intentions". This file is that
 * enforcement for the statically checkable ones.
 *
 * The companion is tsconfig.sim.json, which compiles sim/ with no DOM lib at all -- that
 * catches DOM access this blocklist never thought to name.
 */

/** Browser globals with no business inside a headless, portable simulation. */
const BROWSER_GLOBALS = [
  "window",
  "document",
  "navigator",
  "localStorage",
  "sessionStorage",
  "performance",
  "requestAnimationFrame",
  "cancelAnimationFrame",
  "fetch",
  "XMLHttpRequest",
  "alert",
  "location",
  "history",
  "screen",
  "devicePixelRatio",
  "innerWidth",
  "innerHeight",
  "addEventListener",
];

export default tseslint.config(
  {
    ignores: ["node_modules/", "dist/"],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  {
    files: ["**/*.ts"],
    languageOptions: { ecmaVersion: 2022, sourceType: "module" },
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      eqeqeq: ["error", "always"],
      "no-var": "error",
      "prefer-const": "error",
    },
  },

  {
    // Plain ESM rather than TypeScript, so no-undef is live for these. The benchmark driver
    // straddles two runtimes -- node around the outside, and browser code inside
    // page.evaluate that is lexically in the same file -- which is why the browser globals are
    // here too. `scripts/` is node only and shares the list rather than growing a second one.
    files: ["bench/**/*.mjs", "scripts/**/*.mjs"],
    languageOptions: {
      globals: {
        console: "readonly",
        process: "readonly",
        URL: "readonly",
        globalThis: "readonly",
        performance: "readonly",
        requestAnimationFrame: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
      },
    },
  },

  {
    // Scoped to sim/ only. render/ and platform/ are exactly the layers that are supposed
    // to touch these things.
    files: ["src/sim/**/*.ts"],
    rules: {
      "no-restricted-globals": [
        "error",
        ...BROWSER_GLOBALS.map((name) => ({
          name,
          message:
            "sim/ stays headless and portable (docs/19-architecture.md). Put host-specific code in platform/.",
        })),
      ],

      "no-restricted-properties": [
        "error",
        {
          object: "Math",
          property: "random",
          message:
            "Nondeterminism in sim/ is a bug as severe as a crash (docs/19). Use a seeded stream: world.rng.stream(name).",
        },
        {
          object: "Date",
          property: "now",
          message: "sim/ measures time in ticks, never wall clock (docs/19). Use world.tick.",
        },
      ],

      "no-restricted-syntax": [
        "error",
        {
          selector: "NewExpression[callee.name='Date']",
          message: "sim/ measures time in ticks, never wall clock (docs/19). Use world.tick.",
        },
      ],

      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: [
                "**/render/**",
                "**/render",
                "**/platform/**",
                "**/platform",
                "**/ui/**",
                "**/ui",
              ],
              message:
                "sim/ is the bottom layer: render/, platform/ and ui/ read from it, never the reverse (docs/19-architecture.md#layers).",
            },
          ],
        },
      ],
    },
  },
);
