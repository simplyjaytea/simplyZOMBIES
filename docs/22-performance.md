# 22 — Performance

*Why this exists: the design calls for hordes, a continuously-propagating [attention
field](03-attention.md), and a colony of individually-simulated people — in a browser. That works
only if the cost of distant, irrelevant simulation is near zero.*

---

## Targets

| Metric | Target |
|---|---|
| Frame rate | 60 fps at 1× and 3×; ≥30 fps at 10× |
| Entities, total | ~3,000 |
| Entities, detailed simulation | ~300 (near the player and the base) |
| Survivors | ~20 individually simulated at full fidelity |
| Sim tick | Fixed 20 Hz, decoupled from render |
| Tick budget | ≤8 ms average, ≤16 ms worst case |
| Save write | <100 ms (frequent, per the [hardcore contract](01-hardcore-contract.md)) |

## The core idea: tiered simulation

Most zombies, most of the time, are far away and doing nothing interesting. Simulating them precisely
is wasted work.

| Tier | Where | What runs | Rate |
|---|---|---|---|
| **Detailed** | Near the player or the base | Full ECS: pathing, combat, grabs, per-part damage | Every tick |
| **Coarse** | Mid-range | Position, gradient following, aggregate health | Every 4th tick |
| **Abstract** | Distant | **Hordes as single entities**: a position, a bearing, a count, a composition | Every 20th tick |

Entities promote and demote between tiers as the player and the field move. The promotion boundary sits
outside perception range in every direction, so a horde always resolves into individuals *before* it's
observable — the player never sees a crowd pop into existence.

**Abstract-tier hordes are why the design can afford large sieges.** A 400-zombie horde crossing the
map is one entity with a count until it's close enough to matter.

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
| **Light** | Recomputed only when an emitter changes state or an occluder moves. Static most of the time. |
| **Scent** | The only continuously-updating channel. Diffusion at a low rate — a few Hz, not every tick. |

**Dirty-region tracking**: only cells that changed, plus their propagation neighborhoods, are
recomputed. A quiet base at night costs almost nothing.

**Budgeting**: propagation work has a per-tick ceiling. Excess queues to the next tick. Under extreme
load the field updates slightly slower rather than the frame dropping — degradation is graceful and
deterministic (the queue is ordered).

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

## Rendering

- **Decoupled from the sim.** Render interpolates between the last two fixed-timestep states, so 20 Hz
  simulation looks smooth at 60 fps.
- **Aggressive culling** via the spatial hash.
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
- **Benchmark scenarios** as fixed seeds — "night 40 siege, 600 zombies, 18 survivors" — run in CI with
  budget assertions.
- **Entity-count stress scenarios** run headless to find the ceiling before players do.
- **Memory profiling** on long runs, since a hardcore game's sessions are long and a slow leak is a
  run-ending bug.

## Known risks

Named honestly, since they're the likeliest places this breaks:

| Risk | Mitigation |
|---|---|
| Scent diffusion is O(grid) and continuous | Coarse grid, low update rate, dirty regions. **The most likely thing to need rework.** |
| Tier thrashing at boundaries | Hysteresis — different promote and demote thresholds |
| A siege promoting hundreds at once | Staged promotion across several ticks, beginning before contact |
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

**Previous:** [21 — Extensibility](21-extensibility.md) · **Next:** [23 — Roadmap](23-roadmap.md) ·
[Doc index](../README.md#documentation)
