# CLAUDE.md

Read this before touching anything. `AGENTS.md` covers environment setup; this file covers what
the project is and what must not be broken.

## Godot is the only implementation

The game is `godot/` — Godot 4.7.1 (Compatibility), typed GDScript. There is no second
implementation to keep in sync and no parity work to do.

A TypeScript/Canvas "oracle" was the pre-rebuild implementation. It was retired after the R7
cutover; its frozen parity fixtures remain under `godot/parity/` and are still gated by
`npm run godot:test`. Do not reintroduce `src/`, `test/`, `bench/`, or a Vite/vitest config —
CI fails if they reappear.

The engine pin is exact. `scripts/run-godot.mjs` rejects any engine whose `--version` does not
start with `4.7.1`, and the same version and SHA-512 appear in `.github/workflows/ci.yml`,
`pages.yml`, and `scripts/setup-web-session.sh`. Changing one means changing all of them.

## Verifying a change

There is no `npm test`. Correctness is the Godot gates:

```bash
npm run godot:smoke      # project boots            → GODOT_PROJECT_SMOKE_OK
npm run godot:validate   # content registry
npm run godot:test       # R1 parity vs the frozen fixture
npm run godot:m2         # all Milestone 2 gates    → M2_LETHALITY_OK et al
npm run godot:ban:healthbar  # the health-bar ban   → BAN_HEALTH_BAR_OK
npm run godot:check:appearance # the sprite pipeline → APPEARANCE_OK
npm run godot:check:hud      # HUD speaks in prose   → HUD_OK
npm run godot:r6         # parity, coverage, mutation, soak, bench, validate
npm run godot:run        # play it (DISPLAY=:1 on a headless VM)
```

`godot:m2` prints `ObjectDB ... leaked at exit` and `resources still in use` *after* it reports
success. That is engine shutdown noise, not a failure — check the `_OK` line and the exit code.

A fresh Claude Code on the web container has no engine; `.claude/hooks/session-start.sh`
installs it. To do it by hand: `bash scripts/setup-web-session.sh`.

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

The build order is in [docs/23](docs/23-roadmap.md#build-order). Steps 1–4 and most of 6 have
landed (lethality, stats, roster, district, ranged, needs, jobs, web, upkeep, succession). The
open block is **step 5: building, then the slice director** — see the Building and Director
sections of [HANDOFF.md](HANDOFF.md).

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
- Update `HANDOFF.md` in the same commit as the work it describes — it has drifted four times,
  most recently by ~34 Milestone 2 items that had shipped and never been ticked.
  `npm run godot:check:handoff` (`HANDOFF_OK`) now enforces the two rules that make it
  recoverable: **move a box into its `Done` group** rather than ticking it in place, and give
  every `[x]` an italic `*(...)*` note naming the gate or file that proves it. Where only half
  an item shipped, leave it open and say which half.
