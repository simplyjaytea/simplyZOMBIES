# CLAUDE.md

Read this before touching anything. `AGENTS.md` covers environment setup; this file covers what
the project is, how a unit of work runs, and what must not be broken.

## Godot is the only implementation that ships

The game is `godot/` — Godot 4.7.1 (Compatibility), typed GDScript. New behaviour goes here and
nowhere else. `npm run build` is `godot:export`, and Pages publishes the Godot build at `/`.

**But the TypeScript oracle is still in the tree and still runs in CI, which this file used to
deny.** `src/`, `test/`, `bench/` and the Vite/vitest configs are all present on `main`, and the
`check` job runs `npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check` and
`npm run bench` against them alongside the Godot gates. As of this writing all of it is green:
**45 files / 594 tests** (one file, `handoff.test.ts`, retired with the checkbox ledger it
counted — see the note on `HANDOFF.md` under Conventions). It is a
*frozen reference*, not a second product — do not add features
to it, do not port Godot changes into it — but do not delete it or let it go red either, because
CI will stop you. Its frozen parity fixtures under `godot/parity/` are what `npm run godot:test`
compares against, and tag `ts-oracle-final` is the rollback point.

The engine pin is exact. `scripts/run-godot.mjs` rejects any engine whose `--version` does not
start with `4.7.1`, and the same version and SHA-512 appear in `.github/workflows/ci.yml`,
`pages.yml`, and `scripts/setup-web-session.sh`. Changing one means changing all of them.

## The workflow

How a unit of work goes through this repo — the same loop for a human, an agent, or both. The
pattern that works here is the **slice**: one named piece, built together with the gate that can
fail it, measured if it claims anything about balance, recorded in the same commit. The sessions
that followed this loop landed six slices in a run; the sessions that did not are where the traps
section came from.

1. **Orient before touching anything.** This file top to bottom, then
   [what's left](docs/23-roadmap.md#whats-left-in-milestone-2) for what is open and
   [the record, by system](docs/23-roadmap.md#the-record-by-system) for how the neighbouring
   systems landed. `HANDOFF.md` names what is waiting on the owner. Read
   [docs/30](docs/30-decisions.md) before changing anything that looks arbitrary — it usually
   is not.
2. **Pick one named piece from what's left.** They are sized to land in a session. The "waiting
   on the owner" group is not pickable — those are decisions, and deciding one unilaterally is
   the one mistake at this stage no gate will catch. Work that is not on the list gets named and
   added there first (or asked about), never smuggled in beside a slice.
3. **Design inside the seams.** Effects are sim-owned and command-driven; `godot/sim/` never
   reads presentation state; how a thing looks is content; new randomness gets its own named RNG
   stream. Anything player-facing goes through the standing bans *before* it is built, not after.
4. **Build the gate with the thing.** Every assertion wants a true positive *and* a true
   negative, and every mechanism wants the assertion that something **reads** it — the
   dead-socket rule, paid for eight times this milestone. An assertion with no data to judge says
   so and skips; it never passes quietly.
5. **Measure balance claims; never theorise them.** A claim about campaign outcomes comes from a
   throwaway driver, run before and after on the same driver — two consecutive guesses at the
   harness each cost a full run to disprove. Check the throughput arithmetic first (~1,085
   ticks/s headless: a game day is ~3 minutes, a ten-day campaign ~45). Drivers are deleted
   afterwards; anything that stays behind gets a gate keeping it honest.
6. **Verify before committing.** `npm run godot:m2`, always. A content edit is not verified until
   `npm test` has also run — the frozen oracle's Ajv recurses where `godot:validate` does not.
   Touching a `.ts` file or any prettier-covered path adds `typecheck`, `lint`, `format:check`.
7. **Record in the same commit.** Delete the piece from what's left; write its record — named,
   gated, measured — into the record, by system. Update `HANDOFF.md` only when what is waiting on
   the owner changed. Prose is hand-wrapped.
8. **Leave it honest.** No checkbox ledgers anywhere; every claim names the gate that proves it;
   where only half a thing shipped, the record says which half.

## Verifying a change

Correctness for a Godot change is the Godot gates. `npm run godot:m2` is the one to run before
every commit — it chains all of them and takes a few minutes:

```bash
npm run godot:smoke      # project boots            → GODOT_PROJECT_SMOKE_OK
npm run godot:validate   # content registry
npm run godot:test       # R1 parity vs the frozen fixture
npm run godot:m2         # all Milestone 2 gates    → M2_LETHALITY_OK et al
npm run godot:m2:balance # the balance harness, fast tier → M2_BALANCE_OK (~85 s, inside godot:m2)
npm run godot:m2:sight   # sightlines and memory     → M2_SIGHT_OK
npm run godot:m2:attach  # attachment slots          → M2_ATTACH_OK
npm run godot:m2:wounds  # severity, the bleed clock  → M2_WOUNDS_OK
npm run godot:m2:treatment # pressure and bandaging   → M2_TREATMENT_OK
npm run godot:m2:recovery  # healing, and what is permanent → M2_RECOVERY_OK
npm run godot:ban:healthbar  # the health-bar ban   → BAN_HEALTH_BAR_OK
npm run godot:check:appearance # the sprite pipeline → APPEARANCE_OK
npm run godot:check:hud      # HUD speaks in prose   → HUD_OK
npm run godot:r6         # parity, coverage, mutation, soak, bench, validate
npm run godot:run        # play it (DISPLAY=:1 on a headless VM)
```

Those are the ones worth naming, not all of them: `godot:m2` chains **34**, and the authoritative
list is the `godot:m2` script in `package.json` — read it there rather than trusting a copy here,
because a copy here is one more thing that drifts. Run an individual gate with the
`godot:m2:<name>` script beside it when you are iterating; run the chain before you commit.

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
sentence per part — `{parts:[{part, state, prose, wounded, infected, armored, bleeding, bandage}],
stance, worst}`, whose every added field is a word or a boolean — and deliberately carries
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

New NPCs and adjacent feature scope stay paused; **Mara remains the test survivor.** The design
record is
[`.hermes/plans/2026-08-17_065300-vertical-slice-design.md`](.hermes/plans/2026-08-17_065300-vertical-slice-design.md).
It captures decisions, not shipped behavior: nothing counts as done until code and a focused Godot
check prove it.

[docs/23](docs/23-roadmap.md) is the authority on what is intended **and**, in its milestone status
sections, on what is built and what remains (the old per-item checkbox `HANDOFF.md` was retired
into it and its itemised history lives in git; the `HANDOFF.md` in the tree today is the short
pointer described under Conventions, and it is not a status ledger). Its
[what's left](docs/23-roadmap.md#whats-left-in-milestone-2) section names every
remaining Milestone 2 piece — small, modular, named so the name alone says the work — and its
[record, by system](docs/23-roadmap.md#the-record-by-system) holds the evidence for what landed;
a landing moves its piece from the first to the second in the same commit.
[docs/30](docs/30-decisions.md) is the authority on why something that looks arbitrary is shaped
that way. Read 30 before changing something that looks arbitrary. This file does not restate their
contents — the one copy of the status lives in docs/23, because every duplicated copy of it has
drifted. Three things about the current state matter enough to repeat anyway:

- **The survival loop is built end to end, gated, and switched off.** Grabs, bites, located
  bleeding wounds, pressure and bandaging, recovery, infection — all behind
  `SimShambler.GRABS_ENABLED = false`. Six recorded reasons for the flag have each been answered
  (docs/23's flag record is the seed-by-seed history); what stands now is **colony shape** — a
  bigger colony, or one posted closer — which is a design call about the slice. **Do not decide
  it, or flip the flag, unilaterally.** Relaxing `survivors_end >= 1` has been considered and
  rejected. The swipe (`godot:m2:swipe`) is the one zombie damage path outside the flag, so
  ordinary play exercises wounds, bleeding and treatment — but never infection.
- **The presentation is flat top-down, not isometric** — an independent track that touched nothing
  under `godot/sim/`. `docs/00-vision.md` carries the reversal, docs/30 what it made structural,
  and the art entries in what's left the ordered next steps; the style pick is the owner's.
- **The dead-socket pattern.** This milestone has turned up **nine** pieces of code that were
  complete, correct, often gated, and read by nothing: `crawlFactor`, the `Staggered` state,
  `sepsis.checked`, `injury.sustained`, `item.painkillers.blister`, `SimVisibility` for everybody
  but the player, rule 4's variance floor behind an `if size == 0` that could never be true,
  `SimDirector.snapshot_of`, and — found by the review sweep — `SimStances.CAN_AIM`, which had said
  "a sprint cannot aim" since the ladder landed while `SimRanged` let a sprinting survivor fire.
  **A gate asserting that a helper returns the right number does not assert that anything reads
  it.** When you add a mechanism, add the assertion that something reaches it —
  `check_m2_attach.gd`'s "is this findable in any loot table" is the cheapest example. The sweep
  left three more sockets named but unfixed (`sim/spatial/hash.gd` entire, `SimThreat.threat_within`,
  `SimStances.eye_of`); they are in
  [docs/23's defect list](docs/23-roadmap.md#whats-left-in-milestone-2).

Keep all effects sim-owned and command-driven; player-facing state remains prose/diegetic and must
not weaken the condition-view health-bar ban. The full balance grid and human ten-day playtest are
still required Milestone 2 proof, deferred rather than cancelled.

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
  `godot/assets/sprites/README.md` has the top-down grid and anchor convention.
- Prose is hand-wrapped; `.prettierignore` excludes `docs/` and `*.md` for that reason.
- **A gate that cannot fail is worse than no gate.** Every assertion wants a true positive *and* a
  true negative — `check_ban_health_bar.gd` set the convention after a field that was always
  `false` passed a "no leak" test, and `check_m2_npc_combat.gd` follows it. The same rule caught a
  seed loop that ran four seeds and proved one. If an assertion has no data to judge (a shortened
  campaign the director never pressured), make it **say so and skip**, never pass quietly.
- Update [docs/23's milestone status section](docs/23-roadmap.md#where-milestone-2-stands) in the
  same commit as the work it describes (workflow step 7). `HANDOFF.md` is a short session handoff
  that points at docs/23 and names what is waiting on the owner — **never** per-item checkboxes.
  Its checkbox predecessor drifted four times, most recently by ~34 shipped-but-unticked items,
  which is why status is condensed prose with each claim naming the gate that proves it. No gate
  enforces this any more (`godot:check:handoff` retired with the old file), so the discipline is
  the convention. Where only half an item shipped, say which half.

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
- **But the frozen TypeScript oracle validates the same content with Ajv, and Ajv *does* recurse.**
  The two validators read one shared tree under `godot/content/`, and they disagree about depth:
  `npm run godot:validate` passes a nested violation that `npm test` rejects with a hard
  `ContentError`. So a content edit is not verified until **both** have run — a new enum value, a
  new nested key, anything under `content/schemas/`. This cost a red CI on a change where
  `godot:validate`, `godot:m2` and a purpose-built gate were all green: the map schema's
  `loot[].table` enum still listed two locations and the oracle refused the third.
- **`velocity` uses `dx`/`dy`; `position` uses `x`/`y`.** Writing `vel["x"] = 0.0` adds a key
  nothing reads and raises nothing — a pin that silently does not pin. `shambler.pin` and
  `treatment.pin` are the precedent for both the phase slot (`movement`, order −1) and the names.
- **`events.publish()` only queues; handlers run at `drain()`, at the *end* of `world.step()`.**
  So a fixture that publishes an event and then reads the result without stepping sees nothing
  ("2 hits, 0 wounds" cost a while), and an event published *into* a tick lands after that tick's
  systems have already run — a stagger arriving on the tick a channel completes is genuinely too
  late to stop it. Both are correct behaviour; write the test around them rather than tolerating a
  fudge factor inside the measurement.
- **GDScript lambdas capture primitives by value.** A closure assigning to an outer `int` or
  `bool` mutates its own copy, so an accumulator written inside an event handler reads back
  unchanged. Use an `Array` or `Dictionary` — reference types — for anything a handler accumulates.
  Same family as the packed-array trap above. This one keeps being paid for: it most recently made
  a jam gate report "never cleared" for a jam that had cleared exactly on schedule, because the
  `cleared_at` an event handler assigned to was a captured `int`. The failure mode is the worst
  kind — the gate goes red and blames the code under test.
- **Diagnose the balance harness, do not theorise at it.** Two consecutive guesses at why a flag
  flip wiped colonies (blood loss; then NPCs having no way to treat themselves) were both wrong,
  and each cost a full harness run to disprove. A throwaway `SceneTree` driver that boots
  `SimBoot.playable(seed, …)`, runs the same day count and prints `entity.killed` causes answers it
  in one run. Delete the driver afterwards.
- **A Dictionary keyed by an entity id does not survive a save.** Components round-trip through
  JSON, and JSON has no integer keys — a `{entity: record}` component comes back with String keys
  and the very first `seen[entity]` after a load misses silently, with no error and no wrong
  number, just a memory that is empty for reasons nothing reports. Store per-entity collections
  as an **Array of records** (`{"e": id, …}`) and scan; `sim/modules/sightings.gd` is the
  precedent. Same family as the packed-array and lambda-capture traps above: a value that is
  quietly not what you stored.
- **`entities.despawn` does not remove components, and `components.query` does not check alive.**
  Despawning a body leaves every one of its components in place, so anything counting a population
  by `query` still counts it. This made a director harness report "56 quiet nights in a row" --
  the culled bodies still filled `LIVE_CAP`, so every night after the fourth was refused rather
  than drawn. Remove the component you are counting, not just the entity.
- **`Array.erase()` and `Array.find()` on Dictionaries match by *value*, not by reference.**
  Measured in 4.7.1: with `a` and `b` two different Dictionaries holding identical content and
  `arr = [a, c, b]`, `arr.find(b)` returns **0** and `arr.erase(b)` removes **`a`**. So an array of
  records — a wound list, a sighting list, anything keyed by content rather than by id — cannot be
  edited by handing the element back. Find the index yourself on a field that is unique, or give
  the records an id. `wounds.gd`'s closing loop is safe only because two value-identical wounds
  necessarily close on the same tick; one added field away, it would not be.
- **A `has_method()` guard naming a method that does not exist is silently false forever.** It
  raises nothing, logs nothing, and quietly turns the whole branch into a no-op — `world.despawn`
  guarded its modifier cleanup on `has_method("removeScope")` against a method called
  `remove_scope`, so no despawned entity ever had its modifiers cleared and every save carried
  them. GDScript's `has_method` does **not** convert between snake_case and camelCase for script
  methods. Same family as `vel["x"]`: a name that looks right and reaches nothing. If you write
  one, grep for `func <name>(` before you trust it.
- **A `static var` is shared between the two worlds a gate boots.** docs/30 records this twice for
  components (`putDown`, `mourned`) and it was still live in the kernel: `SimBoot` kept "the last
  world that called `attach_kernel`" in a static, and the attention handlers wrote into *that*
  world's field rather than the publisher's. World A published magnitude 500 and A's own field read
  0.0000 while world B's read 500.0000 — on the spine, under every two-world assertion about noise
  or scent. Per-world state belongs on the world or in a closure over it; a closure over an object
  is safe, because the lambda-capture trap above is about primitives.
- **Throughput, measured:** ~1,085 ticks/second headless on this container, so a game day (288,000
  ticks) is about three minutes and a ten-day campaign about forty-five. Anything phrased as "run
  a few campaigns" is an overnight job — check the arithmetic before promising a grid.

## Seeing it actually run

`npm run godot:run` needs a display and boots on **day 1 in daylight**, not at night. The
environment detail lives in `AGENTS.md` — starting Xvfb, the two container types, screenshots
through a throwaway Godot `SceneTree` script (there is no `scrot`/`imagemagick`/`ffmpeg` here;
the script is a driver, so it is deleted afterwards), and the audio/V-Sync boot noise that is
expected and harmless.
