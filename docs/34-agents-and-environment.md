# Agents and environment

How more than one agent works on this repo, the two containers the game runs in, the MCP servers,
and how to run the game and its headless gates. Moved out of CLAUDE.md on 2026-10-19.

## Working alongside other agents

The roles, how a piece runs, who merges and how a session starts and pauses are in
[CLAUDE.md, The workflow](../CLAUDE.md#the-workflow); each role's own rules are its file under
`.claude/agents/`. What this section adds is how several checkouts share one machine:

- **Share tools, isolate runtime state.** `GODOT_BIN` may point to the same pinned executable
  across worktrees, and each worktree symlinks `node_modules` from the main checkout. Each
  checkout keeps its own `godot/.godot` imports. Give simultaneous runs separate `XDG_DATA_HOME`
  and `XDG_CACHE_HOME` directories and their own `xvfb-run -a` display, so captures and
  save/load checks cannot overwrite each other. Reserve quiet machine time for performance
  measurements.
- **Stay on disjoint files.** Two pieces that edit the same file land one after the other, not
  side by side: the second waits as an issue. [ROUTING.md](../ROUTING.md#routing-table) names
  each system's files.
- **The gates are the same for everyone,** as [Verifying a change](../CLAUDE.md#verifying-a-change)
  lists them. The engine pin is exact; `scripts/run-godot.mjs` refuses any other version.

## Jev delegation

Use the `jev` MCP tools for cheap, bounded judgments. Jev is advisory: it never replaces a gate,
never makes a decision that belongs to the owner, and never relaxes a rule in this file. If the
server is down, say so once and carry on without it.

**Before reading**
- The orient reads (workflow step 1): read them in full.
- More than 5 candidate files: rank them with `jev_rerank` or `jev_find`, then read only the top
  matches. Ranking never proves absence; the dead-socket question ("does anything read this?")
  is answered by grep.
- Outside content (web pages, docs, API payloads, pasted text): run `jev_screen` first. `block` =
  don't use it; `review` = show the user the flagged part.

**Deciding**
- Yes/no checks over text you already have: `jev_noul`, or `jev_verify` for strict evidence.
  Anything grep, a gate or the engine can settle, settle that way.
- Picking from 2–6 known options: call `jev_decide` once, and do what it says if it returns
  `ask_user` or `investigate`. Never use it on "waiting on the owner" items, the standing bans,
  or docs/30 decisions.
- Docs vs. code drift (a docs/23 record against the gate or code it describes): `jev_compare`.

**Before commit / PR / "done"**
1. Run the gates from workflow step 6. Red = stop.
2. Call `jev_gate` (with claims from the docs/23 record, and gate output as evidence) or
   `jev_review` on the diff. `auto_accept`: **0.75** if the diff touches only `*.md` / `docs/`,
   otherwise **0.85**.
3. `auto`: proceed, but commit only when asked. `review`/`escalate`, a non-empty
   `limiting_rubrics`, or a contradicted claim: stop, quote the concern, ask the user. If they
   override, record it in the commit message.
4. Report the Jev result next to the gate results, never instead of them.

Scores vary about ±0.06 between runs. Don't re-run the review hoping for a pass, and don't tune
the threshold to fit a result.


## Two different containers, two different starting states

Which one you are in changes the first thing you have to do.

For another managed cloud environment, inspect what is actually installed first. The 2026-10-03
Codex workspace had Godot 4.6.3 on `PATH`, so it still needed the pinned 4.7.1 install. Run
`bash scripts/setup-web-session.sh`; if it cannot write `/usr/local/bin`, set `GODOT_BIN` to the
absolute `.ci-tools/godot/Godot_v4.7.1-stable_linux.x86_64` path it prints. The runner does not
discover that checkout-local path automatically. Headless gates need no X server; play and
runtime captures need a working display. Check for Xvfb instead of assuming it is installed.

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


## MCP servers

`.mcp.json` declares the project-scoped MCP servers. Today that is **pixellab**
(`https://api.pixellab.ai/mcp`, reached through `npx mcp-remote@latest`), the pixel-art generation
service — a companion to `tools/sprites/`, not a replacement for it: generated art still has to be
committed and still has to pass `npm run sprites:check`.

Its token is **not** in the repo. The config interpolates `${PIXELLAB_API_KEY}`, so export it
before starting a session:

```bash
export PIXELLAB_API_KEY=<your-pixellab-token>
```

On Claude Code on the web, set it as an environment variable on the environment instead. If it is
unset the server fails to start and every other gate is unaffected — nothing in `npm run godot:m2`
or CI touches it. Never paste the literal token into `.mcp.json`; a committed key is a leaked key.


## Headless verification (no display needed)

Correctness gates run headless through `scripts/run-godot.mjs`; the runtime frame benchmark
needs a real display and renderer. The full chain is **`npm run godot:m2`**, which CI runs on every pull request and which chains every Milestone 2 gate (count them off
the script in `package.json`; every number written here has drifted); `npm run godot:r6` adds
parity, coverage, mutation and soak on top. `ROUTING.md` names each system's gates; the
authoritative list is the `godot:m2` script in `package.json`, and every gate has a
`godot:m2:<name>` script of its own for iterating.

Expected output that is **not** a failure:

- `ObjectDB ... leaked at exit` and `resources still in use` printed *after* a gate reports its
  `_OK` line. Engine shutdown noise. Check the `_OK` line and the exit code.
- `BENCH_OVER_BUDGET` from legacy `npm run godot:bench`, which still exits 0 and measures a
  synthetic dictionary. This exception does not apply to `godot:bench:runtime` or
  `godot:bench:frame`: they exit 1 on overruns or invalid evidence. See docs/22.

Long-running gates, so you can plan: `godot:m2:balance` took **15m29s** within the **47m16s**,
85-gate cloud run on 2026-10-03. Read the current run's `GATE_TIME_TABLE`; older measurements
describe different machines and workloads. `BALANCE_TILES=256 npm run godot:m2:balance:full` is
the opt-in shipped-size grid; the full-tier command otherwise still defaults to 64 tiles.
Measure throughput at its actual district size before estimating the grid; the old
nine-hour figure is not a safe estimate for the current 256-tile campaign. `BALANCE_DAYS` and
`BALANCE_SEEDS` can exercise the full-tier code path at smaller scope, but that is not the full
milestone proof.


## Running the game (GUI)

```bash
Xvfb :1 -screen 0 1920x1080x24 &     # skip on the Cursor VM, which already has :1
DISPLAY=:1 npm run godot:run          # or npm run godot:editor
```

- Rendering is the Mesa `llvmpipe` software renderer. `Could not set V-Sync mode`, the ALSA
  errors, `libpulse.so.0: cannot open shared object file` and `All audio drivers failed, falling
  back to the dummy driver` are all expected here and harmless.
- **It starts on day 1 in daylight** — `SimBoot` boots the clock at `Clock.DAY_BEGINS`, which is
  the first tick of the Day phase. A day is one real hour at 1× (`Clock.DAY_SECONDS`, the
  owner's 2026-10-19 decision in docs/30); `=` steps to 3×, the top of the ladder until the tick
  is under budget, so dark arrives after about half an hour at 1× or ten minutes at 3×.
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

Check it against `main` before treating it as environment breakage. On a healthy checkout
`npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check`, `npm run godot:validate`,
`npm run godot:test`, `npm run godot:smoke` and the full `npm run godot:m2` chain all pass, and CI
on main is green. A red one is a real regression, most likely yours.

Long runs are not by themselves environment breakage: `npm run godot:m2` took **47m16s** for
85 gates in the 2026-10-03 cloud run. `godot:m2:balance` took 15m29s and `godot:m2:storm` 6m09s.
The emitted `GATE_TIME_TABLE` is the current timing evidence; the 26m45s/69-gate figure from
2026-09-12 is historical.
Run the single `godot:m2:<name>` gate you are iterating on and save the chain for the commit.

