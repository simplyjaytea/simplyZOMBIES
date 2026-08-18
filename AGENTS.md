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
  runs `npm run bench` / `npm run bench:frame`. All of it is currently green (45 files, 594
  tests). `npm run dev` serves it via Vite on `127.0.0.1:5174` if you need to look at it.

Standard commands live in `package.json` scripts, `README.md`, and `.github/workflows/ci.yml`;
use those as the source of truth.

## Current work

[docs/23's Milestone 2 status section](docs/23-roadmap.md#where-milestone-2-stands) is the authority
on implemented reality — each claim there names the gate that proves it. (`HANDOFF.md` was retired
into it; the itemised backlog history is in git.) The active design record is
`.hermes/plans/2026-08-17_065300-vertical-slice-design.md`; it is **not** implementation evidence.
`CONTEXT.md` holds the slice vocabulary — what to call needs, jobs, stances, and their states — so
prose and code stay in one language.

- Pause new NPCs and adjacent feature scope. Mara remains the sole test survivor.
- **The survival loop is built and switched off.** Wounds carry a severity and bleed
  (`M2_WOUNDS_OK`), pressure and bandaging stop them and the five infection verbs are reachable
  by command (`M2_TREATMENT_OK`), and recovery closes wounds and climbs integrity back
  (`M2_RECOVERY_OK`). `SimShambler.GRABS_ENABLED` is still `false`, so nothing wounds a survivor
  in ordinary play.
- **Bite lethality during a hold has been answered; the flip has not.** All four levers landed
  together — held-bite hit weights (head 0.05 against a free swing's 0.20), `REPEAT_BITE_TICKS`
  40 → 80, part-scaled bite damage `maxf(2.0, minf(BITE_DAMAGE, 0.35 × part max))`, and a sooner,
  cheaper struggle — and `M2_CONTACT_OK` grew HELD-AIM and BITE-SCALE to hold them.
- **Colony agency has been answered too.** A held survivor nobody is answering for struggles on
  instinct after `STRUGGLE_INSTINCT_TICKS`, with F still faster and still resetting the clock
  (INSTINCT in `M2_CONTACT_OK`); a kit weapon is equipped rather than packed, so nobody boots
  unarmed (`SimSurvivors._hold_it`, ARMED in `M2_BALANCE_OK`); and `npc.combat` prefers a shambler
  that is holding someone (HOLDER in `M2_NPC_COMBAT_OK`). The shipped fast tier records the
  colony's first kills at all as a result — 6 on seed 404, 1 on 90210.
- **The price of an escape has been answered too.** Stamina recovers while held — `health.recover`
  ignores the recovery delay for a `grabbed` body and `world.gd` stops charging that body the
  posture drain, without which the first half does nothing (REGEN-HELD in `M2_CONTACT_OK`) — and a
  free survivor can break somebody else's hold: `SimShambler.try_begin_rescue`, the `H` key, the
  separate `shambler.rescue-intake` system, a rescue-first branch in `npc.combat`, and the new
  `grab.broken {victim, by, cause}` event (RESCUE and BROKEN in `M2_CONTACT_OK`, RESCUE-FIRST in
  `M2_NPC_COMBAT_OK`). Empty-tank ticks fell 38.3% → 13.3% on seed 404 and 48.9% → 0.0% on 90210.
- **Aid while held has been answered too.** `treatment._can_channel` grants a `grabbed` body exactly
  one channel — `pressure` on yourself — under seven arbitration rules written out at the top of
  `treatment.gd` (R1–R7: the exemption at begin and per tick, `grab.started` sparing only the
  victim's own press, a stagger still cancelling everything, struggle and press coexisting,
  `grab.broken` cancelling only the victim's own press, self-aid deferring during a break-away, and
  `context()` forcing `pressure` while held). AID-HELD and HELD-CONTEXT in `M2_TREATMENT_OK`;
  PRESS-THROUGH, STRUGGLE-DURING-PRESS, FLIGHT-CANCELS-PRESS and BREAKAWAY-DEFER in
  `M2_CONTACT_OK`.
- **The re-grab treadmill was a speed bug, and is fixed.** Both bodies are pinned during a hold, so
  a release starts inside `GRAB_METRES`, and `BREAK_AWAY_SPEED` 1.6 lost ground to the 1.68 seek —
  the gap *shrank* across the cooldown. Now 2.1, pinned against the seek by CLEAR-AWAY in
  `M2_CONTACT_OK`. Same file, same slice: `_gather_survivors` skips `corpse` carriers, because
  `identity` survives `_make_corpse` and shamblers were grabbing the dead (CORPSE).
- **R5 has been inverted, and the flag is still off.** R5 used to say a running press outranked a
  break-away, which cancelled the churn fix for exactly the survivors using the aid. It now says the
  opposite — `treatment.escape-releases-press` ends the victim's own self-pressure when
  `grab.broken` names them, and only that, R2's exact mirror. Measured on four seeds with grabs
  forced on: grabs 214 → 150 and 212 → 166, bites 136 → 88 and 122 → 65, and re-grab windows longer
  than the cooldown appear at all. It costs the clotting — presses completed go 25/9/26 → **zero**
  on every seed, because a press cancelled at every escape banks nothing — and 404 and 90210 still
  end `0/2` by blood loss.
- **The next step is still a design decision, not code, and the residual is now measured.** A
  break-away released against a wall does not move: over three days of seed 404 the committed escape
  heading is blocked on both axes on 86% of `breakAway` ticks, and the body covers 0.010 m per tick
  against a nominal 0.105, because `_break_away` takes its heading once and `movement.integrate`
  zeroes a blocked axis. The candidates — give a break-away somewhere to go, let a press bank its
  progress, or cut contact rarity — are all design calls. **Do not pick an answer unilaterally**,
  and note that relaxing `survivors_end >= 1` has been considered and rejected — see the full
  measurement in docs/23's Milestone 2 status section and the "Where the work is" section of
  `CLAUDE.md`.
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
