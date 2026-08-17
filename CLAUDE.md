# CLAUDE.md

Read this before touching anything. `AGENTS.md` covers environment setup; this file covers what
the project is and what must not be broken.

## Godot is the only implementation that ships

The game is `godot/` — Godot 4.7.1 (Compatibility), typed GDScript. New behaviour goes here and
nowhere else. `npm run build` is `godot:export`, and Pages publishes the Godot build at `/`.

**But the TypeScript oracle is still in the tree and still runs in CI, which this file used to
deny.** `src/`, `test/`, `bench/` and the Vite/vitest configs are all present on `main`, and the
`check` job runs `npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check` and
`npm run bench` against them alongside the Godot gates. As of this writing all of it is green:
**46 files / 599 tests**. It is a *frozen reference*, not a second product — do not add features
to it, do not port Godot changes into it — but do not delete it or let it go red either, because
CI will stop you. Its frozen parity fixtures under `godot/parity/` are what `npm run godot:test`
compares against, and tag `ts-oracle-final` is the rollback point.

The engine pin is exact. `scripts/run-godot.mjs` rejects any engine whose `--version` does not
start with `4.7.1`, and the same version and SHA-512 appear in `.github/workflows/ci.yml`,
`pages.yml`, and `scripts/setup-web-session.sh`. Changing one means changing all of them.

## Verifying a change

Correctness for a Godot change is the Godot gates. `npm run godot:m2` is the one to run before
every commit — it chains all of them and takes a few minutes:

```bash
npm run godot:smoke      # project boots            → GODOT_PROJECT_SMOKE_OK
npm run godot:validate   # content registry
npm run godot:test       # R1 parity vs the frozen fixture
npm run godot:m2         # all Milestone 2 gates    → M2_LETHALITY_OK et al
npm run godot:m2:balance # the balance harness, fast tier → M2_BALANCE_OK (~85 s, inside godot:m2)
npm run godot:ban:healthbar  # the health-bar ban   → BAN_HEALTH_BAR_OK
npm run godot:check:appearance # the sprite pipeline → APPEARANCE_OK
npm run godot:check:hud      # HUD speaks in prose   → HUD_OK
npm run godot:r6         # parity, coverage, mutation, soak, bench, validate
npm run godot:run        # play it (DISPLAY=:1 on a headless VM)
```

`godot:m2` prints `ObjectDB ... leaked at exit` and `resources still in use` *after* it reports
success. That is engine shutdown noise, not a failure — check the `_OK` line and the exit code.

CI's `check` job runs `godot:m2` **and** the TypeScript side (`npm test`, `typecheck`, `lint`,
`format:check`), and its `performance` job runs `npm run bench` and `npm run bench:frame`.
Touching a `.ts` file or any prettier-covered path means running those too. Note
`npm run godot:bench` prints `BENCH_OVER_BUDGET` on these containers and still exits 0 — those
budgets are calibrated against compiled TypeScript and headless GDScript is an interpreter; see
docs/22. (`npm run bench` is the separate TypeScript benchmark, and it does gate.)

A fresh Claude Code on the web container has no engine; `.claude/hooks/session-start.sh`
installs it. To do it by hand: `bash scripts/setup-web-session.sh`. It does **not** install export
templates, so `godot:export` / `godot:smoke:exports` need `SETUP_EXPORT_TEMPLATES=1`.

## Standing bans

These are settled. Re-read the linked clause before proposing a change to either; do not quietly
amend them.

**No health bar, and no way to compute one.** The
[condition view](docs/05-health-injury.md#the-condition-view) hands the screen a state and a
sentence per part — `{parts:[{part, state, prose}], stance, worst}` — and deliberately carries
**no integrity value, no maximum, and no fraction**, so a fill is not merely discouraged, it is
not computable from what the screen has. `godot/sim/condition.gd` is the one builder;
`npm run godot:ban:healthbar` serialises its output and asserts the absence, with a key
allowlist that fails the moment a numeric field is added. That gate is the ban made mechanical —
if it goes red, re-read
[hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)
rather than widening the assertion.

**Information stays scarce and unreliable.** A bite can present as a scratch. Do not add
certainty the player is not supposed to have — exact quality, counts, positions, or anything
through walls.

**The HUD speaks in words.** `npm run godot:check:hud` allows **no digits on the player HUD
except the day counter**. Needs, condition, and attention all arrive as prose from sim read
models (`needs.hud_clause`, `sim/condition.gd`, `sim/attention_read.gd`). The numeric
developer sheet still exists and is still useful — it lives behind the `M` toggle, where the
gate ignores it.

**Budgets are correctness.** [docs/00 pillar 6](docs/00-vision.md): a feature that breaks budget
does not ship until it is fixed. Exceeding a budget fails the build at the same severity as a
failing test.

## Where the work is

Milestone 2, the vertical slice — one district, a handful of survivors, enough of every system to
find out whether the loop is fun. Its exit criterion is ten in-game days, permanent loss,
succession, and still wanting another run.

The current design pass pauses new NPCs and adjacent feature scope; **Mara remains the test
survivor.** Focus is the first playable survival loop: wounds, treatment, stamina, and recovery.
The design record is
[`.hermes/plans/2026-08-17_065300-vertical-slice-design.md`](.hermes/plans/2026-08-17_065300-vertical-slice-design.md).
It captures decisions, not shipped behavior: do not move any health/injury checkbox until code and
a focused Godot check prove it.

Finish that contract and a reproducible 72-hour acceptance scenario before adding survival code.
Keep all effects sim-owned and command-driven; player-facing state remains prose/diegetic and must
not weaken the condition-view health-bar ban. The full balance grid and human ten-day playtest are
still required Milestone 2 proof, deferred behind this focused survival loop rather than cancelled.

[HANDOFF.md](HANDOFF.md) is the authority on what is built; [docs/23](docs/23-roadmap.md) on what
is intended; [docs/30](docs/30-decisions.md) on why something that looks arbitrary is shaped that
way. Read 30 before changing something that looks arbitrary.

## Conventions

- Typed GDScript. `godot/sim/` is deterministic and must not read presentation state.
- Content is data under `godot/content/`, validated by `npm run godot:validate`. Note the
  validator is **shallow** — it checks top-level property types and rejects unexpected top-level
  keys, but does not recurse into nested objects. A nested shape needs its own gate; see
  `check_appearance.gd`.
- **How a thing looks is content, not code.** `appearance: {sprite, tint}` in a content entry;
  `presentation/appearance.gd` resolves it and falls back to role colours when there is no art.
  Never reintroduce a `if id == "zombie.x": col = ...` branch in the draw loop — that is what
  this replaced, and `godot:check:appearance` fails if the tints move back into code.
  `godot/assets/sprites/README.md` has the 32×16 grid and anchor convention.
- Prose is hand-wrapped; `.prettierignore` excludes `docs/` and `*.md` for that reason.
- **A gate that cannot fail is worse than no gate.** Every assertion wants a true positive *and* a
  true negative — `check_ban_health_bar.gd` set the convention after a field that was always
  `false` passed a "no leak" test, and `check_m2_npc_combat.gd` follows it. The same rule caught a
  seed loop that ran four seeds and proved one. If an assertion has no data to judge (a shortened
  campaign the director never pressured), make it **say so and skip**, never pass quietly.
- Update `HANDOFF.md` in the same commit as the work it describes — it has drifted four times,
  most recently by ~34 Milestone 2 items that had shipped and never been ticked.
  `npm run godot:check:handoff` (`HANDOFF_OK`) now enforces the two rules that make it
  recoverable: **move a box into its `Done` group** rather than ticking it in place, and give
  every `[x]` an italic `*(...)*` note naming the gate or file that proves it. Where only half
  an item shipped, leave it open and say which half.

## Traps that have already cost someone a session

Each of these was found the expensive way. They are not style opinions.

- **Packed arrays are values in GDScript.** `(dict["key"] as PackedStringArray).append(x)` appends
  to a *copy* and silently does nothing. This made a four-seed harness report four identical runs.
  Use a plain `Array` for anything you mutate through a Dictionary.
- **A survivor's body parts do not share a scale.** A healthy head is 15, a hand 10, a torso 40 —
  so `body[part] < 15` means "critically injured" on a torso and "perfectly fine" on a head. There
  is exactly one place that normalises: `SimHealth.part_state`, which returns
  Unhurt/Hurt/BadlyHurt/Unusable. Compare states, never raw integrity.
- **`entity.killed` fires more than once for the same individual** — `health.gd` on a destroyed
  head, `infection.gd` on a put-down and again on turning. Counting events counts one death three
  times. De-duplicate by entity id.
- **The content validator will not catch a nested key.** It checks top-level types only. A wrong
  key inside an `armor` block sat in `item.wrap.cloth` for weeks giving zero arm protection, and
  only a purpose-built gate found it.
- **Throughput, measured:** ~1,085 ticks/second headless on this container, so a game day (288,000
  ticks) is about three minutes and a ten-day campaign about forty-five. Anything phrased as "run
  a few campaigns" is an overnight job — check the arithmetic before promising a grid.

## Seeing it actually run

`npm run godot:run` needs a display (`DISPLAY=:1`; start one with
`Xvfb :1 -screen 0 1920x1080x24 &`). It boots on **day 1 in daylight**, not at night.

There is no `scrot`, `imagemagick` or `ffmpeg` in these containers, so screenshots come from Godot
itself: run a throwaway `SceneTree` script that instantiates `res://presentation/main.tscn` into
`root` (the way `test/project_smoke.gd` does), drives it, and calls
`root.get_texture().get_image().save_png(path)`. That gives you the real app — real HUD, real
presentation, real sim — and lets you set up a scenario before capturing it. Delete the script
afterwards; it is a driver, not a fixture.

The audio and V-Sync errors on boot (`libpulse.so.0`, ALSA, `All audio drivers failed`) are
expected on a headless container and harmless.
