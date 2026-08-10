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
