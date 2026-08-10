# TODO

The executable backlog for [simplyZOMBIES](README.md), covering Milestones 0 through 2 — everything
needed to reach a playable vertical slice.

Milestones 3 and 4 stay as prose in [docs/23-roadmap.md](docs/23-roadmap.md) on purpose. The slice
exists to find out whether the core idea is fun, and most of what lies beyond it is guesswork the
slice will invalidate.

## How to use this

- Each section names the design document that specifies it. **If a task and its doc disagree, the doc
  is wrong** — update it in the same commit rather than letting them drift.
- ⚠ **Risk checkpoints** mark tasks whose *result* decides whether the plan changes. They come from
  [the roadmap's risk list](docs/23-roadmap.md#risks). Don't quietly pass one — if a checkpoint fails,
  that's the signal to stop and redesign.
- Milestones close on their exit criterion, not on the checkbox count.

**Current milestone: 1 — The spine.** Milestone 0 is complete. Two of the three attention channels
are in — the **noise spine** (field, gradient ascent, a shout) and now **scent** (continuous
diffusion, wind, field memory). Both ⚠ checkpoints that were riding on scent are closed. The
[exit criterion](#milestone-1--the-spine) is met for noise and asserted in CI. **Light, melee and
day/night are the remainder.**

Run it with `npm run dev` — `WASD` move, `Shift` sprint, **`Space` shout**, **`O` cycles the
attention overlay** through noise and scent.
`npm test` is correctness; `npm run bench` and `npm run bench:frame` are the budgets, and they fail
the build.

---

# Milestone 0 — Foundations

The architecture with no game on top. Deliberately minimal — the goal is the *minimum* ECS, not a good
one ([roadmap risk 4](docs/23-roadmap.md#risks)).

### Project setup — spec: [docs/19](docs/19-architecture.md)

- [x] Vite + TypeScript scaffold, `strict` on
- [x] Vitest configured, running headless
- [x] Directory layout per [the repository layout](docs/19-architecture.md#repository-layout):
      `src/sim/{kernel,modules,rng}`, `src/render`, `src/platform`, `src/ui`, `content/`, `test/`
      *(`src/ui` is the exception — there is no UI yet, and an empty directory is not a layout. It
      arrives with the first screen in Milestone 2.)*
- [x] ESLint rules enforcing **`sim/` purity** — ban DOM globals, `Math.random`, `Date.now`, and
      imports from `render/`, `platform/`, and `ui/`
      *(plus `tsconfig.sim.json`, which compiles `sim/` with no DOM lib so DOM access is a type error
      rather than only a lint error)*
- [x] Prettier / formatting config

### Kernel — spec: [docs/19](docs/19-architecture.md), [docs/20](docs/20-ecs-and-content.md)

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

- [x] JSON Schema definitions per content type
      *(`zombie` and `affix` — the two docs/20 writes out. Others get a schema the day their system
      exists; a guessed schema is worse than none because it looks authoritative.)*
- [x] Registry that walks content **directories** (not a fixed file list — this is what makes it
      mod-ready later)
      *(walking is in `platform/`, since `sim/` has no file system; the registry itself stays pure)*
- [x] `extends` resolution
- [x] Load-time validation: every ID unique, every reference resolves, every modifier `stat` exists,
      every behavior tag implemented, no circular `extends`
- [x] Errors name the file, the entry, and the field — **fail loudly at load, never silently at hour
      thirty**
      *(every problem reported in one pass, and nothing is published unless all of it validated)*
- [ ] Hot reload in dev
      *(needs a dev server for `src/`; `vite.spike.config.ts` only serves the spike. Lands with the
      renderer.)*

### Platform & render — spec: [docs/19](docs/19-architecture.md#layers)

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

### Tests & CI

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

> **Exit criterion:** an entity moves around a tile map, deterministically, and the same seed plus
> inputs reproduces it byte-identically.
>
> ✅ **Met.** Asserted directly in `test/integration/exit-criterion.test.ts`, against the shipped boot
> path rather than a fixture — including the negative controls that make it capable of failing: a
> different seed diverges, and so does a different input log on the same seed.

---

# Milestone 1 — The spine

The [attention field](docs/03-attention.md) and something that reacts to it. This is the first point at
which the project is legible as a game.

### The attention field — spec: [docs/03](docs/03-attention.md)

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
- [ ] **Light** — shadowcasting from emitters, recomputed only on emitter or occluder change
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
- [ ] Dirty-region tracking
      *(still not earned, and now measured rather than assumed. Scent made the field continuous, which
      was the condition this was waiting on — and the continuous step costs 0.0075 ms amortised per
      tick, the same whether the district is saturated or fresh. Revisit if a third channel or a
      larger grid changes the arithmetic.)*
- [ ] Per-tick propagation budget with a deterministic overflow queue (degrade the field's update rate,
      never the frame)
- [x] Field is part of the save state
      *(sparse — live cells only, so a quiet save costs nothing and a loud one is bounded. Note
      `canonicalize` rejects negative zero, which a decaying float reaches: values under the floor
      snap to a hard 0.)*
- [x] Debug overlay visualizing the noise channel *(developer-only, `O` to toggle, off by default —
      see the [information rule](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable).
      Grows the other two channels when they exist.)*

### Spatial partitioning — spec: [docs/22](docs/22-performance.md#spatial-partitioning)

- [ ] Uniform spatial hash over entity positions
- [ ] Neighbor queries for combat, emitters, and render culling
      *(deferred to the melee work below, deliberately. Gradient ascent needs no neighbour queries —
      that is why the spike measured the angular bias at zero cost — and render culling already
      exists. Building it before combat needs it would be optimising an absence.)*

### Zombies — spec: [docs/14](docs/14-zombies.md)

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
- [ ] Pursue on direct contact
- [ ] Damage model: head and locomotion are what matter; a crawler is still lethal

### The player survivor — spec: [docs/09](docs/09-combat.md)

- [x] Direct movement control of one entity
      *(landed in Milestone 0; it now emits into the field — walking 1, sprinting 6, shouting 120)*
- [ ] Melee loop: wind-up → connect/miss → recovery, all interruptible
- [ ] Stamina cost per swing, scaled by weapon weight
- [ ] Stagger on solid connect
- [ ] Grabs, and breaking free
- [ ] Reach as a distinct property from damage

### Time — spec: [docs/02](docs/02-core-loop.md)

- [ ] Day/night cycle with the four phases
- [ ] Phase transitions publish `phase.changed`, `night.fell`, `day.started`
- [ ] Speed controls: pause, 1×, 3×, 10×, with 10× auto-dropping on threat contact

### Performance

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

> **Exit criterion:** make noise, and they come. Go quiet, and they don't.
>
> ✅ **Met for noise**, asserted in `test/integration/attention.test.ts` against the shipped boot path,
> with the negative control that makes it capable of failing: the same seed and the same 1,200 ticks
> *without* a shout leaves the horde where it was. Measured, a shout takes the crowd within 50 m from
> 30 bodies to 92.
>
> The milestone is **not closed**: light, melee and day/night are still open above. Scent and both of
> its ⚠ checkpoints are now closed. What is closed is the question of whether the field reads as a
> game.
>
> Scent adds a second, slower answer to the same criterion, and it is the one that makes *going*
> quiet interesting rather than merely safe. **Make noise and they come in a minute. Make none, and
> they still come — in an hour.** Standing perfectly still with the noise field at literally zero
> live cells, the crowd within 50 m goes from 30 bodies to 76 over an hour, purely on the scent a
> body cannot stop emitting. The one-minute negative control above is untouched by this, and that is
> the design rather than a coincidence: a 90 minute half-life builds almost no gradient in 60 seconds.

---

# Milestone 2 — The vertical slice

Everything needed to test the thesis, and nothing else:

> *A player managing the attention field — trading comfort for safety, day after day, with people
> they've invested in and can permanently lose — is doing something fun.*

### World & map — spec: [docs/12](docs/12-resources.md)

- [ ] One hand-authored map: a small district with a defensible building
- [ ] ~15 resource types
- [ ] 3 location loot tables (residential, commercial, medical)
- [ ] Site depletion — cleared is cleared
- [ ] Food spoilage *(the only [decay track](docs/13-world-decay.md) in the slice)*

### Survivors — spec: [docs/07](docs/07-survivors.md)

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

- [ ] Hunger, thirst, rest, mood *(temperature and hygiene deferred)*
- [ ] Mood as summed modifiers with named sources
- [ ] Mood consequences: slower work, more mistakes, refusing jobs, arguments
- [ ] Injured survivors consume without producing

### Health & injury — spec: [docs/05](docs/05-health-injury.md)

**Ships complete, not stubbed — this is the hardcore thesis.**

- [ ] Body parts with located conditions; **no health bar anywhere**
- [ ] Injury types: scratch, laceration, deep wound, bite, fracture, sprain, burn, concussion
- [ ] Continuous conditions: blood loss, pain, exhaustion
- [ ] **Bacterial infection kept distinct from zombie infection**, drawing on the same antibiotics
- [ ] Treatment steps: stop bleeding → clean → close → dress → rest, each timed and interruptible
- [ ] Supply quality tiers affecting infection risk
- [ ] **Skill-scaled diagnosis text** — what you see depends on who's looking
- [ ] Permanent conditions (limp, amputation) that don't remove a survivor from play

### Infection — spec: [docs/06](docs/06-infection.md)

**Also ships complete.**

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

- [ ] Ranged: raise → steady → fire → recover → reload, all interruptible
- [ ] Accuracy as a **cone**, never a displayed hit chance
- [ ] Steadiness degraded by movement, exhaustion, pain, injured arms
- [ ] Jamming on degraded weapons
- [ ] Ammo consumption
- [ ] Gunfire emits its full attention cost — **the parity contract must be live in the slice**
- [ ] NPC combat from assigned posts, breaking off when critically injured

### Items — spec: [docs/10](docs/10-items.md)

- [ ] ~12 bases split across melee and ranged
- [ ] ~10 affixes with tiered values, including double-edged ones
- [ ] 3 tiers: Scavenged, Modified, Field-Tested
- [ ] Attachment slots on 2 base classes, with attachments movable between compatible bases
- [ ] Armor as **coverage per body part**, reducing bite transmission rather than granting tankiness
- [ ] Condition degradation affecting performance continuously
- [ ] Repair that **never restores the full ceiling**
- [ ] Carry weight and encumbrance

### Modification — spec: [docs/11](docs/11-crafting.md)

- [ ] **Duct Tape** — reroll one random affix
- [ ] **Scrap Kit** — add an affix to a free slot
- [ ] Skill- and trait-weighted outcomes; injured hands make it worse
- [ ] Failure consuming the consumable and damaging condition

### Skill web — spec: [docs/08](docs/08-skill-web.md)

- [ ] Stub web: one melee branch, one ranged branch, ~12 nodes
- [ ] **Region-tagged points earned by doing** — you cannot grind a build you aren't living
- [ ] Node effects expressed as modifiers, in content
- [ ] Auto-allocation paths per Focus, stopping short of keystones

### Building — spec: [docs/15](docs/15-base-building.md)

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

- [ ] Colony power and strain estimation
- [ ] Pressure, composition, and migration levers *(it adjusts pressure; it never spawns at your gate)*
- [ ] **Guaranteed lulls** after costly nights
- [ ] Week-one grace period
- [ ] Variance floor and ceiling
- [ ] Event seeding gated on colony state
- [ ] "Nothing Personal" preset — director off, as a balance baseline

### Death & succession — spec: [docs/01](docs/01-hardcore-contract.md#succession-what-happens-when-you-die)

- [ ] Permadeath for everyone, player included
- [ ] Succession: hand control to another survivor, save continues
- [ ] Skill web dies with the character
- [ ] **Corpse persists with all gear on it, where it fell**
- [ ] Colony morale hit; work priorities cleared
- [ ] Run ends only when the last survivor dies

### UI — spec: [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)

- [ ] **No numbers anywhere player-facing** — no health bars, no hit chances, no enemy counts, no
      damage text
- [ ] Prose condition descriptions **generated from modifier sources** ("cold, tired, and that arm
      isn't right")
- [ ] Priority grid UI
- [ ] Inventory and equipment UI
- [ ] Skill web UI
- [ ] Pause and speed controls

### Balance harness — spec: [docs/19](docs/19-architecture.md#testing-strategy)

- [ ] Headless multi-run harness — thousands of colonies across seeds
- [ ] Distribution assertions: quiet nights, sieges, deaths, run lengths
- [ ] ⚠ **Risk checkpoint (roadmap risk 6):** measure whether melee-only and ranged-only colonies
      survive comparably. Elegant-on-paper parity usually collapses in playtesting — this is how we
      find out without arguing about it.

> **Exit criterion:** a player survives ten in-game days, loses someone they cared about, and wants to
> start again.

---

# Not in the slice

Restated here because the TODO is where scope creep actually happens. All of this is designed and
deliberately deferred — see each document's cut list.

**Deferred to Milestone 3+:** [weather](docs/16-weather.md) · the full
[decay clock](docs/13-world-decay.md) and mutation waves · every
[zombie type](docs/14-zombies.md) beyond the shambler · the full [skill web](docs/08-skill-web.md) ·
[named items](docs/10-items.md) and [unique survivors](docs/07-survivors.md) · relationships and grief ·
temperature and hygiene · the remaining [modification consumables](docs/11-crafting.md) ·
[factions](docs/18-factions.md) · the escape endgame · the full sandbox and storyteller layer.

**Also Milestone 3, in this strict order** — each depends on the one before, per the
[roadmap](docs/23-roadmap.md):

1. [World scale](docs/24-world-and-scale.md) — the continuous region, districts, the road graph,
   district-tier simulation, streaming
2. **The drive benchmark** against synthetic load, *before any vehicle exists* — it decides whether the
   continuous region was affordable, and finding out late is the expensive way
3. [Vehicles](docs/25-vehicles.md) — bases, slots, affixes, driving, fuel, breakdowns, route trails
4. [Mobile bases](docs/26-mobile-bases.md) — interior modules, convoys, relocation, nomad play

**Cut from the design entirely** (see the [vision's cut list](docs/00-vision.md#cut-list)):
multiplayer · a cure or narrative resolution · aircraft and boats ·
[respec](docs/08-skill-web.md) · a tech tree · player-visible infection percentages · save migrations
before 1.0.
