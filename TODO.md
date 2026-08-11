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
day/night are the remainder** — and light turned out to be the small half of a larger job, so it now
sits inside [visibility & sightlines](docs/28-visibility-and-sightlines.md) below, where **the
primitive is now built**: the district occludes, the arcs work, and the renderer no longer draws
through walls. Light is what is left of that section, and it is the next thing to build. The
[ground](#the-ground--spec-docs24) landed alongside it — five surfaces, trees, and one pace
multiplier — so a route is now a decision about the attention field in the same way a stance is.

Run it with `npm run dev` — `WASD` move, `Shift` sprint, **`Space` shout**, **`O` cycles the
attention overlay** through noise, scent and sight.
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
      *(`src/ui` was the exception until the grid inventory arrived early — `src/ui/inventory.ts`
      is the first screen in the game. See the Milestone 2 entry below.)*
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
      *(moved into [visibility & sightlines](#visibility--sightlines--spec-docs28) below. Light is
      the same shadowcast the renderer and the multiplayer view filter need, and building it three
      times is how they end up disagreeing.)*
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

### Visibility & sightlines — spec: [docs/28](docs/28-visibility-and-sightlines.md)

**The renderer currently draws every entity in the viewport, walls or not.** That is a wallhack in
the shipped single-player build, not a multiplayer worry, and it is why this section exists at all.

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
- [ ] **Light channel on top of the primitive** — shadowcast from emitters at
      [the magnitudes already tabled](docs/03-attention.md#light), range in the same metres
      *(the primitive is built and this is the next thing to build on it. Note that
      `Observer.rangeMetres` is a daylight constant today precisely because there is no light to
      derive it from — when this lands, that field becomes a lookup and nothing else changes.)*
- [ ] Zombies read light as a line-of-sight pull; the
      [sensory profile's](docs/14-zombies.md#sensory-profiles) Light column goes live for the first time
      *(`SHAMBLER_EYES` exists and `boot({ observers })` hands it out, so the cost is already
      measured. Nothing in the game gives a zombie eyes yet, deliberately: docs/14's first design
      rule is that sight must not make them tactical, and the safe way to honour it is to land sight
      and its one new stimulus together rather than sight first.)*
- [x] **Renderer occlusion** — entities are drawn only where the survivor could see them
      *(11 bodies drawn where 216 were in the viewport, at 2,000 entities. The renderer asks
      `world.vision` rather than computing a cheaper check of its own — docs/28's design rule, and
      the reason it gives is that the place two line-of-sight checks disagree is where the exploit
      lives.)*
- [ ] **Last-known position memory**, degrading descriptively
      *(bodies that vanish at a wall edge read as a bug; bodies you lose track of read as the game.
      And a marker that follows an unseen body is a lie, which
      [the fairness rules](docs/01-hardcore-contract.md#fairness-rules) forbid outright.
      **Half done:** the renderer fades a mark where a body was last seen, and it stays put rather
      than tracking. The simulation half — per-observer memory, in skill-scaled prose that degrades
      from "a moment ago" to "a while ago" — is not built, and belongs with the
      [condition view](docs/05-health-injury.md#the-condition-view).)*
- [x] Benchmark scenario held at **the same budget as its sightless twin**
      *(⚠ this is the first cost in the project that does not amortise across the horde — one
      shadowcast per changed observer, and per client on top of that in multiplayer. See
      [the cost shape](docs/22-performance.md#visibility-is-a-different-cost-shape). Tiering is the
      mitigation: a distant zombie needs the gradient it is climbing, not a sightline.
      **`crowded-and-watched` measured 1.34 ms against `crowded`'s 1.32 at the same 4 ms budget** —
      which is a measurement of how rarely a shadowcast runs, not of one being cheap. A single 12 m
      cast is 0.07 ms and a 48 m one 0.18 ms. Still unmeasured, and the thing to measure next:
      observers that **sprint**, which pay every three ticks rather than every forty.)*

### The ground — spec: [docs/24](docs/24-world-and-scale.md#the-ground)

**The surface a body stands on decides how fast it moves and how loud it is.** docs/24 committed to
both halves of this in its Roads section long before there was an array to hold it — "off-road is
slow", "streets are noise highways" — so this is that promise made mechanical rather than a new idea.

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
- [ ] Surfaces in content JSON rather than a table in `surface.ts`
      *(five surfaces × two numbers is small enough to read at a glance today. It stops being small
      the moment weather makes them wet — see below.)*
- [ ] **Wet ground** when [weather](docs/16-weather.md) arrives — rain quiets a hard surface and
      turns dirt to mud
      *(the obvious next thing the layer is for, and the reason it is two numbers per surface rather
      than two constants in the movement system)*
- [ ] Vehicles read the same layer — "off-road is slow, damaging, and impassable for most
      [mobile bases](docs/26-mobile-bases.md)" is the other half of the Roads promise, and it waits
      on vehicles

### Spatial partitioning — spec: [docs/22](docs/22-performance.md#spatial-partitioning)

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
- [ ] Emitters and render culling read the same index
      *(both still do their own thing — the emitter walk is per-entity and culling is a viewport
      rectangle. Neither is hurting yet, and moving them is a change with no measurement behind
      it until one of them is.)*

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
- [x] **Damage model: head and locomotion are what matter; a crawler is still lethal**
      *(three pools rather than one, from `content/zombies/base.json`'s `body` block, which had
      been sitting there read by nothing. A head is instant, a torso never kills however much of
      it is destroyed, and legs at zero leave a quarter of a shamble — slow enough to walk away
      from, far too fast to ignore at arm's length. It draws at half size, because docs/14 says a
      crawler "is easy to miss in a dark breach" and that has to mean less visible rather than
      merely slower. **Damage never interrupts the state machine**; only stagger does, per
      docs/14's "stagger from mass, never flinch from injury".)*

### The player survivor — spec: [docs/09](docs/09-combat.md)

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
- [ ] **Movement stances** — crawl / crouch / walk / jog / sprint, spec:
      [docs/29](docs/29-movement-and-stances.md)
      *(walk and sprint emit 1 and 6, and **those magnitudes are calibrated and do not move** — the
      speeds themselves now scale with `PACE` above. The three new registers are picked to sit
      against them, the way whisper and talk were picked against shout.)*
- [ ] Each stance carries its own speed, noise magnitude, and stamina behaviour — **faster is louder**,
      which is the whole reason this is a system and not two constants
- [ ] Stance changes are [timed and interruptible](docs/01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die);
      no aiming from a sprint, no swinging from a crawl
- [ ] Speed modifiers go through the
      [modifier pipeline](docs/21-extensibility.md#mechanism-2-the-modifier-pipeline) with named
      sources — legs, feet, pain, exhaustion, encumbrance, limp
      *(so "why am I this slow?" is answerable from the introspection that already exists, which is
      what [every death is explicable](docs/01-hardcore-contract.md#fairness-rules) obliges)*
- [ ] Crouch and crawl interact with the **low** occluder class, in both directions — cover that hides
      you also blinds you
- [ ] Fold the shambler's three hardcoded speeds (seek, wander ×0.35, mill ×0.25) into the same model
      *(so a [zombie type's](docs/14-zombies.md#content-shape) speeds are fields in its JSON entry
      rather than constants in a module)*
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
- [ ] **Grabs, and breaking free** — and with them, bite risk
      *(the one part of docs/09's melee model still missing, and the reason **the parity contract
      is not yet satisfied**: with no bite risk, melee's only cost is stamina. Both need a survivor
      who can be injured and infected — an injury model and the infection module, neither of which
      exists. The `entity.staggered` subscription that interrupts a wind-up is the seam this plugs
      into, and it is already there because the rule is symmetrical.)*
- [x] Reach as a distinct property from damage
      *(pinned by a test rather than asserted in prose: the spear out-reaches the bat while doing
      **less** damage, so reach cannot collapse into a damage stat, and the bat staggers four times
      as long as the spear, which is the survival property rather than the killing one. Reach is
      centre-to-centre plus the target's half-width, or a weapon quietly loses 0.35 m of what its
      profile claims.)*

### Time — spec: [docs/02](docs/02-core-loop.md)

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
- [ ] **Night should be darker than this.** `NIGHT_AMBIENT` is 0.25 because there is no light
      channel — nothing to carry, nothing to light, no counterplay. When emitters land, this
      number goes down.
- [ ] Nights vary: the [director](docs/17-director.md) decides what tonight is
      *(docs/02's night-type table. Needs the director, which is Milestone 2.)*
- [ ] Longer nights in winter *(needs [weather](docs/16-weather.md)'s seasons)*

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
> The milestone is **not closed**: light is still open above, the night is still too soft
> without it, and so are grabs — the half of melee that makes its cost more than stamina, and
> the reason [docs/09's parity contract](docs/09-combat.md#the-parity-contract) is not yet
> satisfied. The swing loop itself is closed. Scent and both of its ⚠ checkpoints are now
> closed. What is closed is the question of whether the field reads as a
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
- [ ] Attachment slots on 2 base classes, with attachments movable between compatible bases
      *(the slots are declared in content already; nothing reads them yet)*
- [ ] Armor as **coverage per body part**, reducing bite transmission rather than granting tankiness
- [~] Condition degradation affecting performance continuously
      *(the curve is built and read -- damage and swing speed both scale with wear -- but nothing
      degrades yet, because wear is driven by use and the systems that use things publish the
      events it will subscribe to)*
- [ ] Repair that **never restores the full ceiling**
      *(`Condition` already carries the ceiling, so repair is a system rather than a data change)*
- [x] Carry weight and encumbrance
      *(recursive over nested containers, emitted as `move_speed` and `stamina_recovery`
      modifiers, and **never shown as a number** -- see the grid, below)*

### The grid inventory — spec: [docs/10](docs/10-items.md#inventory-space-and-weight)

Tarkov/DayZ-shaped, and it is [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)
being *satisfied* rather than merely survived: a capacity bar is a number about your capacity, and a
grid is the same information as shape. You do not read that the pack is nearly full, you see that the
axe will not fit.

- [x] Placement primitive: footprints, rotation, bounds, overlap, a declared free-slot scan order
- [x] Containers as entities, so a pack is an item with a grid and pockets are a grid with no item
- [x] Nesting to depth 3, with cycle and depth guards *(both mutation-tested)*
- [x] Stacking, splitting and merging, with the per-base limit respected
- [x] Equipped containers granting their grid — **what you can carry is what you chose to wear**
- [x] Ground items, pickup within arm's reach, and drop
- [x] Every rearrangement as a `Command`, so drags land on a tick and enter the replay record
- [x] Save/load of a nested loadout, and determinism across a scripted drag sequence
- [ ] Searching a container in the world (a car boot, a cupboard) rather than only carried ones
- [ ] Weight affecting the *sound* of a footstep — the obvious link into
      [the attention field](docs/03-attention.md) that nothing has drawn yet

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
      *(unchanged, and the two items below are not exceptions to it. A paperdoll of located conditions
      answers "what is wrong and where"; a bar answers "how much is left". Only the second one is
      prohibited, and it is prohibited for stamina too.)*
- [ ] The [condition view](docs/05-health-injury.md#the-condition-view) screen — the paperdoll above,
      rendered
- [ ] The diegetic condition and stamina readouts — in the world and on the survivor, not in a corner
- [ ] Prose condition descriptions **generated from modifier sources** ("cold, tired, and that arm
      isn't right")
- [ ] Priority grid UI
- [x] Inventory and equipment UI — `src/ui/inventory.ts`, the first screen in the game
      *(drag to move, right-click or `R` to rotate, drag onto a slot to wear, drag out to drop. It
      reads a snapshot rather than the world, and every gesture is a command -- so it cannot write
      to `sim/` and cannot reach a state the simulation would have refused.)*
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

**Also Milestone 3, and independent of that chain —**
[multiplayer](docs/27-multiplayer.md), specified and deliberately unbuilt:

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

**Deferred and now written down rather than merely absent — [z-levels](docs/23-roadmap.md#deferred-z-levels).**
Multi-floor buildings, stairs, rooftops you stand on. Not designed, deliberately: the map is a flat
`Uint8Array`, the field is one 64 × 64 grid, noise and scent both propagate across one plane, and the
renderer has no floor concept. Z-levels add a dimension to all four at once, and the field is the
expensive one. The tactical value the docs actually reference — watch platforms, *"doors, elevation,
chokepoints"* — is mostly reachable through
[doc 28's occluder classes](docs/28-visibility-and-sightlines.md#what-blocks-sight) with no second
floor existing, and [docs/15 already cuts](docs/15-base-building.md#cut-list) free-form multi-story
player construction on its own reasoning. Revisit after
[world scale](docs/24-world-and-scale.md), with a spike against the field cost first.

**On the zombie roster, since PVP raises the question.** The
[types](docs/14-zombies.md#types) are content, not code — one JSON entry each — but three of them are
not: the **screamer** and **runner** need
[sight](docs/28-visibility-and-sightlines.md#what-the-zombies-see), the **heavy** needs structure
damage, and the **bloater** needs a death effect on the scent channel. The roster is cheap; those
three behaviours are the actual work, and the first of them is now a Milestone 1 item.
**[Raiders and bandits](docs/18-factions.md) stay post-slice** — what PVP un-defers is
human-vs-human *resolution*, not raider approach AI.

**Cut from the design entirely** (see the [vision's cut list](docs/00-vision.md#cut-list)):
a cure or narrative resolution · aircraft and boats · [respec](docs/08-skill-web.md) · a tech tree ·
player-visible infection percentages · save migrations before 1.0.

*Multiplayer left this list.* It was cut at the vision level and is now
[reversed and specified](docs/27-multiplayer.md) — see the Milestone 3 entry above. Colony-vs-colony
raiding is **deferred rather than reversed**: there is no colony to raid until Milestone 2.
