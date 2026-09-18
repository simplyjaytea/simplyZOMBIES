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
- **2026-09-19 — Phase 1 DONE.** PR #138 merged (`7264706`, all four checks SUCCESS); plan doc
  landed `6954af7`; `.scratch/simplyzombies/` (18 files) deleted `1b6965d`; both pushed to
  `origin/main` (now `1b6965d`). **27 merged remote branches deleted** — `origin` now carries
  only `main` and `claude/raider-reach-halt` (the parked owner decision, untouched). `git gc`
  ran; no size change (92.6 MB) because every object is reachable from `main`, which is
  expected. Verification on merged main, all green: `npm run check:routing` → `ROUTING_OK`
  (111 paths, 90 scripts, 64 links, 91 check scripts); `npm test` → 45 files / 594 tests;
  `npm run godot:m2` → **82 gates, every mode exit 0, TOTAL 1908.78 s (~31.8 min)**.
- **Windows trap found and fixed (worth carrying forward).** `core.autocrlf` was `true` with
  no `.gitattributes`, so the checkout was CRLF while every blob is LF. `check_m2_dormant.gd`'s
  `_arm_lines` exact-matches `Array` elements after splitting on `\n`, so the trailing `\r`
  made the Seek arm invisible → `NO SIGHT: the isolator found no Seek arm` →
  `M2_DORMANT_FAIL`. Not a code regression; a checkout artifact. Fixed locally with
  `git config core.autocrlf false` then `git rm --cached -r . && git reset --hard`; re-ran
  dormant → `M2_DORMANT_OK`, then the whole chain green. **Recommend (owner's call): a committed
  `.gitattributes` with `* text=auto eol=lf`** so any Windows contributor gets LF without
  knowing this. Not added unilaterally — it is repo policy.
- **2026-09-19 — Phase 2, piece 1 DONE — "The bodies turn and walk"** (`kimi/pack-bodies`, not yet
  merged). Pack survivor + shambler bodies (4 directions + 4-frame walk, reproduced at the 32×40
  pawn canvas via `crop [0,0,32,40]`) and the 4 pack wearables (slot → garment) are now the shipped
  look; screamer/bloater keep generated rigs. Two owner calls this session: tint the painted body
  (Mara `#ccd4e0`, Ellis `#e0d0b8`, colonists keep their six looks-tints, player/raiders white),
  and slot → pack wearable. Full `godot:m2` → **82 gates, all exit 0, TOTAL 1707 s (~28.5 min)**;
  `sprites:check` → 172 generated + 58 authored reproduced. **Named for the owner (not settled):**
  the shared pack body composes to a median luma **0.1284** under the street floor **0.3796** —
  every human reads dark against the ground — see `.hermes/plans/2026-09-19_outpost-pack/
  pack-bodies.png`; the walk frame rate (3 ticks/frame), the Mara/Ellis tints and the dark body
  are first cuts; the five generated human rigs + shambler rig and their gear overlays are no
  longer referenced but still generated (retirement is a follow-up).
  **Trap found: `python3 tools/sprites/build.py` (write mode) re-encodes the whole generated tier
  with the local Pillow, so ~120 generated PNGs show as git-modified even though `--check` passes
  (it compares decoded pixels). `git restore` them; only the new `survivor_pack_*`/`shambler_pack_*`
  /`wear_*` PNGs are meant to be committed.**
- **Next: Phase 2, piece 2 — "The ground is the pack's"**, branch `kimi/pack-ground`. Pause here
  for the owner.
