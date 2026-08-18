# AGENTS.md

Environment and tooling. `CLAUDE.md` covers what the project *is* and what must not be broken —
read that one for the standing bans, the conventions, and the traps.

This repo is the game **simplyZOMBIES**.

- **Godot 4.7.1 build** (`godot/`, typed GDScript) — the canonical, playable product. Every
  `godot:*` npm script and `npm run build` targets this. New behaviour goes here.
- **TypeScript/Canvas "oracle"** (`src/`, `test/`, `bench/`) — the pre-rebuild implementation,
  kept as a **frozen reference**. It is not the shipped product and must not gain features, but
  it is still in the tree and **still gated by CI**: the `check` job runs `npm test`,
  `npm run typecheck`, `npm run lint` and `npm run format:check` against it, and `performance`
  runs `npm run bench` / `npm run bench:frame`. All of it is currently green (46 files, 599
  tests). `npm run dev` serves it via Vite on `127.0.0.1:5174` if you need to look at it.

Standard commands live in `package.json` scripts, `README.md`, and `.github/workflows/ci.yml`;
use those as the source of truth.

## Current work handoff

`HANDOFF.md` remains the authority on implemented reality. The active design record is
`.hermes/plans/2026-08-17_065300-vertical-slice-design.md`; it is **not** implementation evidence.

- Pause new NPCs and adjacent feature scope. Mara remains the sole test survivor.
- **The survival loop is built and switched off.** Wounds carry a severity and bleed
  (`M2_WOUNDS_OK`), pressure and bandaging stop them and the five infection verbs are reachable
  by command (`M2_TREATMENT_OK`), and recovery closes wounds and climbs integrity back
  (`M2_RECOVERY_OK`). `SimShambler.GRABS_ENABLED` is still `false`, so nothing wounds a survivor
  in ordinary play.
- **The next step is a design decision, not code.** Flipping that flag wipes colonies on day one
  to head bites (measured: seed 404, `cause=head`, 22 bites, zero blood-loss deaths). The levers
  are head hit weight, `BITE_DAMAGE` against small parts, escape odds, and `REPEAT_BITE_TICKS`.
  **Do not pick one unilaterally** — see the correction in HANDOFF's contact note and the "Where
  the work is" section of `CLAUDE.md`.
- Do not mark any survival item done until code and a focused Godot check exist. The full balance
  grid and ten-day playtest remain required proof, deferred rather than cancelled.
- Keep effects sim-owned and command-driven; preserve sim/presentation separation and the
  health-bar ban. Player readouts stay diegetic and prose-only.

This section used to say the loop was "being specified before code" and that a reproducible
72-hour scenario had to be written before any survival behaviour landed. Five slices went in
without it, each gated instead by a focused Godot check with true negatives. The scenario is still
worth having; it was not the thing that made the work verifiable.

## Two different containers, two different starting states

Which one you are in changes the first thing you have to do.

| | Cursor Cloud VM | Claude Code on the web |
|---|---|---|
| Godot 4.7.1 | preinstalled at `/usr/local/bin/godot` | **absent** until `.claude/hooks/session-start.sh` installs it (or `bash scripts/setup-web-session.sh` by hand) |
| Export templates | preinstalled at `~/.local/share/godot/export_templates/4.7.1.stable/` | **not installed** — set `SETUP_EXPORT_TEMPLATES=1` if you need `godot:export` or `godot:smoke:exports` |
| Display | VNC desktop already on `DISPLAY=:1` | none — start one: `Xvfb :1 -screen 0 1920x1080x24 &` |
| Playwright Chromium | preinstalled | at `/opt/pw-browsers`; never run `playwright install` |

`scripts/run-godot.mjs` auto-discovers the engine (and honours `GODOT_BIN`) and hard-rejects any
build whose `--version` does not start with `4.7.1`. Keep that pin exact — the same version and
SHA-512 appear in `.github/workflows/ci.yml`, `pages.yml`, and `scripts/setup-web-session.sh`, so
changing one means changing all of them.

## Headless verification (no display needed)

Every correctness and performance gate runs headless through `scripts/run-godot.mjs`. The one to
run before a commit is **`npm run godot:m2`**, which chains all of them; `npm run godot:r6` adds
parity, coverage, mutation and soak on top. Individual gates are listed in `CLAUDE.md`.

Expected output that is **not** a failure:

- `ObjectDB ... leaked at exit` and `resources still in use` printed *after* a gate reports its
  `_OK` line. Engine shutdown noise. Check the `_OK` line and the exit code.
- `BENCH_OVER_BUDGET` from `npm run godot:bench`, which still exits 0. The budgets are calibrated
  against compiled TypeScript; headless GDScript is an interpreter. See docs/22.

Long-running gates, so you can plan: `godot:m2:balance` is ~85 s and is part of `godot:m2`.
`BALANCE_FULL=1 npm run godot:m2:balance:full` is a **~9 hour** grid and is opt-in for that
reason — `BALANCE_DAYS` and `BALANCE_SEEDS` scale it down to exercise the code path.

## Running the game (GUI)

```bash
Xvfb :1 -screen 0 1920x1080x24 &     # skip on the Cursor VM, which already has :1
DISPLAY=:1 npm run godot:run          # or npm run godot:editor
```

- Rendering is the Mesa `llvmpipe` software renderer. `Could not set V-Sync mode`, the ALSA
  errors, `libpulse.so.0: cannot open shared object file` and `All audio drivers failed, falling
  back to the dummy driver` are all expected here and harmless.
- **It starts on day 1 in daylight** — `SimBoot` boots the clock at `Clock.DAY_BEGINS`, which is
  the first tick of the Day phase. (This file used to say it starts at night and that you should
  wait for dawn. That was wrong, whenever it stopped being true.) A day is four hours at 1×, so
  press `3` for 10× and wait if you want to see dark.
- The HUD is **prose only** — no numbers except the day counter, enforced by
  `npm run godot:check:hud`. Do not go looking for a `light` value on it; the numeric developer
  sheet lives behind the `M` toggle. `F1` shows the key list, which is up by default on a fresh
  run and will sit over the middle of the screen until dismissed.

### Screenshots

A warning on checking whether a display already exists: `pgrep -f Xvfb` matches **your own shell
command** (the pattern is in its argv), so it reports a running server when there is none. Test the
display, not the process list — run the capture and read the error, or pick a fresh number
(`Xvfb :2 …`) and pass it explicitly.

There is no `scrot`, `imagemagick`, `xwd` or `ffmpeg` in these containers. Capture through Godot
instead: write a throwaway `SceneTree` script that instantiates `res://presentation/main.tscn`
into `root` — `godot/test/project_smoke.gd` is the pattern — drives it, and calls
`root.get_texture().get_image().save_png(path)`. Run it with
`DISPLAY=:1 godot --path godot --script res://<name>.gd`. This is also how you set a scenario up
before capturing it (spawn a shambler next to a survivor, then watch). Delete the script when you
are done — it is a driver, not a fixture, and it has no gate keeping it honest once it is
committed.

## When something looks broken

Check it against `main` before treating it as environment breakage — but note that this file
previously listed three "known pre-existing" failures (`npm test` content-id and handoff-count
drift, and `format:check` flagging `.scratch/*.html`) that have all since been **fixed**. As of
this writing `npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check` and the full
`npm run godot:m2` chain are green on `main`. A red one is a real regression, most likely yours.
