# Outpost pack: repo cleanup, then the nine integration slices

## Context

The hand-made outpost asset pack (`godot/art/simplyzombies/`, 187 asset entries, 279 native
PNGs, 20 SpriteFrames resources) was committed on `main` in `fb4f753` (PR #137) but **not
integrated**: its own README states the live renderer was never connected, and no `.gd` file
references `res://art/simplyzombies/`. The owner's 2026-09-17 adoption decision (docs/30, "The
outpost pack, adopted") and the tier tooling it bought (`authored.json` `source`/`members`,
`build.py` reproduction, `check_authored.gd`'s SOURCE lane, the first two pack sprites) sit on
`claude/cool-noether-w4xcw7`, PR #138, CI green, 1 ahead / 0 behind `main`.

The owner (2026-09-19, this session) approved: repo cleanup (26 merged branches,
`.scratch/simplyzombies/`, `git gc`), merging PR #138 first, a local gate environment, and
working through all nine integration pieces — pausing after each phase.

This file is the pickup point. **Status lives in the Progress section at the bottom and
nowhere else**; per-piece evidence lands in docs/23's record per the standing discipline (a
piece lands = deleted from what's-left + written into the record in the same commit). Branch
claims follow `<agent>/<piece-slug>`; this arc uses `kimi/<piece-slug>`.

## Phase 0 — local gate environment

1. `npm install`.
2. Godot 4.7.1 stable win64 at `%LOCALAPPDATA%\Programs\Godot-4.7.1\Godot_v4.7.1-stable_win64.exe`
   (the path `scripts/run-godot.mjs` probes; download + SHA-512 from `.github/workflows/ci.yml`'s
   Windows lane).
3. Python 3 on PATH (for `tools/sprites/build.py` / `npm run sprites:check`).
4. Prove: `npm run godot:smoke` and `npm run sprites:check` green.

## Phase 1 — cleanup + foundation merge

1. Merge PR #138 (`claude/cool-noether-w4xcw7` → `main`).
2. Delete `.scratch/simplyzombies/` (21 tracked files of stale planning drafts) — one commit.
3. Delete the 26 merged remote branches (`git branch -r --merged origin/main`, minus
   `main`/`HEAD`). Keeps: `main`, `claude/raider-reach-halt` (parked owner decision, docs/23
   HANDOFF item 7), and `claude/cool-noether-w4xcw7` until its merge makes it merged too.
4. `git gc`.
5. Verify on merged `main`: `npm run check:routing`, `npm test`, `npm run godot:m2` green
   before any piece starts.

## Phase 2 — the nine pieces, docs/23's order

One branch each, gate red both ways + dead-socket assertion, `npm run godot:m2` green before
merge, docs/23 record in the same commit. Standing constraints (docs/30): health-bar ban,
digit ban, prose HUD, 32 px/tile at 2×, flat projection, `godot/sim/` stays art-ignorant;
the six status icons stay refused.

| # | Piece | Branch slug | Gates |
|---|---|---|---|
| 1 | The bodies turn and walk | `kimi/pack-bodies` | `check:authored` (pack_rig lane), `check:topdown` (FLIP re-pin), `check:worn`, `sprites:check` |
| 2 | The ground is the pack's | `kimi/pack-ground` | `check:appearance`, `check:road`, `check:weather` |
| 3 | Trees, the bed and the heaps | `kimi/pack-nature` | `check:trees`, `check:appearance` |
| 4 | The walls are modules | `kimi/pack-walls` | `check:roof`, `check:topdown` |
| 5 | A picture per item base | `kimi/pack-icons` | `check:inventory`, `check:authored` |
| 6 | The shot is seen | `kimi/pack-effects` | new look gate + sim-event reader assertion |
| 7 | The cars are the pack's, east-west | `kimi/pack-vehicles` | `check:wrecks`, vehicles content |
| 8 | The cursor | `kimi/pack-cursor` | presentation input/draw |
| 9 | The needs-assets report | `kimi/pack-report` | docs only |

## Progress

- **2026-09-19 — plan written, Phase 0 DONE.** Local env: Node v22.23.2; `npm install` done
  (esbuild's blocked postinstall was run by hand — `node node_modules/esbuild/install.js` —
  if `node_modules` is ever reinstalled, rerun that or check `node_modules/.bin/esbuild
  --version`). Godot 4.7.1 verified at the probed path (`--version` →
  `4.7.1.stable.official.a13da4feb`). Python 3.12.10 at
  `%LOCALAPPDATA%\Programs\Python\Python312\` with Pillow 12.3.0 (CI's pin); a `python3.exe`
  copy of `python.exe` was made in that dir because `sprites:check` calls `python3` and the
  Windows installer does not create one; the dir + `Scripts\` were prepended to the **user**
  PATH, so any *new* terminal resolves `python3`. **Trap for this session's agent shell:**
  processes already running (and their children) keep the old PATH, so this session prepends
  `$env:LOCALAPPDATA\Programs\Python\Python312` to `$env:Path` inside each command that needs
  Python. Proof: `npm run godot:smoke` → `GODOT_PROJECT_SMOKE_OK` exit 0; `npm run
  sprites:check` → `SPRITES_OK` (172 generated keys, 1 guide sheet, 2 authored keys, 33
  materials). ObjectDB-leak lines after `_OK` are the documented shutdown noise.
- **Next: Phase 1** — merge PR #138, delete `.scratch/simplyzombies/`, delete the 26 merged
  remote branches, `git gc`, then verify `check:routing` + `npm test` + `godot:m2` on merged
  main. Pause here for the owner.
