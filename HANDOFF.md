# Handoff

**Start here if you are picking this up cold** — a person or a fresh session. This is the engineer's
document: what is built, what is being built, what is next, and the roadmap through the vertical
slice. It replaced `TODO.md`, which used to hold the backlog separately and drifted from this file
three times.

Four other places to know about, and nothing else is required reading:

| | |
|---|---|
| [README.md](README.md) | The pitch, and the index of all 32 documents. User-facing. |
| [docs/23-roadmap.md](docs/23-roadmap.md) | Product scope, milestone order, the risk register, and canonical playtest questions. This file owns what is *built*; 23 owns what is *intended*. |
| [docs/31-godot-rebuild-roadmap.md](docs/31-godot-rebuild-roadmap.md) | The engine transition: phases, parity gates, delivery, risks, and cutover. It does not replace product scope in docs/23. |
| [docs/30-decisions.md](docs/30-decisions.md) | The decision records. Twenty entries of "what this chunk of work made structural" — read it before changing something that looks arbitrary. |

---

## Where things stand

| | |
|---|---|
| **Phase** | **Godot rebuild — R0 through R7 complete. Cutover done; Godot is the playable build at `/`.** All parity gates green; oracle archived at tag `ts-oracle-final`. Product Milestone 1 closed; Milestone 2 lethality landed; **stats MVP + unique NPC spawn** are in. |
| **It is playable** | Godot at `/` (and Windows artifact) — 256 m district with civic annex, Mara, knife in hand. `F` swing, `G`/click fire, `R` reload. Shambler / screamer / bloater on the map. HUD shows STR/CON/DEX. |
| **What is left of Milestone 1** | **Nothing required for closure.** |
| **Merged so far** | Through R7 cutover — `ts-oracle-final` tag preserves the last TypeScript oracle. Godot sim/presentation/platform/content all live under `godot/`. |
| **In flight** | **Early-alpha execution — roster + annex + ranged.** Screamer `alarm_on_sight` (300 noise, 30s cooldown), bloater `blooms_on_death` (scent 30 + 6 m / 90 s contamination flag), civic-annex JSON overlay on a 256 m district, bow/pistol fire loop, exhausted swings degrade. Gates: `godot:m2:roster`, `godot:m2:district`, `godot:m2:ranged`. |
| **Pulled forward on purpose** | **Items and the grid inventory, located survivor bodies and condition presentation, and the wound-time infection seam** — all Milestone 2 foundations that landed during Milestone 1. Grabs now produce a located wound with separate visible presentation and private transmission truth; progression, treatment, armor reduction, stages, and turning remain. |
| **Specified but deliberately unbuilt** | [Multiplayer](docs/27-multiplayer.md) (Milestone 3C), [z-levels](docs/23-roadmap.md#deferred-z-levels), INT/CHA/WIS (Milestone 3A — STR/CON/DEX shipped), [aiming](docs/09-combat.md#aiming), and docs/05/06's remaining injury types / sepsis. |

### Counting the backlog

| Milestone | `[x]` done | `[~]` in progress | `[ ]` todo | State |
|---|---|---|---|---|
| 0 — Foundations | 39 | 0 | 0 | ✅ **Closed.** Exit criterion asserted in `test/integration/exit-criterion.test.ts`. |
| 1 — The spine | 52 | 0 | 3 | ✅ **Closed.** Noise, scent, and light/sight are live; contact pursues, grabs, bites and can be broken with stamina. |
| 2 — The vertical slice | 33 | 1 | 77 | ◐ **Underway.** Lethality + stats + unique + roster/district/ranged landed. |
| 3+ — Beyond the slice | 0 | 0 | 16 | ☐ Designed, deliberately unbuilt. Prose lives in [docs/23](docs/23-roadmap.md). |
| **Total** | **124** | **1** | **96** | |

Milestones close on their **exit criterion**, never on the checkbox count.

### Godot rebuild track

This transition does not reopen the product checkbox totals above. Live engine status belongs here;
phase definitions and gates live in [docs/31](docs/31-godot-rebuild-roadmap.md).

| Phase | State |
|---|---|
| R0 — decisions and baseline | **Complete.** |
| R1 — walking skeleton | **Complete.** |
| R2 — world and attention spine | **Complete.** |
| R3 — danger, bodies, and belongings | **Complete.** |
| R4 — native presentation | **Complete.** |
| R5 — platform and delivery | **Complete.** |
| R6 — parity and hardening | **Complete.** Ledger + per-tick parity + coverage + mutation + soak green. |
| R7 — cutover | **Complete.** Godot at `/`; `ts-oracle-final` tag; rollback rehearsed. |

## Do this next

**R7 is closed. Infection lethality, the stats MVP, and the early-alpha execution slice are in.**
Roster behaviors, civic-annex overlay, and bow/pistol fire loop land behind `godot:m2:roster`,
`godot:m2:district`, and `godot:m2:ranged`. Exhausted swings now degrade (refuse path remains behind
`SimMelee.REFUSE_EXHAUSTED_SWINGS` until `crowded-and-swinging` is remeasured).

Rollback: `git checkout ts-oracle-final` (or `git show ts-oracle-final:src/sim/...`) restores the
archived oracle. `godot/parity/` fixtures and snapshots stay on `main` for comparison. Pages now
publishes Godot at `/`; a failed CI publishes nothing. `npm run build` is `godot:export`.

**Named leftover still in the code:**
- **The condition view has one voice.** docs/05 scales a part's prose by the examiner's Medicine
  skill — untrained gets "there's a lot of blood, he doesn't look good", skilled gets "deep
  laceration, sutured and clean, off work five days". There is no [skill web](docs/08-skill-web.md)
  to scale against, so what ships is the untrained tier and `godot/sim/condition.gd` says so. When
  the web lands, that table gains a column rather than being rewritten.
- **The HUD is player-facing.** The single concatenated developer Label is gone: `ui/hud.gd`
  draws four corners of prose (who you are and how you are; day and phase; the attention field
  in words; the key hints), `ui/legend.gd` shows the bindings on a fresh run and on `F1`, and
  the old numeric sheet moved behind the existing `M` toggle. `sim/attention_read.gd` is the new
  read model that finally makes docs/03's spine legible without the developer overlay — its
  noise bands are metres of reach, derived from `magnitude = metres × attenuationPerMetre`.
  Gate: `npm run godot:check:hud` (`HUD_OK`) allows no digits on the HUD but the day counter.
  Panels: equipment slots are three cells wide so item names fit, the injuries tab states each
  part's condition as a word, and the work grid shows full column names with its 1–4 scale
  explained. `ui/text.gd` fits text to a box with an ellipsis instead of `substr`.
- **The renderer is sprite-ready; there is just no art yet.** `appearance: {sprite, tint}` is in
  the zombie/item/survivor schemas, `presentation/appearance.gd` resolves a key to
  `assets/sprites/<key>.png` (imported resource first, raw file second, so a dropped PNG works in
  dev and headless CI without an editor round-trip), and `_draw_entities` branches to a
  feet-anchored `draw_texture_rect` or falls back to today's circles. Tiles are now **32×16**
  (`camera.gd` zoom 16) with nearest filtering and integer window scaling. The screamer and
  bloater colours that used to be literals in the draw loop now live in their JSON, which is what
  proves the pipeline with no art present. Gate: `npm run godot:check:appearance`
  (`APPEARANCE_OK`). Conventions in `godot/assets/sprites/README.md`.
- **The paperdoll scales to its control and names every stance correctly.** `_height` was a
  hardcoded 118.0 that ignored `size`, so the 260px gear-panel doll drew the same figure as the
  140px corner glimpse. `_figure_height()` fits `h` to whatever box the control actually is,
  bounded by whichever pose (standing tallest, prone widest) is tightest, so no stance clips at
  any size. The posture label was its own three-way ternary that mapped stance 0 (Crawl) to
  "stand" and stances 3–4 (Jog, Sprint) both to "walk" — three of five stances were mislabeled.
  It now reads `SimStances.NAMES`, the one canonical stance-name list, instead of keeping its own.
  Verified visually across all five stances at both sizes under Xvfb. Left alone: `sim/stance.gd`
  (singular) is dead code superseded by `sim/stances.gd` (plural) and uses a different component
  key (`"Posture"` vs the live `"posture"`) — unreferenced anywhere, so harmless, but a trap for
  anyone who greps for the wrong file.
- **The paperdoll draws all ten sided parts independently, plus wounds, infection, and
  armour.** The LEGACY_REGIONS bridge from the body split is gone — each arm/hand/leg/foot
  is now drawn and tinted from its own `arm_left`/`arm_right` (etc.) entry rather than the
  worse of the two. The figure faces the viewer (their left is your right), documented once
  in `SIDE_NAME` rather than re-decided per limb. `condition.gd`'s view grew three new
  boolean/word fields for this — `wounded` (has a recorded `injuries.wounds` entry on this
  part), `infected` (`SimInfection.diagnosis_of_part`'s `actionable` word, never a stage or
  `transmitted`), `armored` (`SimInfection.armor_coverage_of` — renamed public, was private
  — is greater than zero for this part) — all still words or booleans, never the number
  behind them. A wound draws a small ring, an infection a second ring beside it, armour
  thickens and re-colours the part's outline rather than competing with the condition tint
  for the fill. Verified visually under Xvfb with a body damaged asymmetrically, a recorded
  wound, an active exposure, and an equipped vest, all four active at once and all agreeing
  with the injuries-tab text.
- **Found while starting this: the sided-limb split had left arm armour dead.**
  `item.wrap.cloth` and `item.vest.scrap`'s `armor` blocks still keyed arm coverage as
  `"arms"` — the pre-split name — so `armor_coverage_of` never matched `arm_left`/`arm_right`
  and a worn vest gave zero arm protection against bite transmission. The item schema's
  `armor` property has no `additionalProperties: false`, so `godot:validate` could never
  catch this; only a real gate could, and none existed despite `check_m2_lethality.gd`'s own
  file comment claiming "armor reduces transmission" since before the split. Both are fixed:
  content keys split into `arm_left`/`arm_right`, and `_armor_reduces_transmission()` now
  actually tests it (`ARMOR OK armored=291 unarmored=427 of 500`).
- **New gates:** `_sidedness_is_independent()` and
  `_wound_infection_armor_are_true_words_not_numbers()` in `check_ban_health_bar.gd` assert
  the two sides of a limb can disagree and that the three new fields are real booleans/words
  with both a true positive and a true negative case — not just "no leak," which a field that
  was always `false` would also satisfy.
- **The health-bar ban is gated in Godot.** `godot/sim/condition.gd` is now the single builder for
  the view — `presentation/main.gd` and `ui/inventory_panel.gd` had each built it inline and
  drifted — and `npm run godot:ban:healthbar` (`BAN_HEALTH_BAR_OK`) serialises it and asserts no
  integrity, no maximum, and no fraction, with a key allowlist that fails when a numeric field is
  added. This is the port of the oracle's `paperdoll.test.ts`, which was the only enforcement.

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
meaningless without gear worth recovering, so it sits in Milestone 3C behind both. What did change:
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

Four nearby tasks remain open and deliberate rather than forgotten. Three are measured-and-deferred
Milestone 1 optimizations: dirty regions, the propagation budget, and sharing the spatial index between
emitters and culling. The fourth is Milestone 2's **simulation half of last-known-position memory** —
the renderer fades a mark where a body was last seen, but no observer *remembers* anything, and the
prose version belongs with the condition view.


## Quick start

```bash
npm install
npm run godot:run        # Godot — the game (also: godot:editor)
npm test                 # correctness: TypeScript suite (reference; Godot gates are godot:r6)
npm run godot:r6         # Godot parity/coverage/mutation/soak + bench/validate
npm run typecheck        # two projects — the second is the sim/ purity gate
npm run lint
npm run format:check
npm run bench            # tick budgets
npm run bench:frame      # frame budget, drives real Chromium
```

`WASD` move · `Shift` sprint · `F` swing / struggle · `Space` **shout** · `E` pick up · `Tab` inventory (drag to
move, right-click or `R` to rotate) · `O` cycles the attention overlay (off → noise → scent → sight) ·
`1`/`2`/`3` speed (1×, 3×, 10×) · `P` pause · `M` raw sprite sheets · `F5` save · `F9` load.

A day is four hours at 1×, so press `3` and wait for dark.

**Editing content while it runs.** Change any file under `godot/content/` and a valid edit reloads the page
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
   bare-eyed view closes from 48 m to 2. A body ten metres away in daylight disappears at midnight;
   a found candle reopens a small pocket around you.

## The build

Godot **4.7.1** is the shipping build. The public URL and Windows artifact both run the Godot
export from the same green commit. Rollback is to the tag, not to a second shipping build.

`.github/workflows/ci.yml` runs `check` (type, lint, tests plus Godot parity/project smoke/content/
bench/R6 per-tick/coverage/mutation/soak), `godot-exports` (verified Windows and web release
exports, real boot checks), and `performance` (tick then frame budgets). `pages.yml` checks out the
exact `head_sha` that passed CI, exports Godot web, and deploys `dist/` to
<https://simplyjaytea.github.io/simplyZOMBIES/> at `/`. A failed CI publishes nothing; each green
push replaces the previous build. `npm run build` is `godot:export`.

The oracle is archive-only: `git checkout ts-oracle-final -- src/ vite.config.ts index.html` (or
`git checkout tags/ts-oracle-final`) restores it; `godot/parity/` fixtures and snapshots stay on
`main` for comparison. No active workflow depends on `src/` or Vite for the deploy.

The rebuild uses the standard (non-.NET) Godot **4.7.1** build. `scripts/run-godot.mjs` accepts
`GODOT_BIN`, then checks the known local portable location and `godot4`/`godot` on `PATH`; it rejects
every other version. Useful commands:

```bash
npm run parity:r1:oracle   # regenerate the expected snapshot with the TypeScript oracle
npm run godot:test         # compare the Godot result with that snapshot headlessly
npm run godot:smoke        # instantiate the actual main scene and catch load/parse failures
npm run godot:run          # run the walking-skeleton presentation
npm run godot:editor       # open the pinned project in the editor
npm run godot:export       # produce dist-godot/windows and dist-godot/web
npm run godot:smoke:exports # boot the Windows executable and the web build in Chromium
```

> ⚠ `pages.yml` also has a manual `workflow_dispatch` escape hatch. Unlike the automatic path, that
> trigger does not prove CI succeeded; use it only to redeploy a known-good `main` revision. The
> automatic push-to-`main` contract remains fully gated.

## What's in the repo

```
docs/           32 documents: 30 product/architecture docs (00-29), the decision log (30), and
                the Godot rebuild roadmap (31). The README index is the reading-order authority,
                not the file numbers -- 24-26 belong under "The world", 28 sits beside the spine
                it serves, and 29 beside combat.
godot/          Godot 4.7.1 project — **the playable build**: sim (typed, fixed-tick), presentation,
                platform (storage/content/input/timing), content (canonical JSON), parity (fixtures
                + oracle snapshots + ledger), bench, export presets, and R6 gates.
scripts/        run-godot, smoke-exports, oracle tooling, handoff regroup.
src/            TypeScript oracle — archived at tag ts-oracle-final (reference only; not built).
                `sim/`/`render`/`platform`/`ui` remain there for parity reference.
test/           TypeScript unit/integration (reference; Godot coverage is godot/check_r6_*.gd).
bench/          TypeScript performance budgets (reference; Godot bench is godot/bench/).
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

The eleven [roadmap risks](docs/23-roadmap.md#risks), each pinned to the task that answers it. Two are
closed or retired and one is narrowed; exact status lives in the roadmap while this table locates the
engineering checkpoint.

| # | Risk | Answered by | State |
|---|---|---|---|
| 1 | The micromanagement cliff — *highest design risk* | Focus + auto-allocation, played with 6+ survivors | ☐ Milestone 2 |
| 2 | Unlimited survivors may undercut permadeath | Watching whether players quarantine or just execute | ☐ Milestone 2 |
| 3 | Unscheduled hordes may starve the tower-defense half | Building, played — are sieges frequent enough? | ☐ Milestone 2 |
| 4 | ECS + modifier pipeline may be over-engineering | Milestones 0–1 changed repeatedly without losing determinism or isolation | ✅ **Retired after Milestone 1** |
| 5 | Attention field performance | 500-zombie synthetic load, then the real continuous channel | ✅ **Closed.** Scent costs 0.0075 ms/tick — 0.1% of budget, and the same when saturated. |
| 6 | Melee/ranged parity may not survive contact | Balance harness: melee-only vs ranged-only colonies | ☐ Milestone 2 |
| 7 | Streaming a continuous region at driving speed — *highest engineering risk* | The drive benchmark, against synthetic load **before any vehicle exists** | ☐ Milestone 3, step 2 |
| 8 | Full nomad viability roughly doubles the balance surface | Balance harness on nomad-only, fixed-only, hybrid | ☐ Milestone 3, step 4 |
| 9 | What a multiplayer client may know about the field | Validation of docs/28's proposal, **before any transport code** | ◐ **Narrowed, not closed** — and it surfaced that visibility was a dependency, not a nicety |
| 10 | A host in the loop may not fit the frame budget | Synthetic-client benchmark at the single-player budget | ☐ Milestone 3 |
| 11 | Attributes may create mandatory builds or reroll fishing | Seeded cohort analysis plus Milestone 3A playtest | ☐ Milestone 3A |

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
      `src/sim/{kernel,modules,rng}`, `src/render`, `src/platform`, `src/ui`, `godot/content/`, `test/`
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

## Milestone 1: The spine (complete)

The [attention field](docs/03-attention.md) and something that reacts to it. This is the first point at
which the project is legible as a game, and it is.

> **Exit criterion:** make noise and zombies converge immediately; stop emitting noise and that
> response disperses, while scent makes stillness only temporarily safe.
>
> ✅ **Met** and asserted in CI (`test/integration/attention.test.ts`), and guarded from a
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
> The milestone is **closed**: contact pursuit, grabs, located bites, private transmission truth, and
> stamina-paid escape complete the melee danger loop.

**52 done, 3 measured-and-deferred tasks.** The complete attention system is in: the **noise spine**
(field, gradient ascent, a shout), **scent** (continuous diffusion, wind, field memory), and **light**
(a separate shadowcast from every emitter, zombies with eyes, and a night dark enough that a found
candle matters). Both ⚠ checkpoints riding on scent are closed, and light deliberately does not live
in the coarse field —
[entry 15 in the decision log](docs/30-decisions.md#what-light-made-structural).

**And the field now has a fourth thing writing to it that is not a channel: you.** The
[stance ladder](docs/29-movement-and-stances.md) is what turns docs/03's emitter table into a decision
made continuously rather than a property of being alive — five rungs, each with its own speed, its own
noise and its own price, and the largest gap deliberately left between jog and sprint because that gap
is where the decision lives.

**Six items moved out**, because Milestone 1 could not finish them: wet ground, surfaces-in-content,
vehicles-read-the-layer and longer-nights went to [beyond the
slice](#beyond-the-slice-designed-deliberately-unbuilt); nights-vary and last-known-position memory went
to [Milestone 2](#milestone-2-the-vertical-slice-underway). Each kept its note and gained a line
saying what unblocks it. An open count is only worth reading if the things in it can be acted on, and
six of them could not.

**Three more are marked ⏸ deferred on measurement** — dirty regions, the propagation budget, and sharing
the spatial index. Each says what would change the answer, because "nobody got to it" and "this was
measured and refused" should not look the same in a backlog.

**There is no closure work left.** Grabs and bite risk landed on the six-part body and private
infection seam. The three unticked Milestone 1 entries are performance optimizations deferred behind
explicit measurement triggers, not unfinished acceptance criteria. See [Do this next](#do-this-next)
for the Milestone 2 continuation.

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
      *(`godot/content/calibration/attention.json`. `DEFAULT_CALIBRATION` shadows it because content loads
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
      [spike failed exactly this check](docs/23-roadmap.md#spike-findings-attention-field)
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

- [x] Shambler entity with a sensory profile weighting noise, scent, and visible light
      *(noise is an impulse, scent a wandering bias, and wall-occluded light a gated lean)*
- [x] Gradient ascent on noise, and **scent as a bias** — it bends a wandering shambler's heading a
      third of the way toward what it can smell, but never seizes it, never commits it, and never
      changes its state. Noise stays the only *impulse*. That asymmetry is what keeps the noise exit
      criterion intact now that the player emits scent permanently and cannot stop.
      Light is a separate wall-precise shadowcast rather than a coarse field layer
- [x] **Persistent per-individual angular bias (±0.62 rad)** on the gradient direction — assigned once
      at spawn from the seeded RNG stream, never re-rolled, **included in save state**. Without it
      they form [conga lines, not a horde](docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own).
      *(mutation-tested: delete the bias and twenty shamblers in one cell collapse to a single heading)*
- [x] Investigate on arrival → mill → disperse, **raising local scent** while they mill
- [x] **Damage model: head and locomotion are what matter; a crawler is still lethal**
      *(three pools rather than one, from `godot/content/zombies/base.json`'s `body` block, which had
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

**Done (13):**

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
      docs/09 wants exhausted swings "slow, weak, and miss" rather than absent — Godot now scales
      `swing_speed` / `swing_recovery` / `melee_damage` from pool emptiness. The refuse path remains
      behind `SimMelee.REFUSE_EXHAUSTED_SWINGS` until `crowded-and-swinging` is remeasured.)*
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
- [x] **Grabs, and breaking free** — and with them, bite risk
      *(actual hold range is 1 m, separate from 1.6 m pursuit contact so weapon reach remains real.
      A hold pins movement, interrupts wind-up and makes `F` a one-second, 20-stamina struggle.
      Additional grab strength progressively lowers escape chance without making it impossible;
      success releases every source. Bites begin after 1.5 s and repeat every 2 s, creating located
      damage and a saved wound whose presentation is a scratch 30% of the time. A separate named
      deterministic stream saves the private 85% transmission answer. The UI receives neither that
      answer nor a numeric chance. Full disease progression remains Milestone 2.)*

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

## Milestone 2: The vertical slice (underway)

One district, a handful of survivors, and enough of every system to find out whether the loop is fun.

> **Exit criterion:** survive ten in-game days, become invested in a survivor, lose them permanently,
> continue through succession, and still want another run afterward — playable end to end without a
> developer explaining it.

Milestone 2 is underway through foundations pulled forward during Milestone 1: **items and grid
inventory, located bodies and the condition view, melee reach, pause/speed control, and the private
infection-transmission seam**. The first end-to-end slice is lethality: symptoms, diagnosis,
treatment, armor reduction, stages, and turning on top of that seam.

### Dependency order

1. Lethality: injury, infection, treatment, turning, and armor interaction
2. People and economy: generation, needs, work, district, resources, search, and spoilage
3. Ranged parity: actions, aiming/sway, ammunition, items, and NPC combat
4. Automation: shallow six-region web, Focus paths, and loadout upkeep
5. Defense and pacing: building, then the slice director
6. Continuity: recruitment, death, corpses, and succession
7. Proof: headless distributions, then the human ten-day playtest

### World & map — spec: [docs/12](docs/12-resources.md)

**Done (1):**

- [x] One hand-authored map: a small district with a defensible building
      *(civic annex overlay `godot/content/maps/district_alpha.json` blit after `generate_district`;
      `godot:m2:district` gates rect confinement, L-shell, loot, playable boot)*

**Open (4):**
- [ ] ~15 resource types
- [ ] 3 location loot tables (residential, commercial, medical)
- [ ] Site depletion — cleared is cleared
- [ ] Food spoilage *(the only [decay track](docs/13-world-decay.md) in the slice)*

### Survivors — spec: [docs/07](docs/07-survivors.md)

**Done (2):**

- [x] Stats MVP: STR + CON + DEX (integers 3–8, fixed total 15) as `aptitudes` + `attr.*` modifiers
      *(carry_capacity, grab_escape, infection_progression rate, damage_taken, move_speed; missing
      keys default 5; HUD shows the numbers; `godot:m2:stats`)*
- [x] Unique survivor pipeline: `godot/content/survivors/uniques/*.json` + Mara Okoro in the playable boot
      *(N more uniques is a JSON drop; kit stows into pockets; shamblers pursue `identity` as well as `controlled`)*

**Open (10):**

- [ ] Generator: name, appearance, age, backstory, traits, skill bias, starting kit
- [ ] Small content pools — enough that generated people feel distinct
- [ ] Trait system with conflict rules
- [ ] Work priority grid with 4 jobs: **Haul, Construct, Cook, Doctor**
- [ ] NPC work AI: choose by priority, proximity, and capability
- [ ] Needs interrupt work, moderated by traits
- [ ] Injuries disable jobs the body can't do
- [ ] ~3 naturally recruitable survivors via director events
- [ ] **Focus + auto-allocation** — auto-spend web points and auto-maintain loadouts
- [ ] ⚠ **Risk checkpoint (roadmap risk 1):** run a seeded 6-survivor colony, all on auto. If that
      is not viable, the item and web systems need **shrinking** — not the UI improving. The seeded
      scenario prevents this checkpoint from inflating the slice's natural recruitment content.

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

**Done (3):**

- [x] Body parts with located conditions; **no health bar anywhere**
      *(ten survivor parts — head, torso, and a left/right of arms, hands, legs, feet — are saved
      and damaged independently; the condition snapshot exposes prose and state, never raw
      integrity. Sided as of the paperdoll revamp: docs/05 already promised "a one-armed
      survivor," which a single aggregate `arms` value couldn't produce. `SAVE_VERSION` bumped to
      13 for the schema change; see docs/30.)*
- [x] **The condition view** — a paperdoll of head / torso / arms / hands / legs / feet (each limb
      sided) with located conditions on the part they are on, spec:
      [docs/05](docs/05-health-injury.md#the-condition-view)
      *(a layout for the skill-scaled prose above, not a second representation of it. It shows what
      the **examiner** believes, so a bite presenting as a scratch presents as a scratch on the
      forearm — which is why it strengthens
      [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) rather than
      carving an exception to it.)*
- [x] Four descriptive states per part — unhurt / hurt / badly hurt / unusable — as **tint and prose**.
      **No fill, no percentage, no pips, and no tooltip carrying a number the screen doesn't show**

**Open (8):**

- [ ] Injury types: scratch, laceration, deep wound, bite, fracture, sprain, burn, concussion
- [ ] Continuous conditions: blood loss, pain, exhaustion
- [ ] **Bacterial infection kept distinct from zombie infection**, drawing on the same antibiotics
- [ ] Treatment steps: stop bleeding → clean → close → dress → rest, each timed and interruptible
- [ ] Supply quality tiers affecting infection risk
- [ ] **Skill-scaled diagnosis text** — what you see depends on who's looking
- [ ] Permanent conditions (limp, amputation) that don't remove a survivor from play
- [ ] Diegetic readouts for the continuous conditions and stamina — breathing, weapon sway, swing
      recovery, a limp, the screen edges closing in, blood on the ground
      *(the bodies to hang these on now exist — see the character models in Milestone 0's render
      section. Swing recovery and the crawl already read as poses; a limp is a walk cycle with one
      leg's stride shortened, which is a `BODY_SPECS` entry rather than new machinery.)*
      *(every one of these is already a specified mechanical consequence. The change is that the
      consequence **is** the readout — nothing is displayed twice, once as an effect and once as a
      meter.)*

### Infection — spec: [docs/06](docs/06-infection.md)

**Done (7):**

- [x] **Private transmitted flag** decided at wound time and never retroactively changed
      *(a named deterministic RNG stream decides it when the bite wound is created; it is saved but
      omitted from player-facing condition state)*
- [x] Transmission by vector, reduced by **armor coverage** (`armor:{part:0..1}` on content, max-coverage check at bite time)
- [x] Five-stage timeline Latent→Onset→Progression→Critical→Turned with CON-scaled `stage_duration_ticks` (12h/12–24h/24h/12h) — advancement is `>=` on `stageEnteredAtTick`, deterministic per tick
- [x] Observation model: `diagnosis_of(world, entity, skill)` never leaks `transmitted`; skill gates uncertainty vs. sepsis hint
- [x] The five responses: `cauterize`/`amputate`/`antibiotics.course`/`quarantine`/`put_down` verbs wired on `zombieInfection` with window guards
- [x] Turning — staged at Critical→Turned, emits `survivor.turned` + `noise.emitted 20`, despawns via `world.despawn` (components+modifiers cleared) and spawns one `shambler` after `health.reap`
- [x] `infection_progression` stat (`1.0` clamped `0.75–1.25`) + `world.despawn` fix + `world.step` `clear_record→drain` + armor schema/content

**Open (2):**

- [ ] **Early stages indistinguishable from sepsis** — shared wound presentation still needs bacterial `sepsis` condition drawing on same course stock
- [ ] ⚠ **Risk checkpoint (roadmap risk 2):** do players quarantine, or just execute? Universal
      execution means the investment curve is too shallow and permadeath has no teeth.

### Combat — spec: [docs/09](docs/09-combat.md)

**Done (5):**

- [x] Melee reach and swing arc read from the same facing
      *(which is what makes reach legible as a property, and what makes being surrounded lethal in the
      way [clause 1](docs/01-hardcore-contract.md#1-you-are-weak-permanently) promises)*
- [x] Ranged: raise → steady → fire → recover → reload, all interruptible
      *(`godot/sim/modules/ranged.gd`; `G` / left-click fire, `R` reload when inventory is closed;
      windup-style cancel on `!canAim`, stagger, grab)*
- [x] Accuracy as a **cone**, never a displayed hit chance
      *(tight while still, wide while moving; closest body in cone; no percent)*
- [x] Ammo consumption
      *(bow consumes `item.ammo.arrow`; pistol mag 8 then `item.ammo.9mm`; 70% arrow recover)*
- [x] Gunfire emits its full attention cost — **the parity contract must be live in the slice**
      *(bow 4, pistol 180 + flash 60; `noise.emitted` hits the kernel flood-fill)*

**Open (6):**
- [ ] **Aiming** — free aim against the [facing](docs/28-visibility-and-sightlines.md#what-an-observer-is)
      the visibility work already added, spec: [docs/09](docs/09-combat.md#aiming)
      *(the steady phase **is** holding the heading on something; being shoved or grabbed moves the
      muzzle rather than cancelling an abstract state)*
- [ ] **Weapon sway as the readout** — the cone drawn as the thing itself, not as a number about it.
      No reticle that reports its own accuracy
- [ ] You cannot aim at what you cannot see — firing at a remembered position is allowed, and costs
      the full 180 noise and 60 muzzle flash either way
- [ ] Steadiness degraded by movement, exhaustion, pain, injured arms
- [ ] Jamming on degraded weapons
- [ ] NPC combat from assigned posts, breaking off when critically injured

### Items — spec: [docs/10](docs/10-items.md)

**Done (4):**

- [x] 24 bases plus the alpha ranged pair: seven melee, bow + pistol + two ammo, five containers, nine supplies, three light sources
      *(bow 4-noise / pistol 180-noise + mag 8; 20 rounds in the military cache)*
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

- [ ] Shallow six-region web, ~12–18 nodes, touching Melee, Ranged, Medicine, Craft, Survival, and
      Endurance so every Focus has a valid path
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
- [ ] "Nothing Personal" internal baseline — director off for comparison, not a player-facing preset

### Death & succession — spec: [docs/01](docs/01-hardcore-contract.md#succession-what-happens-when-you-die)

**Open (6):**

- [ ] Permadeath for everyone, player included
- [ ] Succession: hand control to another survivor, save continues
- [ ] Skill web dies with the character
- [ ] **Corpse persists with all gear on it, where it fell**
- [ ] Colony morale hit; work priorities cleared
- [ ] Run ends only when the last survivor dies

### UI — spec: [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)

**Done (3):**

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
      *(now one compact survivor panel with **Equipment / Injuries** tabs. Equipment surrounds the
      shared posture-aware body with all seven real drop targets; Injuries keeps the same body and
      tint map, replaces slots with selectable regions, and wraps the selected region's diagnosis in
      a fixed details area. Container grids remain beside it and drag-to-equip still queues ordinary
      commands.)*
- [x] Pause and speed controls

**Open (5):**

- [ ] **No player-facing numbers that collapse uncertainty** — no health bars, hit chances, enemy
      counts, or damage text. Known aptitude values are a separate open UI decision in docs/23
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

**Deferred to Milestone 3+:** [weather](docs/16-weather.md) · the six bounded
[survivor attributes](docs/23-roadmap.md#planned-survivor-attributes) · the full
[decay clock](docs/13-world-decay.md) and mutation waves · every [zombie type](docs/14-zombies.md)
beyond the shambler · the full [skill web](docs/08-skill-web.md) · [named items](docs/10-items.md) and
[unique survivors](docs/07-survivors.md) · relationships and grief · temperature and hygiene · the
remaining [modification consumables](docs/11-crafting.md) · [factions](docs/18-factions.md) · the escape
endgame · the full sandbox and storyteller layer.

Attributes arrive only after their consumers: Guard/Scout work, relationships, and the full web. DEX
also requires distance-normalized footstep attention; CON applies injury tolerance to incoming damage
rather than adding mutable per-entity maxima; INT never grants retroactive progress or accelerates its
own node. CHA trade and WIS raider warnings wait for factions in Milestone 4. These are implementation
constraints from docs/23, not Milestone 2 tasks.

### Deferred engineering checkpoints

The first four items were open Milestone 1 tasks whose consumers are weather or vehicles. The rest are
the already-specified Milestone 3C multiplayer path. Kept here so an engineer can tell a deliberate
dependency from an oversight.

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

## Open design and playtest questions

[Docs/23 owns the canonical question register](docs/23-roadmap.md#open-questions), including current
attention, visibility, inventory, succession, attribute, world, and multiplayer questions. Do not copy
them back here: this file records engineering blockers beside the task they block, while docs/23 owns
questions answered by play and product judgment.

Two former questions are closed engineering facts: the district is 256 m, and continuous scent passed
its performance budget. Their measurements remain in the completed Milestone 1 sections above.

## Settled decisions: do not relitigate

These were each decided explicitly by the repo owner. If you're about to "improve" one, don't:

- **Hardcore is the thesis, not a difficulty slider.** Permadeath with succession into another
  survivor; no win condition plus an optional expensive escape.
- **No wave timer.** Horde pacing is attention-driven and director-paced.
- **Blank slates mean no classes or predetermined builds, not identical biology.** Every survivor
  eventually gets bounded, budgeted STR/DEX/CON/INT/CHA/WIS aptitudes. The build still lives primarily
  in found gear plus a classless skill web earned by doing, and the same rules apply to the controlled
  survivor and every recruit.
- **Survivors are unlimited and procedurally generated.** Recruits arrive as unskilled nobodies — that
  is the counterweight that keeps permadeath meaningful.
- **Melee and ranged both good**, spending non-convertible currencies (body/bite-risk vs.
  ammo/attention).
- **Fully drivable continuous region**, no abstracted travel legs. **Full nomad play viable.**
- **Performance is pillar 6**, with CI budget gates that fail the build.
- **Engine transition:** rebuild the current game in Godot behind parity gates while the
  TypeScript/Canvas/Vite version remains the executable oracle. The product roadmap is unchanged;
  Milestone 2 resumes at lethality after cutover. R0 is approved: typed GDScript on Godot 4.7.1,
  Compatibility, Web + Windows, `godot/` in this repository, and `/godot/` as the transition preview.
  **Saves may break pre-1.0** — stable IDs and a version stamp, but no cross-engine migration
  framework.
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
