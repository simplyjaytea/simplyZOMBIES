# 22 — Performance

*Why this exists: the design calls for hordes, a continuously-propagating [attention
field](03-attention.md), a colony of individually-simulated people, and a
[continuous drivable region](24-world-and-scale.md) — in a browser. That works only if the cost of
distant, irrelevant simulation is near zero, and only if performance is treated as a design constraint
rather than a cleanup task.*

---

## Performance is a pillar

Per [pillar 6](00-vision.md#the-six-pillars), this document is not advisory. The budgets below are
enforced:

> **A feature that breaks budget does not ship until it is fixed.**

The mechanism is CI. Benchmark scenarios run as fixed seeds against asserted budgets, and exceeding one
**fails the build** — the same severity as a failing test. This is a real commitment: it means
sometimes stopping feature work to fix a regression, which is exactly the intent. The alternative is
discovering in month nine that the design is not achievable, having built all of it.

**Enforcement status, 2026-10-03:** the paragraph above is the product requirement, not a claim
that the shipped engine already satisfies it. CI's `bench` and `bench:frame` still measure the
frozen TypeScript oracle. The older `godot:bench` times a synthetic attention/spatial dictionary
and exits zero on overruns; it does not prove the playable Godot world's budget. The new
`godot:bench:runtime` and `godot:bench:frame` commands measure shipped consumers and **exit one**
on overruns or invalid measurements. The existing product exceeds the unchanged targets, so
CI currently runs their deterministic exit/fixture contract (`check:runtime-budget`), not the
real timing commands. Making the actual Godot runtime budgets a green CI shipping gate remains
open. See [the shipped-runtime measurements](#shipped-godot-runtime-measurements).

## Targets

| Metric | Target |
|---|---|
| Frame rate | 60 fps at 1× and 3×; ≥30 fps at 10× |
| Entities, total | ~3,000 |
| Entities, detailed simulation | ~300 (near the player and the base) |
| Survivors | ~20 individually simulated at full fidelity |
| Sim tick | Fixed 20 Hz, decoupled from render |
| Tick budget | ≤8 ms average, ≤16 ms worst case |
| **Draw budget** | **≤10 ms average per frame at 1,000 visible entities** |
| **Sim share of frame** | **≤25% of frame time at horde scale** — if the tick is the majority of a frame, something regressed badly |
| Save write | <100 ms (frequent, per the [hardcore contract](01-hardcore-contract.md)) |
| **Chunk stream-in** | **≤4 ms per frame, amortized. Never stalls a frame.** |
| **Sustained driving speed** | **60 km/h through a loaded district without dropping below 60 fps** |

### Aim the budgets at the renderer

The last two rows are new, and they exist because the
[spike](23-roadmap.md#spike-findings-attention-field) measured the opposite of what this document
originally assumed. At 1,560 zombies: **~0.13 ms of simulation against ~3.7 ms of drawing.** The tick
was two orders of magnitude inside its 8 ms budget while the frame was ~30× more expensive than the
tick that fed it.

That does not mean the simulation budgets are wrong — they are what stops a bad system landing. It
means **a budget only on the tick would have caught nothing**, because the tick was never the problem.
Every scenario below asserts frame time as well as tick time for that reason.

The caveat worth carrying: the spike had no combat, no grabs, no per-part damage, no scent diffusion,
and one channel instead of three. Simulation cost will rise. Drawing 1,000 sprites will not get
cheaper on its own.

## The core idea: tiered simulation

Most zombies, most of the time, are far away and doing nothing interesting. Simulating them precisely
is wasted work.

| Tier | Where | What runs | Rate |
|---|---|---|---|
| **Detailed** | Near the player or the base | Full ECS: pathing, combat, grabs, per-part damage | Every tick |
| **Coarse** | Rest of the loaded district | Position, gradient following, aggregate health | Every 4th tick |
| **Abstract** | Neighboring districts | **Hordes as single entities**: a position, a bearing, a count, a composition | Every 20th tick |
| **District** | Everywhere else in the [region](24-world-and-scale.md) | **No entities at all** — a population number, a depletion state, a faction presence, a threat level | On visit |

Entities promote and demote between tiers as the player and the field move. The promotion boundary sits
outside perception range in every direction, so a horde always resolves into individuals *before* it's
observable — the player never sees a crowd pop into existence.

**Abstract-tier hordes are why the design can afford large sieges.** A 400-zombie horde crossing the
map is one entity with a count until it's close enough to matter.

**District tier is why the design can afford a continuous region.** A district you haven't visited in
three weeks is six numbers. It resolves into a populated world deterministically from the seed when you
drive into it, so it's the same world every time.

### Determinism constraint

Tier transitions must be deterministic ([architecture](19-architecture.md)). A promoting horde
distributes its aggregate state to individuals via the seeded RNG, so the same seed produces the same
individuals every time. Tiering is an optimization, never a source of variance.

## The attention field

The most continuously expensive system, since it runs everywhere all the time.

**Coarse grid.** The field is stored well below tile resolution — attention is a smooth gradient and
doesn't need per-tile precision. This is the single largest cost saving available.

| Channel | Update strategy |
|---|---|
| **Noise** | Event-driven only. Nothing propagates unless something emitted. Attenuated flood-fill, bounded radius by magnitude. |
| **[Light](28-visibility-and-sightlines.md)** | Recomputed only when an emitter changes state or an occluder moves. Static most of the time. |
| **Scent** | The only continuously-updating channel. Diffusion at a low rate — a few Hz, not every tick. |

**Dirty-region tracking**: only cells that changed, plus their propagation neighborhoods, are
recomputed. A quiet base at night costs almost nothing — the spike measured **six live field cells**
at rest, which is the strongest evidence the event-driven design for noise is right.

**The cost of a loud event is bounded and known.** At the
[calibrated scale](03-attention.md#scale-and-calibration) — 4 m cells, 0.7 attenuation per metre — an
unsuppressed gunshot floods a 257 m radius, touching roughly **13,000 cells**. The spike measured
1,112 cells as free, so the worst routine case is ~12× that and still cheap. This is the number the
benchmark suite asserts against; if a propagation change makes a gunshot cost materially more than
this, it broke the bounded-radius property.

**Budgeting**: propagation work has a per-tick ceiling. Excess queues to the next tick. Under extreme
load the field updates slightly slower rather than the frame dropping — degradation is graceful and
deterministic (the queue is ordered).

### Visibility is a different cost shape

Worth stating before it is built, because every budget in this document assumes something that
[visibility](28-visibility-and-sightlines.md) breaks.

The field amortises across everybody. One flood-fill answers a gunshot whether thirty bodies are
listening or two thousand, and scent diffusion
[costs the same saturated as fresh](#the-attention-field) because it scans the grid rather than the
live cells. That is why the horde got cheaper per body as it grew.

**Per-observer visibility does not amortise.** It is one shadowcast per observer whose position,
facing, or surroundings changed, and in [multiplayer](27-multiplayer.md#the-filtered-view) it is per
observer *per client* — the same shape as [risk 10](23-roadmap.md#risks), arriving before the
networking does. Two mitigations are already implied by the design and should be built in from the
start rather than retrofitted:

- **Recompute on change, not on tick.** A survivor standing still in an unchanged room is free. The
  Light row above already makes this claim for emitters; observers inherit it.
- **Tiering applies.** Per [the tiers above](#the-core-idea-tiered-simulation), a distant zombie does
  not need a sightline — it needs the gradient it is already climbing. Full visibility is a near-tier
  cost, and the entities that most need it are the handful of survivors on screen.

It earns a benchmark scenario of its own, held against the budget of its sightless twin.

**Built, and measured.** `crowded-and-watched` is `crowded` with fifty shamblers given eyes on top
of the survivor's, held at the same 4 ms budget, and it lands within noise of its twin — 1.34 ms
against 1.32. That number is not a claim about shadowcasting being cheap; a single 12 m shadowcast
costs 0.07 ms and a 48 m one 0.18 ms, which at 20 Hz would be ruinous if it ran per observer per
tick. It is a measurement of **how rarely one runs**: 690 of them across 600 ticks with 51
observers, because a drifting body crosses a tile about every two seconds.

So the budget is really guarding the cache, and the failure mode it will catch is somebody folding
facing into the cache key. What it does *not* cover, and what a future session should measure before
trusting the shape: observers that move fast. A sprinting survivor crosses a tile every three ticks
and pays the full cost every three ticks, and a horde of two thousand *seeking* observers would be a
different scenario than this one.

## Spatial partitioning

A uniform spatial hash over entity positions, serving:

- Neighbor queries for combat, grabs, and crowd formation
- Attention emitter/receiver lookups
- Tier assignment
- Render culling

Uniform hashing beats a quadtree here because entity distribution is clustered and dynamic, and the
constant factors are better at these counts.

## Pathfinding

Naive per-zombie A* at these numbers is the obvious way to die.

1. **Most zombies don't pathfind at all.** They perform gradient ascent on the attention field, which
   is a local lookup — cheap and, importantly, exactly the behavior the design wants
   ([zombies](14-zombies.md)).
2. **Flow fields** for the common case: one field per major attractor, shared by every zombie heading
   there. Computed once, read by hundreds.
3. **A\* only for detailed-tier entities** that need real navigation — survivors going to a job,
   raiders picking an approach.
4. **Hierarchical navigation** between zones for long-distance travel; fine pathing only within the
   current zone.

Flow fields carry the horde, which is precisely where the entity count is.

## Map streaming

The world is chunked. Chunks near the player are loaded and simulated; distant chunks hold summary
state (what's been [depleted](12-resources.md), what structures exist, roughly what's there) and
simulate abstractly.

Chunk load/unload is deterministic and happens outside the tick where possible, with a per-frame
budget so streaming never stalls a frame.

### Streaming at driving speed

**This is the hardest problem in the design.** A [vehicle](25-vehicles.md) at 60 km/h crosses chunk
boundaries continuously, which means promoting terrain, buildings, and entities *while the player is
already moving into them* — with a horde possibly loaded behind. Three mechanisms make it tractable:

**1. Prefetch along road topology, not a radius.** Travel follows
[roads](24-world-and-scale.md#roads) almost always, so the next chunks needed are predictable from the
road graph and the velocity vector. Loading a corridor ahead is a fraction of the work of loading a
disc around the player, and it's the optimization that makes the continuous region affordable at all.

**2. Staged promotion across ticks.** A district promotes over several ticks beginning well before
contact, never in a single frame. District tier → abstract → coarse, with the fine detail arriving last
and only where the player will actually be.

**3. A speed cap tied to load state.** If streaming can't stay ahead, **the vehicle cannot accelerate
further**. The engine strains, the throttle stops responding, and the player slows down. This is
diegetic, it reads as the vehicle's limit rather than the engine's, and it means **the frame is never
sacrificed to the throttle**. Budget is preserved by bounding the input, not by dropping work.

### Hysteresis

Tier boundaries use different promote and demote thresholds so a player driving back and forth across a
boundary doesn't thrash the whole district in and out.

## Rendering

**This is the measured cost centre**, not the simulation. Everything below is load-bearing rather
than an optimization to reach for later.

- **Decoupled from the sim.** Render interpolates between the last two fixed-timestep states, so 20 Hz
  simulation looks smooth at 60 fps.
- **Aggressive culling** via the spatial hash. At a ~30× draw-to-sim ratio, an entity that is
  simulated but not drawn is nearly free — so culling early is worth more than any sim optimization
  available.
- **Sprite batching** by texture; the tile layer redraws only dirty regions.
- **The renderer never writes to the sim** and is never on the tick's critical path.

## Save performance

Saves are frequent (single-slot, continuous, no save-scumming). State is plain and serializable, so
serialization is cheap. Writes are atomic — write to a temp file, then rename — so a crash mid-write
can't corrupt a fifty-hour run. That's a hardcore-game obligation, not an optimization.

## Measuring

Because the sim is [deterministic and headless](19-architecture.md), performance is measurable rather
than felt:

- **Per-system tick timings** recorded and reportable, so a regression names its system.
- **Entity-count stress scenarios** run headless to find the ceiling before players do.
- **Memory profiling** on long runs, since a hardcore game's sessions are long and a slow leak is a
  run-ending bug.

### The CI benchmark suite

Fixed seeds, asserted budgets, **failing the build on regression**. Each scenario targets a specific
way the design could become unaffordable:

| Scenario | Tests | Budget |
|---|---|---|
| **Quiet night** | Baseline; the field at rest should cost almost nothing | **≤0.5 ms tick, ≤4 ms frame** |
| **Night 40 siege** — 600 zombies, 18 survivors | Combat, grabs, flow fields at peak entity count | **≤8 ms tick, ≤10 ms frame**, 60 fps |
| **The drive** — 60 km/h through a district with 400 zombies loaded, streaming ahead | **The headline case.** Streaming, promotion, and horde simulation simultaneously | 60 fps, ≤4 ms/frame streaming, no stalls |
| **Convoy transit** — three [vehicles](26-mobile-bases.md#convoys), full modules, crossing two districts | Multi-vehicle load, district promotion at speed | 60 fps sustained |
| **Long run** — 100 simulated days headless | Memory growth, leak detection, state size | No unbounded growth |
| **Save under load** | Serialization during a siege | <100 ms |

The *Quiet night* budget is deliberately much tighter than it was. The spike measured 0.01 ms sim and
2.10 ms frame with 60 zombies idle, so the original `≤2 ms tick` would have passed while the tick got
200× slower. A baseline scenario that cannot fail is not a baseline.

The drive scenario is the one that decides whether the continuous region was the right call. It should
be written and running *before* vehicles are built, against synthetic load — finding out early is the
whole point of having a pillar.

**A caveat that has now cost the frame budget twice.** It passes with viewport culling removed,
because 2,000 flat rectangles are cheap — recorded when culling landed. Occlusion has now taken the
entities it measures from 216 to 11, so it is measuring 95% less drawing than it was. Neither
mitigation is wrong; the benchmark is simply a regression guard rather than proof that either earns
its place, and it will only become the second thing when sprites replace rectangles. Anyone
tightening this budget should raise the entity count first.

### Shipped Godot runtime measurements

`npm run godot:bench:runtime` boots `SimBoot.playable()` with its real default seed and
256-tile district, warms up 100 complete `world.step()` calls, then measures 600 more, including
every registered system and the event drain. It asserts the existing **8 ms mean / 16 ms worst
tick** limits. This daytime boot is not the specification's separate *quiet night* fixture, so
it is not mislabeled as satisfying the 0.5 ms quiet-night budget. No system is removed to make
the measurement cheaper.

`npm run godot:bench:frame` needs a display and a real Compatibility renderer; headless mode is
refused. It instantiates `main.tscn`, attaches a subclass whose `_draw` times `super._draw()`,
starts the ordinary run and holds simulation and `_process` still. At **1280×720**, it warms
up 30 draws and samples 120, first with the booted world and then with **1,000 additional
textured bodies** inside the player's actual Focal sight and viewport. Positions repeat in
that dense stress fixture; it tests renderer work, not physical horde behavior. Every sample
must finish the real consumer, and the crowd must reach both the Focal list and the texture
path in that same frame. Stale completion markers and cached looks cannot satisfy it.

The **10 ms mean** threshold applies to this world-draw CPU stage. It is a necessary subset
of the draw target, not a complete rendered-frame measurement: child UI drawing, main
`_process`, GPU completion and presentation are excluded. The result separately reports
RenderServer pre/post wall time and intervals between frame-post signals; those intervals
include benchmark validation work. Neither is labeled GPU time or player-facing fps. The
driver requests disabled V-Sync and reports the mode the display API returns; llvmpipe may
warn that changing it is unsupported. That cannot turn CPU timing into an fps result.

The runner owns the targets in `scripts/runtime-budget.mjs`, computes statistics from the raw
samples, and exits one for overruns, missing measurements, an engine/script failure, an
incorrect fixture, or its 180-second timeout. `npm run check:runtime-budget`, reached by CI,
uses deterministic engine transcripts through the **real runner process** to prove passing
and failing exits, mean and single-tick overruns, required sample counts, canonical seed,
complete ticks, display/viewport, real textured crowd, malformed output, and timeout handling.
It checks the exact engine invocation and the fixture's shipped consumers too. This contract
test passing does **not** mean the real timing commands pass.

Measured **2026-10-03**, Godot 4.7.1, Linux, Intel Xeon Platinum 8573C, otherwise idle execution
environment (other worktrees' gates and captures paused): the default world had **89 systems
and 99 shamblers**, seed 20260805, and the sampled ticks were **36100→36700**.
The game source was `5b2706c`, before the parallel wall-floor and UI changes were integrated;
only the benchmark tooling was added for these measurements.

| Actual consumer | Mean | p95 | Worst | Unchanged target | Outcome |
|---|---:|---:|---:|---|---|
| Shipped default world tick | 29.408 ms | 39.345 ms | 296.393 ms | 8 ms mean / 16 ms worst | exit 1 |
| Boot world `_draw` CPU stage, 1280×720 | 41.191 ms | 90.684 ms | 214.854 ms | 10 ms mean | exit 1 |
| 1,000 textured-body `_draw` CPU stage, 1280×720 | 299.397 ms | 334.333 ms | 506.019 ms | 10 ms mean | exit 1 |

The two displayed runs used X11/Xvfb with **llvmpipe (LLVM 19.1.7, 256 bits)**. Their separate
RenderServer means were **42.722 / 56.505 ms**, and the harness-inclusive intervals were
**85.867 / 364.210 ms**, boot/crowd respectively. These software-renderer measurements are not
hardware GPU results. The API reported V-Sync mode zero after the disable request, while the
driver warned that changing it is unsupported; no present-rate claim follows from that. A first
1920×1080 diagnostic was rejected by the fixture contract and is not the canonical result above.

A separate diagnostic wrapped every registered system over the **same 100-warmup / 600-sample
tick interval**. Mean contributions were jobs **5.251 ms**, shambler AI **4.340**, visibility
**3.654**, sightings **2.951**, NPC combat **2.272**, encumbrance **2.039**, and self-aid
**1.986**. Its worst tick, **36134**, took **302.871 ms**: map generation changed by one,
**105** observers recast, visibility cost **176.980 ms** and jobs **100.441 ms**. This is
instrumented attribution, not a second budget baseline; the temporary driver was deleted.
It identifies a visibility/path invalidation spike alongside repeated ordinary per-tick work,
not an isolated scent-grid problem.

The displayed consumer was also sabotaged: after five successful draws, including warmup at
the held simulation tick, the wrapper stopped calling `super._draw()` while still incrementing
its own count. The real frame command refused the incomplete draw and exited one before
producing a passing sample. The mutation was restored. This is independent of the transcript
tests: a previous frame's successful marker cannot make a skipped consumer pass.

These are baseline failures, not regressions introduced by measuring them. Do not raise the
targets to make the commands green. The next bounded performance work should profile the
same warm sample interval, preserve deterministic outcomes, and address repeated content
lookups, unchanged component queries, pathfinding spikes and per-observer work as separate
measured changes. After the runtime passes its budgets on the intended reference runner,
wire the real commands into CI; quiet-night, siege, full frame/FPS, save, streaming and long-run
memory scenarios still need their own representative fixtures.

### Remaining milestone evidence

At the measured **34.00 ticks/second**, the FULL harness's exact no-wipe span from the default
09:00 boot to day ten's end of dusk is **2,772,000 ticks**, which projects to **22.64 hours per
campaign** and **271.73 hours for four seeds × three arms**, before its additional six-survivor
Auto case. This is an early-day throughput projection, not a measured campaign completion
time: population and workload change, and a wipe can end a run early. The historical nine-hour
figure came from the smaller 64-tile harness and must not be advertised for the shipped
256-tile world. No full grid was launched for this measurement.
The shipped-size invocation is `BALANCE_TILES=256 npm run godot:m2:balance:full`; the full-tier
script sets `BALANCE_FULL=1` but otherwise retains the harness's 64-tile default.

The proof order in [docs/23](23-roadmap.md#whats-left-in-milestone-2) remains:

1. Add distribution assertions over per-seed quiet nights, sieges, deaths and run lengths.
   The existing FAST tier has only four compressed dusk-window runs; it is not survival
   distribution evidence. Keep zero-observation cases explicit, and sabotage a counter or
   distribution to prove each new assertion can fail.
2. Measure melee-only and ranged-only outcomes on matched seeds and the same uncompressed
   map/day span, recording exposure, contact and depletion as well as survival. The FULL
   tier has the three arms, but its aggregate totals alone do not establish parity.
3. Schedule the full grid using measured throughput and a resumable per-seed/per-arm artifact
   runner before committing to a multi-day job. Preserve seed, map size, code/content revision,
   exact tick span and arm in each artifact; a shortened pilot is labeled a pilot.
4. Have a person play ten days. Automation cannot close that criterion, including whether
   colonists walking for found armor makes the campaign too punishing.

## Known risks

Named honestly, since they're the likeliest places this breaks:

| Risk | Mitigation |
|---|---|
| **Streaming at driving speed** | Road-topology prefetch, staged promotion, load-tied speed cap. **The hardest problem in the design**, and the reason the drive benchmark exists. |
| **Draw cost at horde scale** | Measured at ~30× the sim cost, and the reason the budgets above assert frame time. Culling, batching, and dirty-region tile redraw. The likeliest source of a frame-rate regression is a rendering change, not a simulation one. |
| ~~Scent diffusion is O(grid) and continuous~~ **Measured, and it is not a risk.** | 0.0377 ms per diffusion step at 4 Hz on a 64x64 grid, or **0.0075 ms amortised per tick** — about a tenth of one percent of the 8 ms budget, and the *same* cost whether the district is saturated with scent or completely fresh, because the step scans the grid rather than the live cells. Dirty regions remain unearned. What scales with the horde is per-entity AI, which noise already paid for. |
| Tier thrashing at boundaries | Hysteresis — different promote and demote thresholds |
| A siege promoting hundreds at once | Staged promotion across several ticks, beginning before contact |
| A continuous region's total state size | District tier holds six numbers per unvisited district; only visited districts carry depletion detail |
| GC pressure from per-tick allocation | Object pooling for hot paths; components as flat typed arrays where profiling justifies it |
| Modifier resolution called per-stat-read | Cache resolved stats, invalidate by source on change |

## Cut list

- **Multithreading / web workers.** Would complicate determinism significantly. Revisit only against
  real profiling data showing single-thread limits.
- **GPU compute for the attention field.** Interesting; breaks the
  [engine-independence rule](19-architecture.md) and the headless test path.
- **Archetype/SoA storage as a first move.** Premature. Revisit with numbers.
- **Level-of-detail rendering.** The camera range is small enough that it isn't warranted.

---

**Previous:** [21 — Extensibility](21-extensibility.md) · **Next:** [27 — Multiplayer](27-multiplayer.md) ·
[Doc index](../README.md#documentation)
