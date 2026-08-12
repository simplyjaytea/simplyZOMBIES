# Handoff

**Start here if you are picking this up cold** — a person or a fresh session. This is the engineer's
document: what is built, what is being built, what is next, and the roadmap through the vertical
slice. It replaced `TODO.md`, which used to hold the backlog separately and drifted from this file
three times.

Three other places to know about, and nothing else is required reading:

| | |
|---|---|
| [README.md](README.md) | The pitch, and the index of all 31 documents. User-facing. |
| [docs/23-roadmap.md](docs/23-roadmap.md) | The slice **as designed** — milestones, the 10 risks, the reasoning. This file owns what is *built*; 23 owns what is *intended*. |
| [docs/30-decisions.md](docs/30-decisions.md) | The decision records. Fourteen entries of "what this chunk of work made structural" — read it before changing something that looks arbitrary. |

---

## Where things stand

| | |
|---|---|
| **Phase** | **Milestone 1, the spine — in progress.** Milestone 0 is closed with no open boxes. **All three attention channels are live.** |
| **It is playable** | Shout and the district walks toward you in a minute. Say nothing and it still finds you, in an hour. You cannot see through a wall, and at midnight you see **two metres** — until you find a candle. **How you move is now the decision**: five rungs from a crawl to a sprint, each with its own speed, its own noise and its own price, and crouching behind a car hides you from what you can no longer see either. You start with nothing. |
| **What is left of Milestone 1** | **Grabs and bite risk.** Movement stances landed, and with them the survivor's body and the [condition view](docs/05-health-injury.md#the-condition-view). See [Do this next](#do-this-next). |
| **Merged so far** | [#1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) design docs · [#2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) attention spike · [#3](https://github.com/simplyjaytea/simplyZOMBIES/pull/3) Milestone 0 · then the noise spine, scent, multiplayer as design, visibility, the ground, the day, items and the grid, and [#19](https://github.com/simplyjaytea/simplyZOMBIES/pull/19) hot reload |
| **In flight** | Nothing. |
| **Pulled forward on purpose** | **Items and the grid inventory**, and now **the condition view** — both Milestone 2, both landed early at the owner's request. The condition view came in with the stances because a paperdoll is a picture of a posture, and building the two separately means two answers to what crouching looks like. The figure itself is now an **outline diagram** rather than the body from the street — see [the decision](docs/30-decisions.md#what-the-outline-figure-changed). |
| **Specified but deliberately unbuilt** | [Multiplayer](docs/27-multiplayer.md) (Milestone 3), [z-levels](docs/23-roadmap.md#deferred-z-levels), [aiming](docs/09-combat.md#aiming), and docs/05's [located injuries](docs/05-health-injury.md#injury-types) — the survivor has a body with six parts that can be hurt, but no wound *types* and no infection. **No engine code.** |

### Counting the backlog

| Milestone | `[x]` done | `[~]` in progress | `[ ]` todo | State |
|---|---|---|---|---|
| 0 — Foundations | 39 | 0 | 0 | ✅ **Closed.** Exit criterion asserted in `test/integration/exit-criterion.test.ts`. |
| 1 — The spine | 51 | 0 | 4 | 🔨 **Current.** All three channels live, contact pursues, stances decide the field. Melee's cost is the last of it. |
| 2 — The vertical slice | 14 | 1 | 94 | ☐ **Not started** — except the items, the grid inventory and the condition view, pulled forward. |
| 3+ — Beyond the slice | 0 | 0 | 16 | ☐ Designed, deliberately unbuilt. Prose lives in [docs/23](docs/23-roadmap.md). |
| **Total** | **104** | **1** | **114** | |

Milestones close on their **exit criterion**, never on the checkbox count.

## Do this next

**[Grabs and bite risk](docs/09-combat.md#grabs).** It is the last open box in Milestone 1 and it has
been the honest answer here for three sessions, but it is a different size now than it was: **half of
what it was waiting on exists.**

What arrived with the stance ladder: a survivor has a body with docs/05's **six parts** — head,
torso, arms, hands, legs, feet — and a blow that lands on one rolls against that table rather than a
zombie's three. Something can now be wrong with a specific limb, and the player can see which.
`entity.staggered` already interrupts a wind-up, and a survivor can now be staggered.

What is still missing, and it is the half that matters: **located injuries**. There is no scratch, no
laceration, no fracture, no bleed — a part has an integrity that goes down, and that is all. And
there is no [infection module](docs/06-infection.md), so a bite has nothing to turn into. Both gaps
matter for the same reason: with no wound *types*, a grab could only reduce a number, and
[the parity contract](docs/09-combat.md#the-parity-contract) is not satisfied by making melee cost
hit points. It is satisfied by making melee cost something you cannot heal by waiting.

So the order is: docs/05's injury types on the body that now exists, then the infection module, then
grabs on top of both. The four grab clauses in docs/09 — cannot move, cannot swing, breaking free
costs stamina and time, two at once is terminal — need **no wound at all** and could land first if
you want the crowd to feel categorically dangerous before it can infect you. That is a legitimate
order; it just leaves the parity contract open a little longer, so write down which one you chose.

**Two things left over from the ladder, both small and both named in the code:**

- **Exhausted swings still refuse rather than degrade.** `melee.ts` stops the swing outright when the
  pool cannot pay for it, and docs/09 wants "slow, weak, and miss". The comment there used to say the
  scaling was waiting on the stance ladder, which shares the pool — the ladder has landed, so what is
  left is a `swing_speed` and `swing_recovery` modifier sourced from how empty the pool is, and both
  stats are already registered. It was held back on purpose: it is a balance change to the one loop
  the game has, and it wants its own measurement rather than riding in behind six other things.
- **The condition view has one voice.** docs/05 scales a part's prose by the examiner's Medicine
  skill — untrained gets "there's a lot of blood, he doesn't look good", skilled gets "deep
  laceration, sutured and clean, off work five days". There is no [skill web](docs/08-skill-web.md)
  to scale against, so what ships is the untrained tier and `condition.ts` says so. When the web
  lands, that table gains a column rather than being rewritten.

**Two things the item system left deliberately unfinished**, if you would rather continue that
thread:

- **Nothing wears out.** `Condition` is on every item, `conditionFactor` reads it, and damage and
  swing speed both already scale with it — but no system ever *lowers* it. Wear is driven by use, so
  it wants to be a subscriber to `attack.connected` rather than a system of its own, which is a small
  change in `modules/items.ts` and no change anywhere else. `item.broke` is declared and unpublished.
- **Attachments are content with no reader.** Bases declare their slots (`head`, `haft`, `wrap` and
  so on) and nothing looks at them. The design wants attachments to move freely between compatible
  bases, which is the mechanic that lets a build survive an upgrade; the grid already knows how to
  hold them.

**Not multiplayer.** [Doc 27](docs/27-multiplayer.md) landed as a specification and the cut-list
reversal is written into [the vision](docs/00-vision.md#cut-list), but nothing was built and nothing
should be built yet. PVP is meaningless without the melee loop and the contested recovery run is
meaningless without gear worth recovering, so it sits in Milestone 3 behind both. What did change:
[risk 9](docs/23-roadmap.md#risks) — what a client may know — now has a *buildable* answer rather
than a proposed one. A stance is also the shape docs/27 predicted: an integer decision on the command
queue, ordered by `(tick, playerId, seq)` like every other, which serialises and replays without a
special case. It is still a **design** question to settle before any transport code exists.

**And not a health bar.** The one thing that was asked for and refused is a bar of any kind. The
[condition view](docs/05-health-injury.md#the-condition-view) shipped instead, and it shipped with
the ban made mechanical rather than merely stated: `conditionView` hands the screen a state and a
sentence per part and **no integrity value, no maximum and no fraction**, so a fill is not
discouraged — it is not computable from what the screen has. `paperdoll.test.ts` serialises the
snapshot and asserts the absence. If a future session finds itself adding a percentage, it will have
to widen that boundary first, and that is the moment to re-read
[clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) rather than the
moment to quietly amend it.

Still open and unclaimed, and all three are deliberate rather than forgotten: the two ⏸ **deferred on
measurement** items in the attention field (dirty regions and the propagation budget, each of which
says what would change the answer), sharing the spatial index between emitters and culling, and the
**simulation half of last-known-position memory** — the renderer fades a mark where a body was last
seen, but no observer *remembers* anything, and the prose version belongs with the condition view.


## Quick start

```bash
npm install
npm run dev              # the game at http://127.0.0.1:5174
npm test                 # correctness: 582 tests (~70 s -- the scent ones simulate hours)
npm run typecheck        # two projects -- the second is the sim/ purity gate
npm run lint
npm run format:check
npm run bench            # tick budgets, and they fail the build
npm run bench:frame      # frame budget, drives real Chromium
```

`WASD` move · `Shift` sprint · `F` swing · `Space` **shout** · `E` pick up · `Tab` inventory (drag to
move, right-click or `R` to rotate) · `O` cycles the attention overlay (off → noise → scent → sight) ·
`1`/`2`/`3` speed (1×, 3×, 10×) · `P` pause · `M` raw sprite sheets · `F5` save · `F9` load.

A day is four hours at 1×, so press `3` and wait for dark.

**Editing content while it runs.** Change any file under `content/` and a valid edit reloads the page
on the same seed, so the HUD's fingerprint is directly comparable before and after. An invalid edit
does *not* reload: the run keeps going and the HUD grows a `content:` line naming the file, the entry
and the field. [Why it restarts rather than hot-swaps](docs/30-decisions.md#what-hot-reload-made-structural).

**If `bench:frame` cannot find a browser**, point it at one:
`CHROMIUM_PATH=/opt/pw-browsers/chromium-*/chrome-linux/chrome npm run bench:frame`.

### Five minutes to see whether it works

1. **Press space.** 4,055 of the district's 4,096 field cells go live, 298 of 300 shamblers switch to
   seeking, and the crowd within 50 m goes from ~30 bodies to ~90 over a minute. Then it fades.
2. **Walk up to one and press `F`.** A beat before the blow, a longer one after, and during the second
   you are committed — the wedge on the ground is the swing. Swing at nothing and the recovery is the
   same length, which is the lesson. Break a shambler's legs and it keeps coming at a quarter speed,
   drawn half size.
3. **Then press nothing and wait.** The noise field sits at literally zero live cells and the crowd
   within 50 m still climbs from 30 to 76 over an hour, on scent alone. Being quiet is not *safe*; it
   is *slow*.
4. **Press `O` twice** and watch a horde you disturbed walk off downwind following its own smell. That
   one was not designed.
5. **Press `O` again** for the sight overlay. In a 2,000-body district the HUD reads about **205
   hidden against 11 drawn** — every one of those 205 used to be on screen. The wedge fanning out of a
   doorway and stopping dead at the next building is the primitive working. Note the `shadowcasts`
   counter: it climbs when you cross a tile boundary and sits still when you turn, which is the whole
   cost argument in one number.
6. **Press `3` and wait for dark.** Watch `light` fall from 1.00 and the hidden count climb as your
   view closes from 48 m to 12. A body ten metres away in daylight is one you cannot see at midnight.

## The build

`.github/workflows/ci.yml` runs two jobs: `check` (typecheck, lint, format, 582 tests, build) and
`performance` (tick budgets, then the frame budget in real Chromium). `pages.yml` publishes `dist/`
to GitHub Pages on every green run on `main`.

> ⚠ **One manual step is still outstanding, and only the repo owner can do it:** Settings → Pages →
> Source: **GitHub Actions**. Until then the workflow runs and the deploy step fails on every green
> merge. Nothing in CI depends on it.

## What's in the repo

```
docs/           31 documents: 30 design docs (00-29) plus the decision log (30). The README
                index is the reading-order authority, not the file numbers -- 24-26 belong
                under "The world", 28 sits beside the spine it serves, and 29 beside combat.
src/sim/        The simulation. Pure, headless, deterministic -- kernel, modules, rng.
src/sim/field/  The attention field. Kernel, not a module.
src/sim/vision/ Sightlines: the shadowcast, and every observer's cached view. Also kernel.
src/sim/time/   The clock. Time of day is a pure function of world.tick -- no clock state.
src/sim/locomotion.ts
                How fast things move. One PACE multiplier; every speed is a ratio of it.
src/sim/threat.ts
                "Is anything close?" -- the rule the speed control drops 10x on.
src/render/     Canvas renderer. Reads the sim, never writes to it.
src/render/sprites/
                The character models. Pure pose selection and figure geometry, split from
                the one file that touches a canvas -- Vitest runs in node. `outline.ts` is
                the paperdoll's figure: a diagram, drawn flat, not the body in the street.
src/platform/   The host: input, the tick loop, storage, content loading, schemas.
src/ui/         Screens. The grid inventory is the first one.
content/        JSON content plus its JSON Schemas.
test/           Unit and integration, including determinism and module isolation.
bench/          The performance budgets. They fail the build.
```

The attention spike is **gone**, deleted in the change that ported its findings onto the real kernel.
[docs/23](docs/23-roadmap.md#spike-findings-attention-field) keeps the evidence.

---

# The roadmap

Everything below was `TODO.md` until Milestone 0 closed. It covers Milestones 0 through 2 — everything
needed to reach a playable vertical slice. Milestones 3 and 4 stay as prose in
[docs/23-roadmap.md](docs/23-roadmap.md) on purpose: the slice exists to find out whether the core idea
is fun, and most of what lies beyond it is guesswork the slice will invalidate.

**How to read it.**

- Each section names the design document that specifies it. **If a task and its doc disagree, the doc
  is wrong** — update it in the same commit rather than letting them drift.
- Three states, and the middle one carries weight: `[x]` **done**, `[~]` **in progress** — built far
  enough to read but not finished, and the note says exactly what is missing — and `[ ]` **todo**.
  Within a section they appear in that order, so the shape of what remains is visible without reading
  the history. The notes on done items are kept: they are usually the reason the next task is shaped
  the way it is.
- ⚠ **Risk checkpoints** mark tasks whose *result* decides whether the plan changes. Don't quietly
  pass one — if a checkpoint fails, that is the signal to stop and redesign. See
  [the register](#risk-checkpoints) below.
- Milestones close on their **exit criterion**, not on the checkbox count.

## Risk checkpoints

The ten [roadmap risks](docs/23-roadmap.md#risks), each pinned to the task that answers it. Four are
closed; the closed ones are worth reading because two of them were answered *differently* from how they
were asked.

| # | Risk | Answered by | State |
|---|---|---|---|
| 1 | The micromanagement cliff — *highest design risk* | Focus + auto-allocation, played with 6+ survivors | ☐ Milestone 2 |
| 2 | Unlimited survivors may undercut permadeath | Watching whether players quarantine or just execute | ☐ Milestone 2 |
| 3 | Unscheduled hordes may starve the tower-defense half | Building, played — are sieges frequent enough? | ☐ Milestone 2 |
| 4 | ECS + modifier pipeline may be over-engineering | Kept minimum; the spike ran the thesis before any architecture | ✅ **Closed** |
| 5 | Attention field performance | 500-zombie synthetic load, then the real continuous channel | ✅ **Closed.** Scent costs 0.0075 ms/tick — 0.1% of budget, and the same when saturated. |
| 6 | Melee/ranged parity may not survive contact | Balance harness: melee-only vs ranged-only colonies | ☐ Milestone 2 |
| 7 | Streaming a continuous region at driving speed — *highest engineering risk* | The drive benchmark, against synthetic load **before any vehicle exists** | ☐ Milestone 3, step 2 |
| 8 | Full nomad viability roughly doubles the balance surface | Balance harness on nomad-only, fixed-only, hybrid | ☐ Milestone 3, step 4 |
| 9 | What a multiplayer client may know about the field | Validation of docs/28's proposal, **before any transport code** | ◐ **Narrowed, not closed** — and it surfaced that visibility was a dependency, not a nicety |
| 10 | A host in the loop may not fit the frame budget | Synthetic-client benchmark at the single-player budget | ☐ Milestone 3 |

Two more findings arrived through the spike rather than the risk list, and both are closed: **noise
magnitudes were never uncalibrated** — the unit was simply never defined, and the answer (256 m
district) changed zero magnitudes — and **field memory is not a no-op**, though what it does is not what
was written down. Both are in [the decision log](docs/30-decisions.md#what-the-spike-settled).

---

## Milestone 0: Foundations (complete)

The architecture with no game on top. Deliberately minimal — the goal was the *minimum* ECS, not a
good one ([risk 4](docs/23-roadmap.md#risks)).

> **Exit criterion:** an entity moves around a tile map, deterministically, and the same seed plus
> inputs reproduces it byte-identically.
>
> ✅ **Met, and asserted** in `test/integration/exit-criterion.test.ts` against the shipped boot path
> rather than a fixture — including the negative controls that make it capable of failing: a different
> seed diverges, and so does a different input log on the same seed.

**39 done, 0 open.** What the milestone made structural is
[entry 2 in the decision log](docs/30-decisions.md#what-milestone-0-built-and-the-rules-it-made-structural).

### Project setup — spec: [docs/19](docs/19-architecture.md)

**Done (5):**

- [x] Vite + TypeScript scaffold, `strict` on
- [x] Vitest configured, running headless
- [x] Directory layout per [the repository layout](docs/19-architecture.md#repository-layout):
      `src/sim/{kernel,modules,rng}`, `src/render`, `src/platform`, `src/ui`, `content/`, `test/`
      *(`src/ui` was the exception until the grid inventory arrived early — `src/ui/inventory.ts`
      is the first screen in the game. See the Milestone 2 entry below.)*
- [x] ESLint rules enforcing **`sim/` purity** — ban DOM globals, `Math.random`, `Date.now`, and
      imports from `render/`, `platform/`, and `ui/`
      *(plus `tsconfig.sim.json`, which compiles `sim/` with no DOM lib so DOM access is a type error
      rather than only a lint error)*
- [x] Prettier / formatting config

### Kernel — spec: [docs/19](docs/19-architecture.md), [docs/20](docs/20-ecs-and-content.md)

**Done (8):**

- [x] Seeded RNG with independent named streams per subsystem
      *(stream seeds hash `(masterSeed, name)`, so adding a stream never shifts an existing one)*
- [x] Fixed-timestep tick loop with an accumulator, decoupled from render
      *(in `platform/`, the only code that reads a clock — `step(world)` takes no time argument)*
- [x] Entity store: integer IDs, allocation, recycling
      *(ids pack a generation, so a recycled slot can't resurrect a stale reference)*
- [x] Component storage and queries
      *(queries iterate in ascending entity order — insertion order doesn't survive a save/load)*
- [x] System registry with **declared insertion order** (ordering is data, not a hardcoded list)
- [x] World state container for singletons — clock, RNG streams, field, weather, director
      *(the container and the clock; field, weather and director land with their modules)*
- [x] Event bus: publish, per-tick drain in deterministic order
- [x] Core event vocabulary stubbed out ([the event table](docs/21-extensibility.md#core-events))

### Modifier pipeline — spec: [docs/21](docs/21-extensibility.md#mechanism-2-the-modifier-pipeline)

**Done (6):**

- [x] Stat registry
- [x] Modifier struct with a **mandatory `source`** field
- [x] Resolution order: `add` → `mul` → clamps
      *(`set` precedes them, or it would erase everything applied before it; `min` is a floor and
      `max` a ceiling. Modifiers fold in `(source, seq)` order — float addition isn't associative, so
      an unsorted fold makes a resolved stat depend on module import order.)*
- [x] Remove-by-source (drop every modifier from `weather.rain` when rain stops)
- [x] Resolved-stat caching with invalidation by source
      *(scoped global vs per-entity; a global change invalidates every entity's cache for that stat)*
- [x] "Why is this stat this number?" introspection returning the full contribution list

### Content pipeline — spec: [docs/20](docs/20-ecs-and-content.md#part-2-content)

**Done (6):**

- [x] JSON Schema definitions per content type
      *(`zombie` and `affix` to begin with — the two docs/20 writes out — then `calibration` and
      `item` as those systems landed, which is the rule working: a type gets a schema the day its
      system exists, because a guessed schema is worse than none for looking authoritative.)*
- [x] Registry that walks content **directories** (not a fixed file list — this is what makes it
      mod-ready later)
      *(walking is in `platform/`, since `sim/` has no file system; the registry itself stays pure)*
- [x] `extends` resolution
- [x] Load-time validation: every ID unique, every reference resolves, every modifier `stat` exists,
      every behavior tag implemented, no circular `extends`
- [x] Errors name the file, the entry, and the field — **fail loudly at load, never silently at hour
      thirty**
      *(every problem reported in one pass, and nothing is published unless all of it validated)*
- [x] Hot reload in dev
      *(and the note that used to sit here had the shape of the job wrong. It assumed republishing
      **without restarting the world**; docs/20's loop is "tweak a JSON value, **reload**, re-run the
      seed, compare outcomes", and restarting is the correct answer rather than the cheap one —
      four things capture content at spawn time (affix modifiers, the `MeleeWeapon` snapshot,
      container grids) or at construction (the field's calibration, which cannot be swapped at all),
      so a live swap would refresh some and not others. An edit is validated into a throwaway
      registry first: valid, and the page reloads on the same seed; invalid, and the run keeps going
      with the error on screen naming file, entry and field.)*

### Platform & render — spec: [docs/19](docs/19-architecture.md#layers)

**Done (7):**

- [x] Canvas renderer skeleton with a camera
      *(interpolates between the last two tick states, so a 20 Hz sim reads smoothly at 60 fps)*
- [x] Tile layer with dirty-region redraw
      *(the map is static in Milestone 0, so the dirty region is "all of it, once": rasterised to an
      offscreen canvas and blitted. The per-rect list arrives when structures make tiles mutable.)*
- [x] Input → **command queue** consumed by the sim on its own tick (so input is part of the
      deterministic record)
- [x] Save/load: serialize world state, version stamp, **clean rejection of stale saves**
- [x] Atomic save writes (temp file + rename) — a crash mid-write must not corrupt a long run
      *(and a browser equivalent: two slots with a pointer flip, since localStorage has no rename)*
- [x] **Character models** — bodies that stand up, face one of eight directions, and walk
      *(procedural, rasterised into one sheet per archetype at boot the way the occluder sprites
      are, so there is still no asset pipeline and still no image file in the repository. Three
      archetypes — you, somebody else's survivor, a shambler — differing by posture before colour,
      because at 31 px posture is what survives the night wash. Poses for the states the
      simulation can already express: idle, walk, sprint, wind-up, recovery, staggered, crawling.
      The walk cycle advances by **distance travelled**, never by a clock, so it cannot desync
      from speed and freezes correctly when the game is paused. `M` shows the raw sheets.)*
- [x] **Bodies that read as bodies is a prerequisite, not polish.**
      [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) says condition
      is read "from descriptive text and animation" and forbids the health bars that would replace
      it — a square cannot favour a leg. The diegetic readouts below now have something to happen
      to; a limp is a walk cycle, and the crawler is the first of them already on screen.

### Tests & CI

**Done (7):**

- [x] Unit tests: RNG streams, modifier resolution, event ordering
- [x] **Determinism test** — same seed + same input log twice → byte-identical state
      *(with a different-seed negative control, so the test can actually fail)*
- [x] **Module-isolation boot test** — boot with each non-kernel module disabled, assert no crash
      *(each one individually, all of them at once, and a check that entity ids don't shift when a
      module is switched off — otherwise configuration would become a determinism bug)*
- [x] CI workflow: typecheck, lint, unit, determinism, module isolation
- [x] **Performance budget harness** wired into CI — per-system tick timings against asserted budgets,
      **failing the build on regression** ([pillar 6](docs/00-vision.md#the-six-pillars))
- [x] Harness asserts **frame time as well as tick time**. The spike measured draw at ~30× sim, so a
      tick-only budget would have caught nothing —
      see [aim the budgets at the renderer](docs/22-performance.md#aim-the-budgets-at-the-renderer)
      *(frame time needs a real compositor, so it runs Chromium via Playwright. The gate is on
      sim+draw, not observed fps: a headless container's rAF pacing measures the host, not us.)*
- [x] Baseline benchmark scenario ("quiet night") as the first entry in
      [the suite](docs/22-performance.md#the-ci-benchmark-suite), at ≤0.5 ms tick and ≤4 ms frame
      *(plus a "crowded" 2,000-entity scenario, since at the 300-entity baseline only ~20 survive
      culling and the frame budget could never fail)*

## Milestone 1: The spine (in progress)

The [attention field](docs/03-attention.md) and something that reacts to it. This is the first point at
which the project is legible as a game, and it is.

> **Exit criterion:** make a noise and the horde comes; go quiet and it doesn't.
>
> ✅ **Met for noise** and asserted in CI (`test/integration/attention.test.ts`), and now guarded from a
> second direction: contact pursuit is the first stimulus allowed to persist, so
> `test/integration/pursue.test.ts` asserts that a quiet district with nobody near the survivor has
> nobody pursuing. Contact cannot make silence meaningless, because it needs the zombie to already be
> next to you.
>
> Guarded from a third direction now that stances exist: `test/integration/stances.test.ts` asserts the
> criterion one rung at a time — the district hears more at every step up the ladder, and crawling past
> a shambler is not the same event as sprinting past it. "Go quiet" is a thing you can now *do*
> gradually rather than a thing you either are or are not.
>
> The milestone is **not closed**: melee still does not cost bite risk.

**51 done, 4 open.** **All three channels are in**: the **noise spine** (field, gradient ascent, a
shout), **scent** (continuous diffusion, wind, field memory), and **light** (a shadowcast from every
emitter, zombies with eyes, and a night dark enough that a found candle matters). Both ⚠ checkpoints
riding on scent are closed, and light turned out not to belong in the field at all —
[entry 15 in the decision log](docs/30-decisions.md#what-light-made-structural).

**And the field now has a fourth thing writing to it that is not a channel: you.** The
[stance ladder](docs/29-movement-and-stances.md) is what turns docs/03's emitter table into a decision
made continuously rather than a property of being alive — five rungs, each with its own speed, its own
noise and its own price, and the largest gap deliberately left between jog and sprint because that gap
is where the decision lives.

**Six items moved out**, because Milestone 1 could not finish them: wet ground, surfaces-in-content,
vehicles-read-the-layer and longer-nights went to [beyond the
slice](#beyond-the-slice-designed-deliberately-unbuilt); nights-vary and last-known-position memory went
to [Milestone 2](#milestone-2-the-vertical-slice-not-started). Each kept its note and gained a line
saying what unblocks it. An open count is only worth reading if the things in it can be acted on, and
six of them could not.

**Three more are marked ⏸ deferred on measurement** — dirty regions, the propagation budget, and sharing
the spatial index. Each says what would change the answer, because "nobody got to it" and "this was
measured and refused" should not look the same in a backlog.

**So the honest remainder is one job**: [grabs and bite risk](docs/09-combat.md#grabs), the parity
contract. That checkbox still bundles two very different sizes — docs/09's four grab clauses need no
wound at all, while bite risk needs docs/05's injury types and the infection module — and it is now
half unblocked, because the survivor has a six-part body that can be hurt. See
[Do this next](#do-this-next) for the order.

What this milestone found — including two things that contradicted the design docs and got them
corrected — is in [the decision log](docs/30-decisions.md#what-milestone-1-has-found-so-far).

### The attention field — spec: [docs/03](docs/03-attention.md)

**Done (10):**

- [x] Noise layer on a **coarse grid** — 4 m cells, per
      [scale and calibration](docs/03-attention.md#scale-and-calibration)
      *(the field is kernel, not a module: a world with nothing emitting is coherent, a world with
      no field is not. 256 m district ÷ 4 m = exactly 64 × 64 cells, asserted.)*
- [x] Calibration constants as content, not magic numbers: 1 tile = 1 m, 0.7 attenuation per metre,
      18 m-equivalent wall penalty, ~3 s noise half-life
      *(`content/calibration/attention.json`. `DEFAULT_CALIBRATION` shadows it because content loads
      after the world is built and the cell geometry has to exist first — a test asserts the two
      agree, so drift fails the build.)*
- [x] `AttentionEmitter` component + emission system
- [x] **Noise** — event-driven only; attenuated flood-fill with material-based falloff, radius bounded
      by magnitude
      *(everything reaches the field through `noise.emitted`, so a trap or a generator needs no
      knowledge that the field exists)*
- [x] **Scent** — diffusion at a few Hz with a global wind vector
      *(4 Hz, gather-not-scatter so determinism falls out of the loop shape, wind as four
      normalised outflow weights derived once. Needed a **scent floor of its own**: sharing noise's
      made dilution rather than the half-life govern a smell's lifetime — a 90 minute half-life
      behaving like two minutes. Walls do not block it, and it sums where noise takes a maximum.)*
- [x] **Field memory** — milling bodies emit scent residue (**never noise**), at a magnitude that
      propagates past its own cell
      *(its own `field-memory` module, so the acceptance check below toggles a shipped
      configuration rather than a test-only edit)*
- [x] ⚠ **Acceptance check:** toggle residue off and confirm something observably changes. The
      [spike failed exactly this check](docs/23-roadmap.md#problem-3--field-memory-is-currently-a-no-op)
      because it emitted onto the wrong channel.
      **Passed, and the mechanic is kept — but it does not do what the doc said.** The horde
      *migrates*: it lays residue, the plume drifts downwind, it climbs into its own plume and
      repeats, crossing most of a district in an hour. With residue off it stays within 7 m of where
      it gathered. The mill site therefore empties *faster*, not slower. Self-limiting — the crowd
      spreads at the district edge, the residue burns out, they disperse.
      [docs/03 is corrected](docs/03-attention.md#what-field-memory-turned-out-to-actually-do).
- [x] Field is part of the save state
      *(sparse — live cells only, so a quiet save costs nothing and a loud one is bounded. Note
      `canonicalize` rejects negative zero, which a decaying float reaches: values under the floor
      snap to a hard 0.)*
- [x] Debug overlay visualizing the noise channel *(developer-only, `O` to toggle, off by default —
      see the [information rule](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable).
      Grows the other two channels when they exist.)*
- [x] **Light** — shadowcasting from emitters, recomputed only on emitter or occluder change
      *(built, and **not in the field** — `src/sim/vision/light.ts`, beside the primitive it casts.
      The field refused it twice: `liveCells()` is read as "the district is silent" by three
      exit-criterion assertions, and 4 m cells would round away the wall-absolute precision that
      makes shutters work. Magnitude is range, and it aggregates by **max**, never sum.)*

**Open (2):**

- [ ] Dirty-region tracking
      ⏸ **deferred on measurement.** *Scent made the field continuous, which was the condition this was
      waiting on, and the continuous step costs 0.0075 ms amortised per tick — the same whether the
      district is saturated or fresh. This note used to say "revisit if a third channel changes the
      arithmetic", and **a third channel has since arrived and changed nothing**: light is a shadowcast,
      not a field layer, so it never touches this grid. The trigger is now a **larger grid**, or a fourth
      channel that genuinely lives in the field.*
- [ ] Per-tick propagation budget with a deterministic overflow queue (degrade the field's update rate,
      never the frame)
      ⏸ **deferred on measurement, and the most speculative item in this file.** *Nothing in the design
      documents asks for it — "overflow queue" appears only here — and the cost it would manage has been
      measured not to exist: `after-a-shout` runs at 0.19 ms against `quiet-night`'s 0.15 at the same
      budget, and [risk 5](#risk-checkpoints) is closed. Propagation is already bounded per emission,
      because the flood stops when the arriving magnitude falls below the floor.*
      *It would not be free either: a deferred emission is **new save state**, arriving against a field
      that has decayed further than it would have — so "degrade the update rate, never the determinism"
      needs the deferral count itself to be deterministic. The trigger is a **magnitude-180 emitter**,
      the gunshot docs/22 budgets for, which does not exist because there is no ranged weapon yet.*

### Visibility & sightlines — spec: [docs/28](docs/28-visibility-and-sightlines.md)

**Done (9):**

- [x] **Facing** on observers — a heading, in save state, read by both sight and
      [aiming](docs/09-combat.md#aiming)
      *(one component, specified once in docs/28 and consumed by combat, rather than combat growing
      its own. Kernel, beside `Position` and `Velocity`, because neither future reader owns the
      other. Updated at the top of `movement.integrate`, **before** collision resolution, so a body
      walking diagonally into a wall keeps looking where it was going rather than snapping to run
      along it — mutation-tested by moving the update below the collision and watching the assertion
      fail. It rides that loop rather than taking a system of its own because a second system means
      a second `query`, and `query` sorts: measured at **+0.70 ms/tick** on the 2,000-entity crowded
      scenario against **+0.16 ms** folded in. Kept when the body stops, since a survivor standing
      still is still looking somewhere, and `headingOf` collapses the negative zero that
      `Math.atan2` reaches due east and `canonicalize` rejects outright. `SAVE_VERSION` 5.)*
- [x] Recursive shadowcasting over the tile grid, **symmetric** (if A sees B, B sees A) and integer-only
      so determinism falls out
      *(Albert Ford's symmetric variant: a floor tile is revealed only when its **centre** is inside
      the wedge, which is the condition that makes the relation symmetric — the permissive variants
      are cheaper and are not. Slopes are rational `{n, d}` pairs compared by cross-multiplication,
      so no float ever decides which side of a wedge boundary a tile fell on. Mutation-tested: make
      the reveal permissive and the symmetry guard finds asymmetric pairs at every corner.)*
- [x] Occluder classes on tiles — **solid / transparent / screening / low**, with opacity and solidity
      as *two* properties
      *(a window stops a body and not a sightline; a curtain stops a sightline and not a body. One
      enum cannot express that, and the day it has to is the day this gets rebuilt.
      `Tile.Floor` and `Tile.Wall` kept their values and the generator's layout pass was left
      untouched — the three new classes are dressed on afterwards from **their own RNG stream**, so
      the district a seed produces is byte-identical to the one every existing calibration was
      measured against. Windows replace wall tiles and the other two only land on open ground, so
      solidity never moved. Mutation-tested: define `blocksSight` as `isSolid` and three guards go
      red at once.)*
- [x] Focal and peripheral arcs — detail ahead, movement to the sides, nothing behind
      *(a dot product against the heading rather than an angle difference: no `atan2`, no wrap-around
      case to get wrong. Per observer rather than as constants, because a survivor and a screamer
      will not share them. A body standing still in the peripheral arc is **not drawn at all** —
      movement is what is noticed out there, which is the mechanic and not an omission.)*
- [x] **Recompute on change, not on tick** — an observer that hasn't moved a tile, turned, or had its
      surroundings change sees what it saw
      *(cached per **tile**, not per view, so turning on the spot is free: the arcs are evaluated
      against cached geometry at query time. 690 shadowcasts across 600 ticks with 51 observers.
      Mutation-tested both ways — recompute unconditionally and the "standing still is free" guard
      goes red; fold facing into the cache key and the "turning is free" one does.)*
- [x] **Renderer occlusion** — entities are drawn only where the survivor could see them
      *(11 bodies drawn where 216 were in the viewport, at 2,000 entities. The renderer asks
      `world.vision` rather than computing a cheaper check of its own — docs/28's design rule, and
      the reason it gives is that the place two line-of-sight checks disagree is where the exploit
      lives.)*
- [x] Benchmark scenario held at **the same budget as its sightless twin**
      *(⚠ this is the first cost in the project that does not amortise across the horde — one
      shadowcast per changed observer, and per client on top of that in multiplayer. See
      [the cost shape](docs/22-performance.md#visibility-is-a-different-cost-shape). Tiering is the
      mitigation: a distant zombie needs the gradient it is climbing, not a sightline.
      **`crowded-and-watched` measured 1.34 ms against `crowded`'s 1.32 at the same 4 ms budget** —
      which is a measurement of how rarely a shadowcast runs, not of one being cheap. A single 12 m
      cast is 0.07 ms and a 48 m one 0.18 ms. Still unmeasured, and the thing to measure next:
      observers that **sprint**, which pay every three ticks rather than every forty.)*
- [x] **Light channel on top of the primitive** — shadowcast from emitters at
      [the magnitudes already tabled](docs/03-attention.md#light), range in the same metres
      *(`Observer.rangeMetres` is no longer a daylight constant: `sightMetres` takes the max of
      ambient and emitted and the **min** with the observer's own eyes, so light removes a penalty
      rather than granting an ability. A floodlight is not better than daylight and a shambler's
      twelve metres stay twelve.)*
- [x] Zombies read light as a line-of-sight pull; the
      [sensory profile's](docs/14-zombies.md#sensory-profiles) Light column goes live for the first time
      *(the game hands eyes to 15% of the horde. Light is the **third** stimulus shape — noise is an
      impulse that commits, scent is a bias on a gradient, and light is a gated lean with no
      gradient at all, because docs/28 asks whether a zombie can *see* the lit cell. Four negative
      controls hold docs/14's first rule: it never reaches Seek, keeps its heading the tick the lamp
      dies, ignores a floodlight through a wall, and ignores one entirely with no eyes.)*

### The ground — spec: [docs/24](docs/24-world-and-scale.md#the-ground)

**Done (5):**

- [x] **A surface layer**, separate from the tiles — paved / dirt / grass / undergrowth / rubble
      *(two arrays, never one enum. A tree stands on grass and rubble lies on tarmac, so a single
      enum would be a product of two sets rather than a list — the same lesson doc 28 learned about
      opacity and solidity, one layer down. `Paved` is 0, so a zeroed array is a paved district and
      a map built without a surface layer behaves exactly as maps did before it existed.)*
- [x] **Surface multiplies movement speed**, applied in `movement.integrate`
      *(the one place every mover passes through, so the player module, three shambler states and
      whatever sets a velocity next all pay it without knowing the layer exists. Velocity keeps
      meaning **intent**, which is what keeps the sprint threshold reading intent rather than
      terrain: a survivor wading through brambles is still sprinting and still loud for it.)*
- [x] **Surface multiplies footstep noise** — and never replaces the emitter's magnitude
      *(a walk carries 1.4 m on tarmac, 0.9 m on grass and 2.4 m across rubble; a sprint across
      rubble carries 14.6 m, most of a street. Sprinting stays exactly six times a walk on every
      surface, because the [emitter table](docs/03-attention.md#noise) is calibrated and terrain
      modulates it. There is a guard on that ratio specifically. A shout is a shout wherever you
      stand, and a generator's hum is a property of the generator.)*
- [x] **Trees** — solid and opaque, standing on grass
      *(its own tile value even though the primitive cannot tell it from a wall, because everything
      else will: it is drawn differently, it is wood later, and a district whose only solid thing is
      masonry cannot have a park in it. A stand of them breaks a sightline down a street, which is
      what gives a district somewhere to be that is neither indoors nor exposed.)*
- [x] Undergrowth under every piece of screening foliage, rubble under every piece of low cover
      *(the two halves of a bush have to agree. Screening that blocked a sightline while leaving you
      fast and silent would be strictly better than every other tile on the map, and
      [docs/29's rule](docs/29-movement-and-stances.md#the-rule) is that nothing may be strictly
      better than anything else. You can be unseen or unheard; the ground makes you pick.)*

### Spatial partitioning — spec: [docs/22](docs/22-performance.md#spatial-partitioning)

**Done (2):**

- [x] **Uniform spatial index over entity positions** — a dense grid with a counting sort, not a
      map of buckets
      *(the literal reading of "hash" was built first and measured 344 ns per body per tick,
      nearly doubling a tick for an index nothing queried yet. 2,000 bodies in a 256 m district
      land in ~1,900 distinct cells, so a map of per-cell arrays is one tiny array per body. Flat
      typed arrays plus a prefix-sum table cost 66 ns and allocate nothing. The fixed cost is the
      prefix sum, proportional to the **grid** rather than the crowd — which is the right trade at
      district scale and becomes per-chunk when the world streams.)*
- [x] Neighbor queries **for combat**
      *(the swing's arc query is the first and so far only consumer, which is exactly why it was
      deferred to here. Guarded by `crowded-and-swinging`, held at the same budget as `crowded`:
      1.63 ms against 1.75, i.e. asking "what is within reach" is not a function of how many
      bodies are in the district.)*

**Open (1):**

- [ ] Emitters and render culling read the same index
      ⏸ **deferred, and the shape is wrong rather than the timing.** *Neither consumer's question is
      "what is within R metres of this point", which is the only question `SpatialHash` answers. The
      emitter walk is per-entity over every emitter with no radius in it at all, and culling is a
      viewport **rectangle** — a circumscribing circle over an isometric viewport would drag in bodies
      the rectangle rejects for free. Sharing the index means adding a rect query, which `hash.ts`'s own
      `CELL_METRES` note warns against: "a grid tuned per caller is a grid with two answers."*
      *The measurements argue against it too: culling is what keeps the frame budget passing at all, and
      `crowded-and-swinging` shows the index holding at its sightless twin's budget. The trigger is one
      of the two actually hurting.*

### Zombies — spec: [docs/14](docs/14-zombies.md)

**Done (6):**

- [x] Shambler entity with a sensory profile weighting the three channels
      *(all three weights are read; only noise is live, so scent slots in behind it)*
- [x] Gradient ascent on noise, and **scent as a bias** — it bends a wandering shambler's heading a
      third of the way toward what it can smell, but never seizes it, never commits it, and never
      changes its state. Noise stays the only *impulse*. That asymmetry is what keeps the noise exit
      criterion intact now that the player emits scent permanently and cannot stop.
      Light-as-line-of-sight arrives with its channel
- [x] **Persistent per-individual angular bias (±0.62 rad)** on the gradient direction — assigned once
      at spawn from the seeded RNG stream, never re-rolled, **included in save state**. Without it
      they form [conga lines, not a horde](docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own).
      *(mutation-tested: delete the bias and twenty shamblers in one cell collapse to a single heading)*
- [x] Investigate on arrival → mill → disperse, **raising local scent** while they mill
- [x] **Damage model: head and locomotion are what matter; a crawler is still lethal**
      *(three pools rather than one, from `content/zombies/base.json`'s `body` block, which had
      been sitting there read by nothing. A head is instant, a torso never kills however much of
      it is destroyed, and legs at zero leave a quarter of a shamble — slow enough to walk away
      from, far too fast to ignore at arm's length. It draws at half size, because docs/14 says a
      crawler "is easy to miss in a dark breach" and that has to mean less visible rather than
      merely slower. **Damage never interrupts the state machine**; only stagger does, per
      docs/14's "stagger from mass, never flinch from injury".)*
- [x] Pursue on direct contact
      *(a fifth state, and the only stimulus that **persists** — noise commits for twenty seconds and
      fades, scent and light end the tick they stop being sensed, and contact holds until the survivor
      gets clear. **Contact is distance**, for `threat.ts`'s reason: distance is the one measure that
      does not vary with the light, so shutters and darkness cannot switch pursuit off. Two radii,
      because one flickers. It grinds at a wall rather than pathing round it, which is docs/14's
      sentence and falls out for free from a heading that never stops pointing. A stagger still drops
      it, which is what docs/09 says a stagger buys.)*

### The player survivor — spec: [docs/09](docs/09-combat.md)

**Done (12):**

- [x] Direct movement control of one entity
      *(landed in Milestone 0; it now emits into the field — walking 1, sprinting 6, shouting 120)*
- [x] **A single pace multiplier** — `PACE` in `src/sim/locomotion.ts`, currently 1.5
      *(the repo owner's call, on game feel: at the real-world 1.4 m/s a 256 m district is a
      three-and-a-half minute crossing. Everything that moves is scaled by the same factor, so every
      ratio survives — sprint is still three times walk, a shambler still eight tenths of it, and the
      sprint threshold is **derived** rather than the hardcoded 2.8 it used to be, which was the
      midpoint of the old pair and would silently have stopped being the midpoint of anything. The
      emitter magnitudes did not move and must not. Worth knowing when tuning it: noise is emitted
      per tick, not per metre, so a large increase quietly makes stealth easier by shortening every
      exposure.)*
- [x] **Melee loop: wind-up → connect/miss → recovery, all interruptible**
      *(a swing is state that persists across ticks, not a function call, and the blow reads
      position, facing and neighbours **at the moment it lands** — turning away mid-wind-up
      misses, and there is a test that does exactly that. A sprint abandons a wind-up and does not
      refund the stamina; nothing escapes a recovery, which is the window docs/09 says kills you.
      No input buffer: a second press inside a window does nothing, because buffering lets a
      player pre-pay for a window they have not survived yet.)*
- [x] Stamina cost per swing, scaled by weapon weight
      *(the recovery **delay** matters as much as the rate: without one a survivor swinging at
      exactly the regeneration rate never tires, and melee's only cost quietly becomes zero.
      docs/09 wants exhausted swings "slow, weak, and miss" rather than absent — that needs the
      modifier pipeline scaling the windows, and arrives with the stance ladder that shares this
      pool.)*
- [x] Stagger on solid connect
      *(and it is the **only** thing that interrupts a shambler. Coming out of it they go back to
      drifting rather than back to what they were doing — nothing is remembered across a stagger,
      which keeps this from being the first version of a zombie that holds a grudge. They pick the
      fight back up through the ordinary noise response, because a connect is 8 magnitude at arm's
      length. Two staggers take the longer, not the latest, or a knife tap shortens what a bat
      just bought.)*
- [x] Reach as a distinct property from damage
      *(pinned by a test rather than asserted in prose: the spear out-reaches the bat while doing
      **less** damage, so reach cannot collapse into a damage stat, and the bat staggers four times
      as long as the spear, which is the survival property rather than the killing one. Reach is
      centre-to-centre plus the target's half-width, or a weapon quietly loses 0.35 m of what its
      profile claims.)*
- [x] **Movement stances** — crawl / crouch / walk / jog / sprint, spec:
      [docs/29](docs/29-movement-and-stances.md)
      *(the ladder is `src/sim/stances.ts`, arithmetic and importing no module, so
      `stances.test.ts` asserts docs/29's two design rules directly: faster is louder at every
      rung, and **no rung is strictly better than another** — checked over every pair, not just
      neighbours. Walk and sprint still emit 1 and 6, and the ladder now owns the only copy of
      those two numbers; the three new registers are picked to sit against them, the way whisper
      and talk were picked against shout.)*
- [x] Each stance carries its own speed, noise magnitude, and stamina behaviour — **faster is louder**,
      which is the whole reason this is a system and not two constants
      *(speed as a factor of a walk so `PACE` keeps owning the clock, and stamina written as
      seconds-to-empty and divided down — the unit the decision is actually made in. Noise comes
      from the **rung** rather than the speed, because rough ground slows a jogging body below a
      walking pace and getting quieter by wading into a bush would be reading the wrong number.)*
- [x] Stance changes are [timed and interruptible](docs/01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die);
      no aiming from a sprint, no swinging from a crawl
      *(one rung at a time, so crawl→sprint costs four transitions and an interrupted body is left
      somewhere real. `entity.staggered` cancels the pending change — the same seam that already
      cancels a wind-up. The swing is abandoned on the **decision** to sprint rather than on its
      arrival: a bat's wind-up is shorter than the transition, so reading the current rung alone
      would have let the blow land every time and docs/09's rule would never have fired once.)*
- [x] Speed modifiers go through the
      [modifier pipeline](docs/21-extensibility.md#mechanism-2-the-modifier-pipeline) with named
      sources — legs, feet, pain, exhaustion, encumbrance, limp
      *(so "why am I this slow?" is answerable from the introspection that already exists, which is
      what [every death is explicable](docs/01-hardcore-contract.md#fairness-rules) obliges. **This
      found a live bug**: nothing read `move_speed`, so `inventory.encumbrance`'s penalty had been
      resolving correctly and changing nothing since the grid landed. The test that "covered" it
      asserted `resolve()` rather than the ground covered. See
      [the decision log](docs/30-decisions.md#what-the-stance-ladder-and-the-condition-view-made-structural).)*
- [x] Crouch and crawl interact with the **low** occluder class, in both directions — cover that hides
      you also blinds you
      *(one assignment, and no cache invalidation at all — `VisibilityIndex.refresh` already keys on
      `observer.eye`, so writing the field *is* the invalidation. Both directions come free from
      `shadowcast` being symmetric; the test asserts both halves in one place, because a test
      checking one is how the two come to drift apart.)*
- [x] Fold the shambler's three hardcoded speeds (seek, wander ×0.35, mill ×0.25) into the same model
      *(so a [zombie type's](docs/14-zombies.md#content-shape) speeds are fields in its JSON entry
      rather than constants in a module. Read at spawn onto the individual, with a per-field
      fallback so a type using `extends` to override `speed` keeps its inherited drift fractions.
      `CRAWL_SPEED_FACTOR` became an `injury.crippled` modifier, which is what its own comment said
      it wanted to be and could not.)*

**Open (1):**

- [ ] **Grabs, and breaking free** — and with them, bite risk
      *(the one part of docs/09's melee model still missing, and the reason **the parity contract
      is not yet satisfied**: with no bite risk, melee's only cost is stamina. **Half of what it was
      waiting on now exists** — a survivor has a body with docs/05's six parts and a blow that lands
      on one rolls against that table. What does not exist is located *injuries*: no scratch, no
      laceration, no fracture, and no infection module for a bite to turn into. A grab that could
      only reduce a number would be the health bar this design refuses. The `entity.staggered`
      subscription that interrupts a wind-up is the seam this plugs into, and it is already there
      because the rule is symmetrical.)*

### Time — spec: [docs/02](docs/02-core-loop.md)

**Done (5):**

- [x] Day/night cycle with the four phases
      *(**time of day is a pure function of `world.tick`** — no clock state, nothing new in the
      save, and nothing that can disagree with the world it was saved from. Starting a run at
      dusk is not a field, it is starting at a different tick. The cost of that trick is that
      `world.tick` stops meaning "ticks since the run began", and two tests were quietly
      measuring the wrong interval within minutes of it landing; both now subtract a start
      tick. A run opens at 09:00 rather than at tick 0, because tick 0 is the start of dawn —
      the darkest moment of the cycle — and a fresh world opening half-blind is not a default.)*
- [x] Phase transitions publish `phase.changed`, `night.fell`, `day.started`
      *(the vocabulary declared all three in Milestone 0 with no publisher. The publisher is
      **stateless** — it compares the phase at this tick with the phase at the previous one
      rather than remembering what it announced, which is what makes it survive a load: a
      remembered phase is either save state that can disagree with the tick, or a
      re-announcement of something that already happened. Day 1 is published explicitly on the
      first tick, since a listener should not miss the day it booted into.)*
- [x] **Ambient light, and the dark is mechanical** — a survivor sees 48 m at noon and 12 m at
      midnight
      *(range is a property of light, which is what
      [docs/28 said](docs/28-visibility-and-sightlines.md#what-an-observer-is) when the field
      was a daylight constant with a note on it. Night is **not a tint over the same view**;
      the view is smaller. Affordable because the tile radius is an integer: ambient light
      changes every tick through dusk, the integer radius about thirty-six times across the
      half hour, and the cache key is built from the integer — mutation-tested by removing the
      rounding and watching it become a shadowcast a tick.)*
- [x] Speed controls: pause, 1×, 3×, 10×, with 10× auto-dropping on threat contact
      *(a day is four hours at 1×, so these are a prerequisite for the cycle rather than a
      convenience — nobody in a dev session would otherwise see nightfall. Implemented by
      scaling the real interval fed to the accumulator, never the timestep, so the fixed
      timestep and the replay record are untouched. Contact is a **distance**, not a sightline:
      a sightline-based rule would fire constantly in daylight and stop firing at night, which
      is exactly when a fast-forward is most dangerous.)*
- [x] **Night is darker.** `NIGHT_AMBIENT` is 0.04, derived rather than picked
      *(and derived in **tiles**, which is the part that matters. The metres version admitted 0.05,
      where bare eyes are 2.4 m and a candle is 3 m and both round to the same three-tile window —
      an upgrade on paper, invisible in play. In tiles the ladder is 2 bare-eyed, 3 by candle, 20 by
      campfire, 35 by lamp, 48 by daylight. The counterplay is **findable, not given**: the default
      loadout is empty and candles sit at loot weight 40.)*

### Performance

**Done (2):**

- [x] Budget scenarios for the loud district: *after-a-shout* and *crowded-and-loud*, each held at the
      **same budget as its quiet twin** — the claim being guarded is that converging is not in a
      different cost class from drifting. Measured 0.19 ms against 0.15 at 300 bodies, 1.38 against
      1.04 at 2,000. The frame benchmark now samples mid-convergence rather than at rest.
- [x] ⚠ **Risk checkpoint (roadmap risk 5):** synthetic 500-zombie load test. Continuous scent
      diffusion is [the most likely thing to need rework](docs/22-performance.md#known-risks) — find
      out now, not in Milestone 2.
      *(**Closed.** `five-hundred-milling` holds 0.42 ms against a 1 ms budget with residue laid
      continuously. Diffusion itself is 0.0377 ms per step, 0.0075 ms amortised per tick, and costs
      the same saturated as fresh because it scans the grid rather than the live cells. The
      continuous channel is not the expensive one; per-entity AI is, and noise already paid for it.)*

## Milestone 2: The vertical slice (not started)

One district, a handful of survivors, and enough of every system to find out whether the loop is fun.

> **Exit criterion:** a full run — arrive, recruit, fortify, survive nights, lose someone, continue —
> playable end to end without a developer explaining it.

**13 done, 93 open.** Nothing here has been started deliberately, with one exception: **items and the
grid inventory** were pulled forward at the owner's request and are largely done. They neither blocked
nor were blocked by Milestone 1 — two new modules plus content, and the one place they touch combat
goes through the event bus.

### World & map — spec: [docs/12](docs/12-resources.md)

**Open (5):**

- [ ] One hand-authored map: a small district with a defensible building
- [ ] ~15 resource types
- [ ] 3 location loot tables (residential, commercial, medical)
- [ ] Site depletion — cleared is cleared
- [ ] Food spoilage *(the only [decay track](docs/13-world-decay.md) in the slice)*

### Survivors — spec: [docs/07](docs/07-survivors.md)

**Open (10):**

- [ ] Generator: name, appearance, age, backstory, traits, skill bias, starting kit
- [ ] Small content pools — enough that generated people feel distinct
- [ ] Trait system with conflict rules
- [ ] Work priority grid with 4 jobs: **Haul, Construct, Cook, Doctor**
- [ ] NPC work AI: choose by priority, proximity, and capability
- [ ] Needs interrupt work, moderated by traits
- [ ] Injuries disable jobs the body can't do
- [ ] ~3 recruitable survivors via director events
- [ ] **Focus + auto-allocation** — auto-spend web points and auto-maintain loadouts
- [ ] ⚠ **Risk checkpoint (roadmap risk 1):** play with 6+ survivors, all on auto. If that isn't
      viable, the item and web systems need **shrinking** — not the UI improving.

### Needs — spec: [docs/04](docs/04-survival-needs.md)

**Open (4):**

- [ ] Hunger, thirst, rest, mood *(temperature and hygiene deferred)*
- [ ] Mood as summed modifiers with named sources
- [ ] Mood consequences: slower work, more mistakes, refusing jobs, arguments
- [ ] Injured survivors consume without producing

### Moved here from Milestone 1, because this is what unblocks them

Both sat as open Milestone 1 tasks that Milestone 1 could not finish. Listed here rather than deleted,
with their original notes, so a reader can tell "nobody got to it" from "it was waiting on something".

**Open (2):**

- [ ] **Last-known position memory**, degrading descriptively
      *(bodies that vanish at a wall edge read as a bug; bodies you lose track of read as the game.
      And a marker that follows an unseen body is a lie, which
      [the fairness rules](docs/01-hardcore-contract.md#fairness-rules) forbid outright.
      **Half done:** the renderer fades a mark where a body was last seen, and it stays put rather
      than tracking. The simulation half — per-observer memory, in skill-scaled prose that degrades
      from "a moment ago" to "a while ago" — is not built, and belongs with the
      [condition view](docs/05-health-injury.md#the-condition-view).)*
      *(**moved from Milestone 1.** The renderer already holds the presentational half and its comment
      is written for the swap — when the simulation grows this, the drawing does not change, only where
      the fact comes from. Two things make it bigger than it looks: it is the first genuinely **new save
      state** in the project, because memory is a function of history rather than of current positions
      and so cannot be re-derived on load, which means a `SAVE_VERSION` bump; and the write pass is the
      first observer × body loop in a file whose whole argument is that per-observer cost does not
      amortise.)*
- [ ] Nights vary: the [director](docs/17-director.md) decides what tonight is
      *(docs/02's night-type table. Needs the director, which is Milestone 2.)*
      *(**moved from Milestone 1.** It needs the director, and the director is here.)*

### Health & injury — spec: [docs/05](docs/05-health-injury.md)

**Open (11):**

- [ ] Body parts with located conditions; **no health bar anywhere**
- [ ] Injury types: scratch, laceration, deep wound, bite, fracture, sprain, burn, concussion
- [ ] Continuous conditions: blood loss, pain, exhaustion
- [ ] **Bacterial infection kept distinct from zombie infection**, drawing on the same antibiotics
- [ ] Treatment steps: stop bleeding → clean → close → dress → rest, each timed and interruptible
- [ ] Supply quality tiers affecting infection risk
- [ ] **Skill-scaled diagnosis text** — what you see depends on who's looking
- [ ] Permanent conditions (limp, amputation) that don't remove a survivor from play
- [ ] **The condition view** — a paperdoll of head / torso / arms / hands / legs / feet with located
      conditions on the part they are on, spec:
      [docs/05](docs/05-health-injury.md#the-condition-view)
      *(a layout for the skill-scaled prose above, not a second representation of it. It shows what
      the **examiner** believes, so a bite presenting as a scratch presents as a scratch on the
      forearm — which is why it strengthens
      [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) rather than
      carving an exception to it.)*
- [ ] Four descriptive states per part — unhurt / hurt / badly hurt / unusable — as **tint and prose**.
      **No fill, no percentage, no pips, and no tooltip carrying a number the screen doesn't show**
- [ ] Diegetic readouts for the continuous conditions and stamina — breathing, weapon sway, swing
      recovery, a limp, the screen edges closing in, blood on the ground
      *(the bodies to hang these on now exist — see the character models in Milestone 0's render
      section. Swing recovery and the crawl already read as poses; a limp is a walk cycle with one
      leg's stride shortened, which is a `BODY_SPECS` entry rather than new machinery.)*
      *(every one of these is already a specified mechanical consequence. The change is that the
      consequence **is** the readout — nothing is displayed twice, once as an effect and once as a
      meter.)*

### Infection — spec: [docs/06](docs/06-infection.md)

**Open (9):**

- [ ] Transmission by vector, reduced by armor coverage
- [ ] **Private transmitted flag** decided at wound time and never retroactively changed
- [ ] Five-stage timeline with stage-appropriate symptoms
- [ ] **Early stages indistinguishable from sepsis**
- [ ] Observation model: what the player sees, filtered by examiner skill
- [ ] The five responses: amputate (stages 1–2 only), cauterize, antibiotics, quarantine, put down
- [ ] Turning — including inside the walls, at night
- [ ] Gear comes off the body in every case
- [ ] ⚠ **Risk checkpoint (roadmap risk 2):** do players quarantine, or just execute? Universal
      execution means the investment curve is too shallow and permadeath has no teeth.

### Combat — spec: [docs/09](docs/09-combat.md)

**Open (11):**

- [ ] Ranged: raise → steady → fire → recover → reload, all interruptible
- [ ] Accuracy as a **cone**, never a displayed hit chance
- [ ] **Aiming** — free aim against the [facing](docs/28-visibility-and-sightlines.md#what-an-observer-is)
      the visibility work already added, spec: [docs/09](docs/09-combat.md#aiming)
      *(the steady phase **is** holding the heading on something; being shoved or grabbed moves the
      muzzle rather than cancelling an abstract state)*
- [ ] **Weapon sway as the readout** — the cone drawn as the thing itself, not as a number about it.
      No reticle that reports its own accuracy
- [ ] Melee reach and swing arc read from the same facing
      *(which is what makes reach legible as a property, and what makes being surrounded lethal in the
      way [clause 1](docs/01-hardcore-contract.md#1-you-are-weak-permanently) promises)*
- [ ] You cannot aim at what you cannot see — firing at a remembered position is allowed, and costs
      the full 180 noise and 60 muzzle flash either way
- [ ] Steadiness degraded by movement, exhaustion, pain, injured arms
- [ ] Jamming on degraded weapons
- [ ] Ammo consumption
- [ ] Gunfire emits its full attention cost — **the parity contract must be live in the slice**
- [ ] NPC combat from assigned posts, breaking off when critically injured

### Items — spec: [docs/10](docs/10-items.md)

**Done (4):**

- [x] 13 bases: five melee, four containers, four supplies
      *(ranged bases wait for the ranged loop -- inventing their content before the system that
      reads it is inventing it blind, which is the argument `src/sim/combat.ts` already makes
      about weapon profiles)*
- [x] ~10 affixes with tiered values, including double-edged ones
      *(eleven. Two of docs/10's list -- **of the Butcher** and **of the Steady Grip** -- are not
      here, and deliberately: both are conditional on the target's or the wielder's state, and
      [docs/21's cut list](docs/21-extensibility.md#cut-list) puts modifier conditions in code
      rather than content. They arrive with the system that owns the condition.)*
- [x] 3 tiers: Scavenged, Modified, Field-Tested
- [x] Carry weight and encumbrance
      *(recursive over nested containers, emitted as `move_speed` and `stamina_recovery`
      modifiers, and **never shown as a number** -- see the grid, below)*

**In progress (1):**

- [~] Condition degradation affecting performance continuously
      *(the curve is built and read -- damage and swing speed both scale with wear -- but nothing
      degrades yet, because wear is driven by use and the systems that use things publish the
      events it will subscribe to)*

**Open (3):**

- [ ] Attachment slots on 2 base classes, with attachments movable between compatible bases
      *(the slots are declared in content already; nothing reads them yet)*
- [ ] Armor as **coverage per body part**, reducing bite transmission rather than granting tankiness
- [ ] Repair that **never restores the full ceiling**
      *(`Condition` already carries the ceiling, so repair is a system rather than a data change)*

### The grid inventory — spec: [docs/10](docs/10-items.md#inventory-space-and-weight)

**Done (8):**

- [x] Placement primitive: footprints, rotation, bounds, overlap, a declared free-slot scan order
- [x] Containers as entities, so a pack is an item with a grid and pockets are a grid with no item
- [x] Nesting to depth 3, with cycle and depth guards *(both mutation-tested)*
- [x] Stacking, splitting and merging, with the per-base limit respected
- [x] Equipped containers granting their grid — **what you can carry is what you chose to wear**
- [x] Ground items, pickup within arm's reach, and drop
- [x] Every rearrangement as a `Command`, so drags land on a tick and enter the replay record
- [x] Save/load of a nested loadout, and determinism across a scripted drag sequence

**Open (2):**

- [ ] Searching a container in the world (a car boot, a cupboard) rather than only carried ones
- [ ] Weight affecting the *sound* of a footstep — the obvious link into
      [the attention field](docs/03-attention.md) that nothing has drawn yet

### Modification — spec: [docs/11](docs/11-crafting.md)

**Open (4):**

- [ ] **Duct Tape** — reroll one random affix
- [ ] **Scrap Kit** — add an affix to a free slot
- [ ] Skill- and trait-weighted outcomes; injured hands make it worse
- [ ] Failure consuming the consumable and damaging condition

### Skill web — spec: [docs/08](docs/08-skill-web.md)

**Open (4):**

- [ ] Stub web: one melee branch, one ranged branch, ~12 nodes
- [ ] **Region-tagged points earned by doing** — you cannot grind a build you aren't living
- [ ] Node effects expressed as modifiers, in content
- [ ] Auto-allocation paths per Focus, stopping short of keystones

### Building — spec: [docs/15](docs/15-base-building.md)

**Open (7):**

- [ ] Walls, a gate, barricades
- [ ] **Damage states shown descriptively** — intact → scratched → splintering → gaps → breach
- [ ] One trap
- [ ] One bait emitter *(the mechanic that makes this steering rather than blocking)*
- [ ] Construction emits sustained noise
- [ ] Repair as a job with a real daily cost
- [ ] ⚠ **Risk checkpoint (roadmap risk 3):** are sieges frequent enough to justify building? If not,
      the [director](docs/17-director.md) needs a minimum siege cadence — a pacing change, not a change
      to the attention model.

### Director — spec: [docs/17](docs/17-director.md)

**Open (7):**

- [ ] Colony power and strain estimation
- [ ] Pressure, composition, and migration levers *(it adjusts pressure; it never spawns at your gate)*
- [ ] **Guaranteed lulls** after costly nights
- [ ] Week-one grace period
- [ ] Variance floor and ceiling
- [ ] Event seeding gated on colony state
- [ ] "Nothing Personal" preset — director off, as a balance baseline

### Death & succession — spec: [docs/01](docs/01-hardcore-contract.md#succession-what-happens-when-you-die)

**Open (6):**

- [ ] Permadeath for everyone, player included
- [ ] Succession: hand control to another survivor, save continues
- [ ] Skill web dies with the character
- [ ] **Corpse persists with all gear on it, where it fell**
- [ ] Colony morale hit; work priorities cleared
- [ ] Run ends only when the last survivor dies

### UI — spec: [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)

**Done (2):**

- [x] Inventory and equipment UI — `src/ui/inventory.ts`, the first screen in the game
      *(drag to move, right-click or `R` to rotate, drag onto a slot to wear, drag out to drop. It
      reads a snapshot rather than the world, and every gesture is a command -- so it cannot write
      to `sim/` and cannot reach a state the simulation would have refused.)*
- [x] The [condition view](docs/05-health-injury.md#the-condition-view) screen — the paperdoll above,
      rendered
      *(pulled forward with the stance ladder, because a paperdoll is a picture of a posture and
      building the two separately means two answers to what crouching looks like. **Two tiers of one
      readout**: a small always-visible glimpse on the canvas showing tint and posture, and a panel
      on the inventory screen adding a line of prose per part. The glimpse says *where*, the panel
      adds *what*, and neither says *how much* — `conditionView` carries a state and a sentence per
      part and **no integrity number at all**, which is what makes a fill impossible to draw rather
      than merely discouraged. `paperdoll.test.ts` serialises the snapshot and asserts the absence.
      The figure is an **anonymous outline seen flat on** — `render/sprites/outline.ts` — and not
      the body from the street: the district's camera hides the part the reader is asking about.
      One set of proportions, three postures; prone is the same figure turned a quarter turn.
      Six parts, four states, one voice of prose — the **untrained** tier of docs/05's diagnosis
      table, because there is no [skill web](docs/08-skill-web.md) to scale against yet and
      inventing a scale would be inventing the skill system in a string table.)*

**Open (6):**

- [ ] **No numbers anywhere player-facing** — no health bars, no hit chances, no enemy counts, no
      damage text
      *(unchanged, and the two items below are not exceptions to it. A paperdoll of located conditions
      answers "what is wrong and where"; a bar answers "how much is left". Only the second one is
      prohibited, and it is prohibited for stamina too.)*
- [ ] The diegetic condition and stamina readouts — in the world and on the survivor, not in a corner
      *(the glimpse above is a corner, deliberately and for now: docs/05 wants blood on the ground
      where they have been standing and breathing you can hear. This is the thing that replaces it,
      not a step toward it.)*
- [ ] Prose condition descriptions **generated from modifier sources** ("cold, tired, and that arm
      isn't right")
- [ ] Priority grid UI
- [ ] Skill web UI
- [ ] Pause and speed controls

### Balance harness — spec: [docs/19](docs/19-architecture.md#testing-strategy)

**Open (3):**

- [ ] Headless multi-run harness — thousands of colonies across seeds
- [ ] Distribution assertions: quiet nights, sieges, deaths, run lengths
- [ ] ⚠ **Risk checkpoint (roadmap risk 6):** measure whether melee-only and ranged-only colonies
      survive comparably. Elegant-on-paper parity usually collapses in playtesting — this is how we
      find out without arguing about it.

## Beyond the slice (designed, deliberately unbuilt)

Restated here because a backlog is where scope creep actually happens. All of it is designed and
deliberately deferred — see each document's cut list.

**Deferred to Milestone 3+:** [weather](docs/16-weather.md) · the full
[decay clock](docs/13-world-decay.md) and mutation waves · every [zombie type](docs/14-zombies.md)
beyond the shambler · the full [skill web](docs/08-skill-web.md) · [named items](docs/10-items.md) and
[unique survivors](docs/07-survivors.md) · relationships and grief · temperature and hygiene · the
remaining [modification consumables](docs/11-crafting.md) · [factions](docs/18-factions.md) · the escape
endgame · the full sandbox and storyteller layer.

### Moved here from Milestone 1, because weather and vehicles are what unblock them

Four items that were open Milestone 1 tasks and could not be finished in Milestone 1. Kept with their
original notes, so a later reader can tell a deferral from an oversight.

**Open (16):**

- [ ] **Wet ground** when [weather](docs/16-weather.md) arrives — rain quiets a hard surface and
      turns dirt to mud
      *(the obvious next thing the layer is for, and the reason it is two numbers per surface rather
      than two constants in the movement system)*
      *(**moved from Milestone 1.** The surface layer carries two numbers per surface rather than two
      constants in the movement system precisely so this could land.)*
- [ ] Surfaces in content JSON rather than a table in `surface.ts`
      *(five surfaces × two numbers is small enough to read at a glance today. It stops being small
      the moment weather makes them wet — see below.)*
      *(**moved from Milestone 1**, and gated on the item above rather than on effort: the move is an
      hour of mechanical work — a schema, a loader, a boot option and a drift test, mirroring
      `calibrationFromContent` — for zero behaviour change while the table is still ten readable
      numbers. Wet ground doubles it, and that is the trigger. `LIGHT_TABLE` is a third precedent for
      leaving calibration in code with a test pinning content against it.)*
- [ ] Vehicles read the same layer — "off-road is slow, damaging, and impassable for most
      [mobile bases](docs/26-mobile-bases.md)" is the other half of the Roads promise, and it waits
      on vehicles
      *(**moved from Milestone 1.** It was always waiting on vehicles.)*
- [ ] Longer nights in winter *(needs [weather](docs/16-weather.md)'s seasons)*
      *(**moved from Milestone 1.** It was always waiting on weather's seasons.)*
- [ ] Authoritative host: the same `sim/` kernel headless, clients send commands, host ticks
- [ ] `playerId` on `Command`, and merged-queue ordering by `(tick, playerId, seq)`
      *(late commands dropped rather than applied late, and the client told)*
- [ ] Per-client **filtered view** — the client is never sent state it may not know, built on the
      [visibility primitive](docs/28-visibility-and-sightlines.md) from Milestone 1
      *(a filter is worthless without a visibility query. Filtering state to a client that then draws
      what it holds through a building buys nothing, which makes doc 28 a **dependency** here rather
      than a companion.)*
- [ ] Late join and reconnect over the existing save path; the version stamp becomes the join check
- [ ] Host-owned time control: 1×, no pause *(the [core loop's](docs/02-core-loop.md#time-scale)
      unlimited-pause rule is scoped to single-player, not deleted)*
- [ ] Succession per player, onto **unclaimed** survivors only; spectate when none exist
- [ ] Survivor-vs-survivor PVP behind host flags — friendly fire, looting the dead — default off
- [ ] Survivor-vs-survivor combat **resolution** — a player survivor hit, injured and killed by the
      ordinary model
      *(needs no new mechanics; it is gated on the melee loop and
      [scoped out of the faction deferral](docs/09-combat.md#cut-list) rather than waiting on it)*
- [ ] **Voice as an emitter:** a `speak` command carrying a register, not an amplitude.
      Whisper 2 / talk 8 / shout 120, the last being the emitter already shipped
- [ ] WebRTC audio on a separate transport, spatialised client-side, with **audible range equal to
      emission reach** — what a teammate hears is what a zombie hears
- [ ] ⚠ **Risk checkpoint ([roadmap risk 9](docs/23-roadmap.md#risks)):** validate what a client may
      know about the attention field **before writing transport code**. The field is world state and
      the noise channel is a map of where everyone just was — ship it whole and the host model's
      whole reason for existing is defeated.
      *(no longer a blank page:
      [docs/28 proposes an answer](docs/28-visibility-and-sightlines.md#what-a-client-may-know--a-proposed-answer-to-risk-9)
      — entities by sight, the field **per channel** rather than by sight, and the `O` overlay
      conceded as host-only. The checkpoint is now a validation, and the open part is whether an
      audible-not-visible noise view leaks position anyway.)*
- [ ] ⚠ **Risk checkpoint ([roadmap risk 10](docs/23-roadmap.md#risks)):** a benchmark scenario with
      synthetic clients attached, held at **the same budget as its single-player twin**. Per-client
      filtering scales with player count, a shape no existing budget has.

## Open questions nobody has answered

- **Is being quiet *tense*, or just slow?** Half-answered, and the half that is answered is the one
  that was blocking. Quiet is no longer *completely safe* — the noise field still reads zero live
  cells when you stand still, but scent finds you anyway over about an hour, 30 bodies within 50 m
  becoming 76. Whether an hour of creeping pressure *plays* as tense or merely as slow is still a
  question for a human at a keyboard, but it is now a tuning question rather than a design hole.
- **Does one shout being a district-wide event make shouting the only verb?** New, from watching it
  run. The magnitudes are right and the reach is what docs/03 calibrated for; the question is whether
  a stimulus that always recruits everybody leaves room for the quieter ones.
- **Does a migrating horde make the district legible or unpredictable?** New, and the most interesting
  thing this build produced. A disturbed horde now walks off downwind following its own scent, which
  means the player can *read* where it went from the wind — or be surprised by a crowd arriving from
  a direction nothing happened in. Which of those it feels like is a playtest question.
- **Is 90 minutes the right scent half-life?** It is the constant the whole channel's feel rests on
  and it was picked, not derived. Residue lasts ~40 minutes in practice, which is what makes the
  migration self-limiting; halving or doubling it changes how long a mistake follows you around.
- **Is a district you cannot see tense, or merely opaque?** New, and the most immediate consequence
  of the visibility work. The survivor now sees 11 bodies where 216 were being drawn. Reading the
  horde was already meant to be a skill; the question is whether removing that much information
  makes the district feel dangerous or just makes it feel empty until something is suddenly adjacent.
  A human at a keyboard, and the first thing to check next session.
- **Does the ground actually change where you walk?** New. The street is fast and loud, the yards
  are slow and quiet, and undergrowth is slow, loud and the only cover. The tables say a route is a
  decision; whether a player *notices* that without a readout is the question, since the HUD's
  ground line is a developer tool and the shipped game will not have it.
- **Are the arcs right?** 60° focal inside 190° total was picked, not derived, and docs/28
  deliberately declined to name numbers so that nobody would read them as settled. They are per
  observer and in one file. Widening the peripheral arc is a one-line experiment.
- **Does a body standing still in your peripheral vision deserve to be invisible?** It is the
  mechanic as specified — movement is noticed out there, identity is not — and it means a shambler
  that stops moving nine metres to your left is simply not on screen. Correct, and possibly
  horrible.
- **How long is a day, really?** Four hours at 1× is still a guess — but it is now a guess you can
  sit through, at 10×, in 24 minutes. `DAY_SECONDS` is one constant.
- **Is night tense, or just a nuisance?** New, and the sharpest question this build produced. Night
  currently takes the survivor's sight from 48 m to 12 and offers nothing in exchange, because the
  light channel does not exist. If it plays as pressure, the number should go *darker* when torches
  arrive. If it plays as an annoying filter, that is a signal the dark needs its counterplay before
  it needs more of itself.
- **Is a session with no pause still this game?** New, from the multiplayer design. The core loop
  claims the tension comes from irreversibility rather than APM; multiplayer removes the pause and
  keeps everything else, which tests that claim about as directly as it can be tested.
- **Does voice-as-emitter play as tense, or as a mute button?** Also new. If never speaking is
  dominant, the mechanic removed a channel instead of adding one.
- **Is the grid a decision or a chore?** The newest question, and the one nothing but playing will
  answer. Tarkov's inventory is famously either the best part of the game or an admin screen, and
  which one it is here depends on numbers that are currently guesses: pocket size (4×2), the pack
  grid (6×8), and how often a run actually fills it. **If rearranging is fiddly rather than tense,
  the fix is bigger cells and fewer of them, not a better UI.**
- **Does invisible weight read at all?** Encumbrance costs speed and stamina recovery and prints
  nothing, per clause 4. That is the right principle and it may simply not be *legible* — if players
  never notice they are overloaded, the signal needs to be louder in the world (gait, breathing,
  footstep noise) rather than quieter in the UI.
- The rest are listed under "Open questions" in [`docs/23-roadmap.md`](docs/23-roadmap.md).

*"How big is a district?" is no longer among them — it's 256 m, forced by the noise calibration.
"What does continuous scent cost?" is no longer among them either — 0.0075 ms a tick, and it was
never going to be the problem.*

## Settled decisions: do not relitigate

These were each decided explicitly by the repo owner. If you're about to "improve" one, don't:

- **Hardcore is the thesis, not a difficulty slider.** Permadeath with succession into another
  survivor; no win condition plus an optional expensive escape.
- **No wave timer.** Horde pacing is attention-driven and director-paced.
- **Blank slates, no classes.** The build lives in found gear (PoE-shaped affixes) plus a classless
  skill web earned by doing. Applies to every survivor, not just the player.
- **Survivors are unlimited and procedurally generated.** Recruits arrive as unskilled nobodies — that
  is the counterweight that keeps permadeath meaningful.
- **Melee and ranged both good**, spending non-convertible currencies (body/bite-risk vs.
  ammo/attention).
- **Fully drivable continuous region**, no abstracted travel legs. **Full nomad play viable.**
- **Performance is pillar 6**, with CI budget gates that fail the build.
- **Stack:** TypeScript + canvas + Vite, no engine, with a portability contract keeping a Godot pivot
  cheap. **Saves may break pre-1.0** — stable IDs and a version stamp, but no migration framework.
- **The inventory is a grid, and weight is invisible.** Tarkov/DayZ-shaped: cells, footprints,
  rotation, nesting, and containers you have to wear to get. This *replaced* the weight-and-capacity
  model `docs/10-items.md` originally specified, and the argument is not genre nostalgia — a capacity
  bar is a number about your capacity, which
  [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) prohibits outright,
  and a grid is the same information as shape. Weight is still simulated and still never printed:
  you find out you are overloaded by walking slower. **There is no kilogram on the inventory screen**
  and adding one is a contract violation, not a UX improvement.
- **Vehicles were un-cut** after initially being cut at the vision level. `docs/00-vision.md` records
  the reversal and why the original objection was half right.
- **A district is 256 m, falloff stays linear.** Decided against re-authoring the magnitude table,
  because its ratios are load-bearing in six documents and only the unit was ever missing.
- **Field memory is scent, never noise.** Kept rather than cut, on the condition that Milestone 1
  proved it did something. **It did** — though not the something that was written down. See
  [what scent changed](docs/30-decisions.md#what-scent-changed-and-what-it-corrected).

## Conventions and gotchas

- **Never put an em dash in a heading you intend to link to.** GitHub's anchor slugs collapse
  ` — ` into a double hyphen, and it has silently broken links three times in this repo. Use a colon.
  Several headings were rewritten for exactly this reason.
- **Every doc opens with "why this exists" and closes with a cut list.** The cut lists are load-bearing
  — they're what stops scope creep, and [Beyond the slice](#beyond-the-slice-designed-deliberately-unbuilt) restates them for the
  same reason.
- **The README index is the reading order.** File numbers reflect authorship order.
- **Events are queued, not immediate.** `publish` enqueues; handlers run on `drain`, which the tick
  does once. Anything that publishes outside a tick and expects the effect immediately -- `equip` at
  boot, a test asserting on the result -- has to drain first. This cost an hour: the melee bridge
  looked broken when it was only late.
- **A right-click mid-drag is not a `pointerdown`.** Once the primary button takes pointer capture,
  Chromium delivers no second `pointerdown` for another button -- only `contextmenu`. Verified by
  instrumenting the canvas. `platform/pointer.ts` keys rotation off `contextmenu` for this reason.
- **`npm run bench:frame` needs a browser path here.**
  `CHROMIUM_PATH=/opt/pw-browsers/chromium-*/chrome-linux/chrome npm run bench:frame`.
- **The container is ephemeral.** Anything uncommitted is gone when the session ends.
- `.claude/settings.local.json` is git-ignored globally and won't travel with the repo.

## A habit worth continuing

Every guard added so far was **mutation-tested**: break the thing on purpose, confirm something goes
red, put it back. That is not ceremony — it caught two guards that looked rigorous and tested nothing:

- A modifier-ordering test using `0.1 / 0.2 / 0.3` passed with the fold sort deleted, because later
  multiplications rounded the difference away. Catastrophic cancellation fixed it.
- The frame budget passes with viewport culling removed, because 2,000 flat rectangles are cheap. It
  is a regression guard today, not proof that culling earns its place; it will bite when sprites
  replace rectangles. Recorded here so nobody reads it as stronger than it is.

  **Sprites have now replaced the rectangles, and it did not bite.** The same mutation with
  character models in place: draw 2.26 ms with the cull deleted against 1.89 ms with it, both
  comfortably inside the 4 ms budget. The prediction was wrong, and the reason is worth having --
  *visibility* rejects 1,986 of 2,001 bodies before anything is drawn, so the viewport cull is
  removing work that occlusion was going to remove a few lines later either way. The two guards
  overlap almost completely, and the cheaper-looking one is not the one carrying the budget.

  So the note stands, with its expiry removed: viewport culling is still a regression guard rather
  than a proven cost saving, and the thing that would actually make it earn its place is a case
  where a great many bodies are *visible* at once -- a horde in open ground at night, not a street
  full of bodies behind walls.

The noise spine's three guards were each broken on purpose and confirmed red:

- Delete the angular bias → twenty shamblers in one cell collapse to a single heading.
- Delete the decay system → the district never falls silent.
- Delete the travel commitment → the horde forgets the moment the gradient dies.

Scent's seven were done the same way, and one of them found a hollow guard on the first try:

- `addScent` sums → change it to `max` and two bodies stop smelling more than one.
- Wind weights → pair each neighbour with its own weight instead of the opposite one and the plume
  drifts *upwind*.
- Scent decay → **the first version of this guard passed with the decay term deleted**, because a
  plume evaporates by dilution anyway. Now measured in isolation with the diffusion rate at zero.
- The scent floor → point it at noise's floor and a smell's lifetime collapses.
- Kernel diffusion → unregister the system and the field only ever holds what emitters wrote.
- The scent bias → remove it from the wander branch and standing still is safe forever again.
- Residue → the acceptance check *is* the mutation, and it toggles a shipped module rather than
  editing the code under test.

Sight's guards were done the same way, and the fourth hollow one turned up on the first try:

- Reveal every tile the wedge touches instead of only those whose centre is inside it → the symmetry
  check finds asymmetric pairs at every corner.
- Define `blocksSight` as `isSolid` → three tests go red at once: the window, the foliage, the
  low cover.
- Ignore the eye level → standing and crouching see the same thing over a car.
- Recompute unconditionally → "standing still is free" fails.
- Fold facing into the cache key → "turning is free" fails, and *nothing else does*.
- Make `invalidate()` a no-op → a wall built after the view was computed is invisible to it.
- Delete the sightline check from `detail` → **the first version of this guard passed**, because the
  arcs hide a third of a circle by themselves. Now counted inside the arcs only, plus a two-tile
  case with one wall.

The ground's guards were done the same way, and turned up a bug and a hollow guard in one sitting:

- Drop the surface factor from `movement.integrate` → grass, rubble and brambles all cross at the
  same speed.
- Drop it from `attention.emit-movement` → the two readings in the real district become equal.
- Hardcode the sprint threshold back to `2.8` → the "still exactly halfway" guard fails, and
  *nothing else does*, which is precisely why it needed its own assertion.
- Stop laying undergrowth under screening → the district loses a surface, and a bush becomes a free
  sightline break.
- **"Is this tile indoors?" answered by shape rather than by the generator** → the first version
  scanned outward for solid tiles in four directions, which the map perimeter satisfies for every
  tile in the district. It passed while measuring nothing, and it was hiding brambles growing in
  people's living rooms.

The day's guards were done the same way:

- Range ignores ambient light → night becomes a tint, and the "shrinks what a survivor can see"
  guard fails.
- Drop the rounding to whole tiles → dusk costs a shadowcast every tick.
- Make the phase publisher remember what it announced instead of comparing two ticks → the
  transition counts go wrong.
- Start a run at tick 0 → it opens in the dark, and the guard that says otherwise fails.

One of those, the decay system, needed a **second** test written for it: the arithmetic was already
covered by a unit test calling `decay()` directly, which passed happily with the system unregistered.
Covering the maths is not covering the wiring.

A green suite says nothing about whether it *can* go red.
