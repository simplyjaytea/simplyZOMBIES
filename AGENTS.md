# AGENTS.md

## Cursor Cloud specific instructions

This repo is the game **simplyZOMBIES**. Two parallel implementations live here:

- **Godot 4.7.1 build** (`godot/`, typed GDScript) — the canonical, playable product. All `godot:*` npm scripts and `npm run build` target this.
- **TypeScript/Canvas "oracle"** (`src/`, `test/`) — archived parity reference, run in a browser via `npm run dev` (Vite on `127.0.0.1:5174`). Not the shipped product.

Standard commands live in `package.json` scripts, `README.md`, and `.github/workflows/ci.yml`; use those as the source of truth. Notes below are the non-obvious, Cursor-Cloud-specific bits.

### Toolchain provided by the VM snapshot (NOT reinstalled by the update script)

- **Godot 4.7.1** is installed at `/usr/local/bin/godot` and is on `PATH`. `scripts/run-godot.mjs` auto-discovers it (it also honors `GODOT_BIN`) and hard-rejects any engine whose `--version` does not start with `4.7.1`, so keep this exact pin.
- **Godot export templates** for `4.7.1.stable` are installed at `~/.local/share/godot/export_templates/4.7.1.stable/`. These are required by `npm run build` / `npm run godot:export` and `npm run godot:smoke:exports`.
- **Playwright Chromium** is installed (used by `npm run godot:smoke:exports` and `npm run bench:frame`).

The update script only refreshes npm dependencies (`npm ci`). If the snapshot is ever rebuilt from scratch, reinstall Godot 4.7.1, its export templates, and Playwright Chromium following the exact URLs/checksums in `.github/workflows/ci.yml`.

### Running the game (GUI)

- There is a VNC desktop on `DISPLAY=:1`. Launch the game with `DISPLAY=:1 npm run godot:run` (or `npm run godot:editor`).
- Rendering uses the software renderer (Mesa `llvmpipe`). The `Could not set V-Sync mode` warning and the ALSA/`All audio drivers failed, falling back to the dummy driver` messages are expected on this headless VM and are harmless.
- The game **starts at night**, so the scene is nearly black. Press `3` (10× speed) and wait for `light` in the HUD to climb toward `1.00` to see daylight. The attention overlay (`O` cycles noise/scent/sight/light) and `Space` (shout) are readable regardless of lighting. Full key list is in `README.md`.

### Headless verification (no display needed)

All `godot:*` correctness/perf gates run headless via `scripts/run-godot.mjs` (e.g. `godot:smoke`, `godot:test`, `godot:validate`, `godot:bench`, the `godot:r6:*` gates, `godot:m2`). `godot:m2` prints Godot `ObjectDB ... leaked at exit` / `resources still in use` warnings *after* it reports `M2_LETHALITY_OK` — that is engine shutdown noise, not a failure.

### Known pre-existing drift (confirm against `main` before touching)

On the current commit these fail for repo-content reasons unrelated to environment setup, so do not chase them as env problems:

- `npm test`: `test/integration/content-loads.test.ts` expects 4 content type ids but content now includes a 5th (`survivor`); `test/unit/handoff.test.ts` expects `HANDOFF.md`'s summary-table counts to match its checkbox counts and they have drifted.
- `npm run format:check`: flags `.scratch/*.html` and `scripts/run-godot.mjs` as unformatted.
