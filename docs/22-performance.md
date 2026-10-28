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
- **Sprite batching** by texture; the tile layer redraws only dirty regions. In the Godot build this
  is [the world, baked](#the-world-baked): the ground, walls and roofs are drawn once per chunk
  and a mask shader picks per tile which look shows.
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

### Bringing the tick to budget

Alpha plan item A3 takes the shipped tick to its unchanged 8 ms mean / 16 ms worst budget one
system at a time, biggest measured win first. Each slice is a memo, an index or a cheaper route to
the answer the sim already gave, never a change to what it decides; `npm run godot:m2:tick`
(`godot/check_m2_tick.gd`) holds each fast path to the slow one it replaced and changes the data
under it to prove it cannot go stale. Every number below is `npm run godot:bench:runtime` on the
same cloud Xeon (2.10 GHz, four cores), same seed 20260805, same 100-warmup / 600-sample window;
the attribution beside it is a throwaway driver timing each registered system over that window,
deleted afterwards.

| Slice | Date | Mean | Worst | What it cut |
|---|---|---:|---:|---|
| Baseline, `main` at `bf6b41a` | 2026-10-19 | 32.42 ms | 300.98 ms | -- |
| 1. Content entries by id | 2026-10-19 | 24.41 ms | 319.35 ms | `SimItems._content_get` walked every file in the tree per lookup |
| 2. The map-change spike | 2026-10-19 | 24.78 ms | 68.13 ms | a door swing rebuilt every solidity cell, recast every observer and re-planned with a linear A* |
| 3. The shadowcast inlined | 2026-10-19 | 21.70 ms | 47.59 ms | four calls and a Dictionary per tile and per frame |
| 4. The whole-district scans | 2026-10-19 | 19.40 ms | 37.11 ms | every AI asked about every body on the map, then kept the near ones |
| 5. The component query memo | 2026-10-19 | 17.02 ms | 35.77 ms | a hundred `components.query` calls a tick rebuilt the same sorted intersection |
| 6. What each body paid every tick | 2026-10-19 | 13.68 ms | 36.89 ms | each observer re-read every position, every colonist walked every zombie, every zombie re-read the sky |
| 7. The cast's rows and the hour | 2026-10-19 | 13.49 ms | 32.67 ms | the shadowcast resolved its quadrant per tile, every observer re-read the hour, a dormant zombie resolved a speed it never used |
| 8. The per-body cuts | 2026-10-20 | 13.63 ms | 30.01 ms | a 21 ms A* on Dictionaries, thirteen modifier strips per unhurt body, a scan of every positioned thing for the screamer, the Dress test reading each item twice |
| 9. The far quarter and the spread cast | 2026-10-20 | 12.07 ms | 27.29 ms | every far idle zombie thinking and recasting every tick, a colonist's 48 m cast landing whole on the tick they crossed a tile |
| 10. The tables read straight | 2026-10-20 | 10.63 ms | 31.86 ms | four thousand component calls a tick through an untyped world, a sighting list walked per body in view, every body walked per swinging door |
| *a third, slower container from here; slice 10 there: 13.70 / 37.70* | | | | |
| 11. The worst tick's spikes | 2026-10-20 | 14.29 ms | 32.09 ms | the player's 48 m cast landing whole on the tick they stepped, two colonist quadrants landing together, a long plan expanding every tile tied on cost in arrival order |

**Slice 1, content entries by id.** `SimItems._content_get` found an entry by walking every value
in the flat content tree until one carried the id. `item_base_of` runs about a hundred times a
tick in the shipped world (dressing checks every loose garment, encumbrance weighs every pack) at
about 0.12 ms a walk, which was **12.7 ms** of the 32 ms tick. The answer is now memoised on the
world (`content_index`, never a static, for the two-worlds trap) and a hit is trusted only while
the tree still holds that same object at the same key with the same id, so an entry swapped for an
edited copy, an erased key, an added one or a replaced tree all fall back to the scan and rebuild.
Jobs fell from 5.9 to 2.0 ms and encumbrance from 2.4 to 0.45 ms. The worst tick is unchanged
within noise: it is the map-change spike, the next slice.

**Slice 2, the map-change spike.** One door swinging shut cost about 300 ms: `SimFortify.sync_map`
rebuilt all 65,536 solidity cells (90-170 ms), the generation bump recast every one of the 105
observers (200 ms), and every walk re-planned on an A* whose open set was a linear scan (100 ms).
The world now logs *where* each generation changed the map (`world.map_changes`, written by
`invalidate_tiles(rect)`; `invalidateMap()` and a bare `mapGeneration += 1` still mean "all of
it"), and `map_unchanged_within(gen, area)` answers "changed" whenever in doubt. In play, a door,
board or barricade rewrites only the cells whose overlay changed and logs only their rectangle;
a restore, a boot and a gate editing `map.tiles` keep the full rebuild. A car logs the footprints
it moved. A view or a light cast made at an older generation stands when nothing changed inside
its own square, since a shadowcast reads nothing outside it. A* keeps a binary heap ordered by
(f, first-entry order), which is the order the linear scan chose in, so it plans the same path
tie for tie.

**One behaviour change, the dead's views.** A person's cast moves with their tile, so a person
who keeps a view across a bump is still on the tile they cast from and keeps exactly what a recast
would give. The dead recast only after walking two tiles (`ZOMBIE_RECAST_TILES`), and every bump
used to recast every dead body a tile off its origin: half the district on a door swing and every
tile a car crosses, 140 ms. They now keep that tile-off view across a bump outside their square too,
which is the approximation they already live with between bumps; nothing draws a zombie's view.
`SimVisibility.DEAD_KEEP_VIEW` switches the old rule back on. With it off, a serialized-world
sha256 matches `main` at every 500-tick checkpoint across 3,000 ticks, so the rest of the slice
changes no outcome. With it on, the run diverges from `main` at tick 36,968, when one shambler
notices a colonist on a different tick.

**Slice 3, the shadowcast inlined.** Every tile a cast visited cost four calls
(`blocks_sight` → `opacity_at` → `overlay_at` and `tile_at`) and every wedge a Dictionary frame,
and the reset zeroed its buffer one byte at a time. A 48-tile cast visits about seven thousand
tiles. The cast now reads the tile class and overlay straight off the map's arrays, with the same
answer per tile (out of bounds is a wall, an overlay outranks the class, Low blocks only a
crouched eye), keeps its frames as five ints on one flat array popped in the same order, and
clears with `fill`. Visibility fell from 3.7 to 2.2 ms mean and its worst from 140 to 19 ms. With
`DEAD_KEEP_VIEW` off the 3,000-tick hash still matches `main`. This run and the slices after it
were measured with gates running on the other cores, so treat each mean as within a millisecond
or so.

**Slice 4, the whole-district scans.** Three systems asked a question of every body on the
district and then threw most of the answers away. Every armed NPC and raider asked
`SimAllegiance.enemies_of` (a `hostile` test on each of the hundred bodies) and only then kept the
ones in reach; `enemies_within` asks the distance first and returns the same ids in the same
order. The shambler pass tested all 340-odd positioned things, every item on the ground among
them, against the three person markers; `_people_with_position` walks the three markers' own
tables. Sightings asked `detail` of every body and cupboard for every observer, though a target
outside the observer's shadowcast square is Unseen by construction; `_in_square` skips those
first. NPC combat fell from 2.7 to 1.1 ms, the shambler pass from 5.3 to 4.4 and sightings from
3.4 to 2.6. No outcome moves: the 3,000-tick hash with `DEAD_KEEP_VIEW` off still matches `main`.

**Slice 5, the component query memo.** `components.query` built and sorted a fresh intersection
on every call, about a hundred calls a tick and 2.3 ms in all, nearly every one asking what it
asked the tick before. The store now counts each table's membership changes (an entity gaining or
losing the component, never a value replaced) and answers from a memo row while every count it
was built against still holds; `restore` drops the memo, and every caller gets its own copy. The
bench is noisy at this size, so from here each row is the median of three runs interleaved with
three of the slice before on the same machine: slice 4 measured 18.85 / 38.49 ms that way, slice
5 17.02 / 35.77. The 3,000-tick hash with `DEAD_KEEP_VIEW` off still matches `main`.

**Slice 6, what each body paid every tick.** Sightings read every body's and cupboard's position
once per observer; `observe` now reads them once and hands each observer only what lies inside its
square (`_square_bounds` and `_in_bounds`, the same test as `_in_square`), with a searched
cupboard handed to everybody because it is forgotten on sight of the flag. Self-aid walked every
zombie for every colonist to ask whether a claw was in reach before asking whether the colonist
needed care at all; it now asks care first, in one pass over the wound list instead of three
selectors over ten parts, and the claw check asks distance before health. The shambler pass reads
the sky's speed and sight multipliers once a tick instead of once a body. Measured as the median
of three runs interleaved with slice 5 on a busier machine: slice 5 17.77 / 50.39 ms, slice 6
13.68 / 36.89; the worst tick is the noisiest number here. The 3,000-tick hash with
`DEAD_KEEP_VIEW` off still matches `main`.

**Slice 7, the cast's rows and the hour.** The shadowcast now resolves each row's fixed axis,
bounds test and index steps once per row instead of choosing a quadrant per tile, and its two
row-limit divisions are inlined; inside the range circle a tile is inside the square, so the cell
write needs no bounds test. `SimVisibility.refresh` reads the hour's ambient factor once for every
observer. The shambler pass resolves a body's seek speed only in the three arms that move it, so
the fifth of the district lying dormant no longer pays for it. A smaller step than the slices
before it: slice 6 13.77 / 34.60 ms against slice 7 13.49 / 32.67, median of three interleaved,
within the bench's noise on its own. The 3,000-tick hash with `DEAD_KEEP_VIEW` off still matches
`main`.

**Slice 8, the per-body cuts.** A fresh container ran the bench slower, so this row is read
against slice 7 measured the same way on it: **15.15 / 41.62 ms** to **13.63 / 30.01**, median of
three interleaved runs, about a tenth off the mean. `SimPath.find` keeps its heap order but packs
each entry as one int (f, then first-entry order, then the tile) and holds g, order and the way
back in flat arrays, with `walkable` read straight off the world's cells and the map's tiles: the
59-step plan round a block that was a 21 ms tick is now about 7 ms, by the same expansions.
`wounds.impair` stripped thirteen modifier sources from every body every tick before adding back
the few that apply; a body with no wound, no impairing blood loss and none of those sources
(`SimModifiers.holds_any`) is now skipped, and `remove_by_source` looks before it rebuilds a list
it would leave unchanged, 0.42 to 0.06 ms. The screamer's alarm walked every positioned thing for
its people; it asks `SimAllegiance.people_with_position`, the shambler's own walk moved there. The
Dress test reads an item's base once and asks for an `armor` block first. Smaller: scent diffusion
swaps its two buffers instead of copying one into the other, each view keeps its arc cosines beside
the angle they came from, `refresh` reads the light index once, the movement pass reads the
world's cells directly and asks each corner once, and the noise emitter preloads the stance table
instead of loading it per body. The 3,000-tick hash with `DEAD_KEEP_VIEW` off still matches
`main`.

**Slice 9, the far quarter and the spread cast.** The first slice that changes what the sim
decides, approved as an engineering call under the owner's standing brief of 2026-10-19 and held
behind its own two switches. A wandering or dormant zombie with no person within 40 m
(`SimShambler.FAR_THINK_METRES`) and no hold thinks on one tick in four (`FAR_THINK_EVERY`), its
phase set by its id; between thinks its countdowns run, a dormant body stays pinned and anything
else keeps the velocity it had, so it walks the line it would have walked and turns, hears or
smells up to three ticks late. Scent and light steer by four ticks' worth on the tick it does
think (`_steps_bias`). Its view rests on the ticks before it does not think: the shambler marks
it in `SimVisibility.resting` and the next refresh keeps the view it has. A colonist other than
the player recasts after two tiles (`PERSON_RECAST_TILES`) rather than one, and the recast is
spread a quadrant at a time, two quadrants a tick for everyone together, longest-waiting first,
with the old view standing until the new one lands whole; the player and the dead cast as
before. `npm run godot:bench:runtime`, median of three interleaved runs on the slower container:
slice 8 **14.00 / 31.35 ms** to **12.07 / 27.29**. With `THINK_LOD` and `STAGGER_PERSON_CASTS`
off the 3,000-tick hash still matches `main`; with them on it repeats exactly run to run, and a
save between thinks restores onto the same phase because the phase is the id and the tick.
`godot:m2:tick` FAR-THINK and SPREAD hold both rules, and every lane in the chain the full tree
was run against (51 gates over four lanes, balance included) stayed green.

**Slice 10, the tables read straight.** A counting driver found about 3,300 `get_component` and
800 `has_component` calls a tick, each two calls through an untyped world at about 0.7 µs against
0.14 µs for the dictionary read underneath. `SimComponentStore.table` hands a pass the live table,
read-only by convention, and the passes that made most of the calls hold their tables once:
movement, the shambler think, sightings, the visibility refresh, the noise emitter,
`enemies_within`, the settlers' threat scan, and the fortify doors and presses. Sightings finds a
remembered body's record through a map of the first record per id, and a cupboard through a set;
the door swing builds one set of occupied tiles. Median of three interleaved runs on the slower
container: slice 9 **12.27 / 28.78 ms** to **10.63 / 31.86**. The 3,000-tick hash with both slice 9
switches off still matches `main`, and with them on matches slice 9.

**Slice 11, the worst tick's spikes.** A driver that timed every system and every cast and
plan on each tick over 14 ms, on a quiet container, named three spike sources: the player's whole
48 m cast, about 3.5 ms on the tick they crossed a tile; two quadrants of a colonist's spread cast
landing together, 1.3 to 2.8 ms; and a long job plan, 5 ms for 59 steps. Everything else over the
line was one system or several slowing at once with no cast or plan behind it, which is the host.
Each cut has its own gate-drivable switch, and a lane that pins one restores it.
`SimVisibility.STAGGER_PLAYER_CAST` spreads the player's recast over two ticks, two quadrants
each (`PLAYER_QUADRANTS_PER_TICK`), so the view lands whole one tick (50 ms) after the step. The
old view stands until then; the first cast, a lit target and the switch off still cast at once.
The player has a queue of its own, so colonists waiting never delay it. The colonist budget
`PERSON_QUADRANTS_PER_TICK` goes from two quadrants a tick to one, which halves that spike. This
is a constant, not a switch, because it changes only how fast a queue drains under the slice 9
switch. `SimPath.NEAR_TIES` breaks a tie on cost toward the tile nearer the goal before arrival
order, in both the flat and the Dictionary search. Plan lengths are unchanged, because the order
among equal costs never changes whether a plan is shortest. A long plan expands fewer tiles, and
a pair the old order gave up on at its 4,096-tile cap can now be reached. The plan still runs
whole on one tick: amortizing a plan across ticks is a bigger change and stays post-alpha.

Measured on a third container, roughly twice as slow and much noisier than the one that profiled
it. Median of three interleaved runs: slice 10 **13.70 / 37.70 ms** to **14.29 / 32.09**. The
mean is inside the noise, and single runs of either build swung by 2 ms. The worst tick of the
visibility refresh, timed per system in three runs each with the two switches off and then on,
went from 8.6, 17.1 and 15.6 ms to 6.4, 8.5 and 8.7. The job planner's went from 12.4, 13.4 and
9.2 ms to 8.5, 13.7 and 8.2. The same runs show the host's noise directly: a cheap system such as
encumbrance or the scent field, with a mean under 0.5 ms, took 7 to 25 ms on a single tick. Before
the move, on the quiet container, the same build ran **7.22, 6.94 and 7.21 ms** mean with worst
ticks of **14.96, 13.32 and 15.63 ms**, all under 16. Slice 10 alone there ran a 7.0 to 7.3 ms
mean, with worst ticks of 14.7, 23.8 and 21.6. Those runs were not interleaved, so they are a
reading, not a measurement. With both new switches off and the three earlier ones off too, the
3,000-tick hash matches `main`. With them on, it repeats run to run. `godot:m2:tick` NEAR-TIES and
PLAYER-CAST hold both rules, and the full `godot:m2` chain, run over four lanes, stayed green.

**Where the tick stops for the alpha.** Against the baseline's 32.42 ms on the faster container,
slice 10 reads about 9.5 ms by the ratio both containers measured for slice 7 (13.49 there, 15.15
here), and 10.6 ms where it was measured. The mean meets the alpha's stop point of 10 ms; the 8 ms
budget and the 16 ms worst do not hold, and they are post-alpha work. The p95 is about 16 ms and
single ticks run 20 to 34 ms. A per-system driver over the same window attributes the spikes: a
whole 48 m cast (the player's, which slice 9 deliberately left whole because roofs and the light
wash read it, and a zombie's after a map change near it) costs about 7 ms; a long job plan up to
12 ms even on flat arrays; and some runs of consecutive ticks slow every system at once, which is
the shared container rather than any one cost. The remaining mean is spread thin: the shambler
think about 2.1 ms, sightings 1.3, the refresh 1.3, jobs 1.0, and nothing else above 0.6. The next
cuts are named in docs/23's runtime budget entry under what's left.

Slice 11 then took the measured spikes on the worst tick. On a quiet container the worst tick
read under 16 ms in three of three runs. On a noisy one it stays 25 to 38 ms whichever build is
running, because there the spike is the host slowing whatever system it lands on. Two causes
remain in the sim, both post-alpha. A long job plan still runs whole on one tick, 8 to 14 ms there
and about 5 on the quiet host. A zombie's whole 12-tile recast after a nearby map change costs
under 1 ms on its own, but several can land on one tick. Before a timing gate goes on, the worst
tick needs measuring on a quiet, dedicated machine. Until then it says more about the container
than about the sim.
**P0, the colony sample and Haul's walk (2026-10-24, `-p0-tick`).** The shipped sample measures a
boot with its 72 loose items; a colony mid-run carries more on the ground, so
`godot/bench/runtime_tick.gd` now also samples `colony-tick`: the same booted world with 200 more
loose items on outdoor floor inside the errand radius, placed from a local seeded stream, 100
warm-up and 600 samples, judged by `scripts/runtime-budget.mjs` at the same 8 ms mean and 16 ms
worst. Haul's search ran `_danger_at` (one query and one walk over every shambler) for every loose
item, so a colony with 272 on the ground paid about 21.5 ms for one idle colonist's Haul call. The
cheap filters still run on every item, in their old order, and the zombie walk now runs on the
nearest item left, and on the next only when a zombie stands near the first: the same answer as
the old loop, pinned by the `ORDER` lane in `godot:m2:tick` and by a 3,000-tick serialize hash on a
colony-loaded world, identical to `main`'s. The call is 3.7 ms (1.6 ms with the zombie walk off).
Across three interleaved colony runs on this container jobs.ai's mean went from 4.45 ms (4.07,
4.45, 4.73) to 3.85 ms (3.77, 3.85, 4.89); the whole tick did not separate from noise, since the
box's own spread is 8.6 to 13.3 ms between runs of the same code. The tick stays over budget. The
next costs, from the same driver on an idle colonist with 272 loose items: the Dress scan 1.3 ms
(every ground item asks `_is_better_armor` and may erase a stale claim, so its order is part of
what it decides and it was left alone), the stockpile scan 0.7 ms a call (`stockpile_items`, read
by Cook, Repair and Water), Repair 0.7 ms and Cook 0.6 ms.

**Stockpile spread, 2026-10-24 (S3, `claude/project-thread-spo`).** A haul's drop point is now the
emptiest free tile of the nearest stockpile patch, chosen once per haul and kept on the job. Three
interleaved pairs of `godot:bench:runtime` against main 21211eac on this box: `shipped-tick` head
16.76, 18.66, 18.02 ms (median 18.02) against main 17.22, 17.28, 17.09 ms (median 17.22); `colony-tick`
head 20.92, 19.90, 19.51 ms (median 19.90) against main 19.88, 19.35, 20.33 ms (median 19.88). The
shipped median is +0.8 ms, inside the 1 to 4 ms run-to-run spread this box shows; the colony tick is
level. Both sit over the 8 ms mean target, as main does.

**The colony tick, P4, 2026-10-28 (`claude/project-thread-k4ppk0`).** Two memos and one spike, no
outcome moved (docs/23's record, "the colony tick without changing outcomes"). A per-system driver
over day one of the playtest on seeds 99 and 404 put every tick over 200 ms on one colonist's
Retreat re-plan reading the lot's walls once per lot tile, 206 to 222 ms quiet and the 480 to 637
ms in the day-one logs under load; after the fix nothing on those days passes 92 ms. The walls box
read itself fell from 0.33 ms to 0.003 ms, and `stockpile_items` from 1.4 ms to 0.16 ms a call
with 272 loose items (2.6 calls a colony tick). Median of three interleaved `godot:bench:runtime`
pairs against main `0e562cf8` on this box, mean / worst:

| Sample | main | head |
|---|---:|---:|
| `shipped-tick` | 11.37 / 27.75 ms (11.23, 11.37, 11.77) | 10.45 / 35.04 ms (10.85, 9.88, 10.45) |
| `colony-tick` | 14.48 / 31.61 ms (14.48, 14.22, 15.93) | 10.45 / 21.79 ms (10.45, 10.45, 11.15) |

The colony mean drops about 4 ms, the stockpile scan and the danger rule's walls read. The shipped
worst is host noise at this size: head's worst ticks fell at no fixed tick, and a fourth main run
outside the three threw a 210 ms tick. Both samples remain over the 8 / 16 ms budget.

### The world, baked

Plan item A4, 2026-10-19 (`presentation/world_layers.gd`, `world_mask.gdshader`; docs/23's
record, "Performance — the world, baked"). The per-frame tile loop is gone: each 8×8-tile chunk's
ground, walls and roofs are drawn once into five RenderingServer canvas items (seen, wall-module
boards, remembered, roof, roof dimmed) that keep their commands. The sight sets reach a mask
shader as two small textures, uploaded only when they change, and a chunk's layer with nothing to
show is hidden. A chunk rebakes when its inputs change (zoom, map object, content tree and seed
drop everything; a map generation change re-signs each chunk and drops the changed ones; snow
rebakes within 2 ms a frame). `npm run godot:check:world_bake` holds the rebake triggers, the mask
rule and the no-leak property.

Measured 2026-10-19 with `npm run godot:bench:frame` on one container, the parent commit and this
change back to back: Godot 4.7.1, X11/Xvfb, **llvmpipe (LLVM 20.1.2, 256 bits)**, Intel Xeon
@ 2.10 GHz, 1280×720.

| Stage | Before | After |
|---|---:|---:|
| shipped-draw `_draw` CPU, mean / p95 | 28.5 / 38.4 ms | **8.7 / 12.0 ms** |
| shipped-draw RenderServer wall time, mean | 14.3 ms | 18.5 ms |
| shipped-draw harness-inclusive interval, mean | 43.5 ms | 27.8 ms |
| crowded-draw `_draw` CPU, mean | 317.9 ms | 108.0 ms |

shipped-draw meets the 10 ms mean; crowded-draw is still the thousand bodies and is not met.
A throwaway driver walking the player six tiles a second for 120 frames measured the `_draw`
CPU stage at **18.9 → 9.4–10.5 ms** mean at zoom 64 and **37.6 → 11.3 ms** at zoom 32, the
chunks entering the view baking inside the frame. An earlier pass on a four-core container
measured shipped-draw at 1920×1080 **35.2 → 9.0 ms**; the frame command itself is fixed at
1280×720.

The renderer's own time grew on the software renderer, because every pixel of a baked layer runs
the mask. Before the per-chunk cull it was 38.9 ms against the parent's 14.3 and the
harness-inclusive interval was worse than before (49.1 against 43.5 ms); hiding layers with
nothing to show brought it to 18.5 ms and the interval to 27.8. On a GPU the mask is two texel
fetches a fragment. llvmpipe numbers are not hardware GPU results, as above.

The night, per pixel: plan item A10, 2026-10-19 (`presentation/light_map.gd`,
`night_light.gdshader`; docs/23's record, "Art — the night, per pixel"). The flat night wash and
the per-tile pool rects are replaced by one screen rect with a multiply shader. Each frame the CPU
side builds one RGBA8 texel per tile in view (`LightLook.light_texels`, at most 24 sources); the
shader then makes five texel fetches per fragment and loops over the sources. Measured the same
way as above, on another container (llvmpipe, Intel Xeon @ 2.80 GHz, 1280×720). Night means a
throwaway driver with a carried torch and a lit campfire on the boot scene:

| Stage | Before | After |
|---|---:|---:|
| shipped-draw (day) `_draw` CPU, mean | 13.5 ms | 12.9–14.1 ms |
| shipped-draw (day) RenderServer wall time, mean | 30.2 ms | 44.4–45.0 ms |
| night `_draw` CPU, mean | 20.7–21.7 ms | 17.0–18.3 ms |
| night RenderServer wall time, mean | 37.8–38.8 ms | 52.3–53.5 ms |

The `_draw` stage, which is what the 10 ms target judges, did not grow: by day it is noise, and at
night it fell because the pool rects are gone. On this machine that stage was already over the
target before the slice. The renderer grew by about 14 ms because llvmpipe runs the full-screen
fragment shader on the CPU. **The GPU cost of this shader is unmeasured.** No container here has
a hardware GPU, and CI renders no real frame: `godot:bench:frame` is not in CI, and
`check:runtime-budget` checks the runner's exit contract against fabricated evidence. So this
shader cannot trip a CI budget, and no gate measures its cost. A software-renderer timing gate
would judge llvmpipe rather than the product, so none was added. Measuring on hardware is the open
item.

The art review's revision (2026-10-20: pools bounded by their radius and cut into rings, the
night held at its floor outside them, the light map cleared rather than drawn by day) was measured
against the first cut on a third container (llvmpipe, Intel Xeon @ 2.10 GHz, 1280×720), two runs
each, the same driver and bench:

| Stage | First cut | Revised |
|---|---:|---:|
| shipped-draw (day) `_draw` CPU, mean | 7.45–7.99 ms | 7.42–7.69 ms |
| shipped-draw (day) RenderServer wall time, mean | 25.97–28.18 ms | 16.21–16.86 ms |
| night `_draw` CPU, mean | 10.35–11.58 ms | 10.35–10.91 ms |
| night RenderServer wall time, mean | 31.66–35.06 ms | 32.08–32.76 ms |

By day the shader no longer runs at all, so the renderer is back to its pre-A10 cost; at night the
revision costs the same. The second review's pass (edges faded per tile edge, remembered tiles in
the texels, a darker floor) measured night `_draw` 11.62–13.13 ms and renderer 33.4–36.6 ms in a
session where the untouched day path also read 7.63–9.19 ms: the night-to-day ratio held at about
1.4, so the change is the machine's drift, not the pass's. The GPU cost remains unmeasured, as
above. The third review's pass (an opaque tile behind a window lit only from an open neighbour,
`LightLook._face_lit`) was measured five times interleaved with the commit before it on one
container: night `_draw` median 21.77 ms against 20.91 ms (ranges 20.26–22.24 and 20.64–20.96),
about 0.9 ms at the edge of this bench's noise. A first cut that asked the sim's full sight and
solid predicates per neighbour cost about 2.5 ms and was replaced by the tile-class tables
(`LightLook._open`), which defer to the sim's predicates only where a tile carries an overlay.

**The night's `_draw` stage, measured and closed to the day's (2026-10-24, B1).** `godot:bench:frame`
now commits a `night-draw` sample: the crowd is removed, the survivor carries a hand torch
(`item.torch.handheld`), and a lit campfire four metres off is the second source, at the review
scenes' midnight. Three runs each, llvmpipe, Intel Xeon @ 2.80 GHz, 1280×720, on the same container:

| Sample | Before (median of 3) | After (median of 3) |
|---|---:|---:|
| shipped-draw (day) `_draw` CPU, mean | 10.30 ms (9.66–10.42) | 9.90 ms (9.60–10.92) |
| night-draw `_draw` CPU, mean | 13.94 ms (13.18–14.47) | 10.04 ms (9.84–10.52) |

The profile (throwaway instrumentation, not committed) put the night's extra cost in
`LightLook.light_texels`, 2.5–2.9 ms a frame, rebuilt every frame although its answer is a fact
about the sim, which changes only in `step()`. The light map also re-uploaded its RGBA8 texture
every frame, about 0.5 ms. Both now run once per tick and per view: `main.gd` keys the texels on
(world, tick, eyes, view), and `light_map.gd` skips the upload when the texels are the last
frame's. Night frames that share a tick are byte-identical to before, and the night screenshots
(`night_lights`, 1280×720 and 1920×1080) decode to identical pixels before and after. Left: the
night's `_draw` now costs what the day's does, about 8–9 ms of entity drawing and 2 ms of world
layers on this container, shared with the day. Night is about 0.1–0.3 ms above day, at the edge of
this bench's noise. The 10 ms target is met by the median on this container only because the day
draw sits at it too; a faster container will read lower, and a slower one higher, for both.

**The overcast day grade (2026-10-24, B5).** One more screen-sized pass by day and none at night:
`presentation/day_grade.gd` draws a rect whose shader reads the screen (`hint_screen_texture`),
so the renderer copies the frame once and runs one cheap fragment over it. `_draw` gains one
rect and one uniform. Three runs each, interleaved with the grade switched off
(`DayGrade.enabled`), llvmpipe, Intel Xeon @ 2.10 GHz, 1280×720, on one container:

| Sample | Grade off (median of 3) | Grade on (median of 3) |
|---|---:|---:|
| shipped-draw (day) `_draw` CPU, mean | 5.46 ms (5.21–6.18) | 5.69 ms (5.58–5.83) |
| shipped-draw (day) RenderServer wall time, mean | 16.26 ms (15.62–17.48) | 22.59 ms (22.51–23.30) |
| crowded-draw `_draw` CPU, mean | 153.10 ms | 156.06 ms |
| night-draw `_draw` CPU, mean | 6.23 ms (5.35–6.45) | 5.68 ms (5.26–6.05) |
| night-draw RenderServer wall time, mean | 31.54 ms | 29.80 ms |

The `_draw` stage the budget judges did not move past this bench's noise, and the night did not
move at all (the grade draws nothing there). The cost is on the renderer, by day: about 6.3 ms of
llvmpipe wall time for the screen copy and the pass, which is software rasterising what a GPU does
in a fraction of a millisecond. The GPU cost remains unmeasured, as above. There is no cheaper path that
keeps the look: the night's pass is a `blend_mul` multiply and reads no screen, and a multiply can
darken and tint but cannot pull a colour toward its grey or lift a dark, which the overcast grade
needs; the renderer time was over 10 ms by day before this slice too (16.26 ms here), and the
`_draw` delta is within noise. The crowded sample is over target before and after,
as it was.

### Flat dressing, baked

Plan item A12, 2026-10-20 (`presentation/world_layers.gd`, `presentation/dressing.gd::decor_picks`,
`main.gd::_draw_decor`). The nature pictures and the furnishings left the per-frame draw loop and
bake into a sixth world layer, DECOR, which is LIVE-only: it shows where the sim sees, and it is
culled with its chunk like the seen ground. `decor_picks` answers the picks the per-tile functions
make, each with its offset from the tile's centre and a mirror flag, so a baked picture is the one
the frame would have drawn.

The density came from three places. Furnishing rarities in `content/dressing/street.json` went down
(shelf 4, cabinet 10, table 6, chair 6, dumpster 14, barrier 70, cone 45; post unchanged), and three
pack props joined as scenery: the oil barrel (40), the pallet stack (55) and the rubbish bags (8,
beside a wall or a kerb). The crates, footlockers and medical boxes are container kinds and stay out.
Litter is cut from the pack's `overlay-debris` sheet: since A12's sixth pass a crumpled paper (11x12)
alone, drawn on whole art pixels like everything else, weighted toward walls, kerbs and cluttered
blocks (docs/23's sixth-pass record has the numbers). About one in six of the visible floor on the
review shots; the 64-tile suburb, mostly edge, counts 387 of 2,282 (OCCUPANCY lane). Each picture's extent is content: the block's `sizes`, checked against its authored canvas.

The seventh pass's cost, same machine (a 2.80 GHz Xeon, llvmpipe), alternated with main 9d9bc23:
the world `_draw` mean 9.74 ms before and 9.24 ms after over three runs each (`godot:bench:frame`,
1280x720), the crowded scene 182.6 and 181.7; the tick 11.09 and 10.77 ms over two
(`godot:bench:runtime`). The per-block litter quota and the table's own-chair test are memoised in
the occupancy (`litter_blocks`, `memo`), so they are paid once per map, not per frame.

The sixth pass's cost, same machine, alternated with the fifth: the world `_draw` mean 6.03 ms
before and 6.06 ms after over four runs each (`godot:bench:frame`, 1280x720), the crowded scene 88.6
and 87.7; the tick 7.49 and 7.03 ms over two (`godot:bench:runtime`). The per-room keep and the
room flood fill are memoised in the occupancy, so a room's pieces are ranked once per map.

The fifth pass's cost, same machine, three runs each: the world `_draw` mean 5.82 ms before and
5.94 ms after (`godot:bench:frame`, 1280x720), the crowded scene 87.6 and 87.5; the tick 7.37 and
7.21 ms (`godot:bench:runtime`; nothing under `godot/sim/` changed). The occupancy is built once
per map, seed, content and prop layout (`main.gd::_dressing_occupancy`) and memoises each tile's
raw top, so the bake and the per-frame litter read it rather than recompute it.

The per-tile rolls use `Dressing._mix`, a multiply-xorshift finaliser over the hash: the plain hash's
low bits fell on a lattice, and `godot:check:trees`'s LATTICE lane holds the mixed roll to a near-even
pair count on a 32-square window (250 and 241 against 248 expected; the shifted roll gave 320 and 192).
Every flat picture is placed in whole art pixels: its centre up to six art pixels off the tile's
centre line, its base up to six above the tile's south edge, its left edge on the art grid even when
its width is odd (PLACED lane). About half are mirrored.

Overlap, not one picture to a tile. A tile's raw picture is its furnishing, else its nature picture.
Two pictures whose art rects meet cannot both be drawn: the lower rank gives way (a standing
furnishing over a flat one, a flat one over nature, anything over a scrap), and a tie goes to the
tile whose hash is higher (`Dressing._kept_top`). Every art rect fits within one tile of its own, so
the eight neighbours are the only tiles that can meet it. The rule reads raw neighbours, so a loser
still blocks what lies beside it: that costs a little furniture and keeps every answer local and
pure. OCCUPANCY lane judges it on the suburb: the raw rolls must meet (48 meetings across the three
rules, so each rule has work), no two kept pictures meet, no kept picture sits under a higher raw
one, and no scrap sits on a held tile or in the clearing. The clearing round the colony's start is
four tiles out, so nothing stands within three of it (CLEAR lane, which says so and skips when the raw
roll puts nothing there).

Measured on the round-4 shots with a temporary probe that dumped every drawn picture's rect (deleted
after): no two drawn pictures overlap, none overlaps the survivor's tile, none sits off the art grid.
Street litter is one in 6.0 to 7.0 of the visible paved tiles across the shots; indoor litter one in
6.4 to 9.5 of the visible floor; the day street holds 13 and 22 trash bags. The empty indoor 3x3
windows left are inside the clearing, except two per interior shot.

Measured 2026-10-20 on one container, with `npm run godot:bench:runtime` and
`xvfb-run -a npm run godot:bench:frame` at 1280x720, Godot 4.7.1, X11/Xvfb, llvmpipe (LLVM 20.1.2,
256 bits), Intel Xeon @ 2.10 GHz. The base is the parent commit 75ce22a, which already carries the A4
bake. The third-pass numbers were two runs each, base and change alternated; the fourth pass is one
run, because the container was busy with the full gate chain otherwise.

| Measure | Base, runs | Base mean | Third pass, runs | Third pass mean | Fourth pass, one run |
|---|---|---:|---|---:|---:|
| shipped-tick, mean ms | 9.85, 9.63 | 9.74 | 10.03, 8.89 | 9.46 | 9.80 |
| shipped-tick, worst (max) ms | 23.7, 25.0 | — | 24.6, 24.5 | — | 27.4 |
| shipped-draw `_draw` CPU, mean ms | 9.43, 9.61 | 9.52 | 8.49, 7.37 | 7.93 | 7.36 |
| crowded-draw `_draw` CPU, mean ms | 126.8, 130.5 | 128.7 | 122.7, 122.3 | 122.5 | 121.7 |

Shipped-draw is the budget that applies to the frame (10 ms mean at 1280x720), and it is under it.
Crowded-draw is a stress scene and misses 10 ms before and after. The tick misses its 8 ms mean and
16 ms worst before and after, and its runs move both ways with no `godot/sim/` change: the
difference is the container's spread, not a speed-up.

Trade-offs: the prop-occupancy skip left the bake, so a furnishing can show around a crate or a
bed where a prop stands, and a prop placed after its chunk is baked shows the picture at its edges
until the chunk rebakes. The street and the room sit in the same bake. The harness's `day_street`
moves the survivor to the nearest open paved street tile whose 21 x 11 surroundings are at least 75
percent paved outdoor street and whose 3 x 3 ring holds no picture, then snaps the camera to the survivor (`_snap_camera`); before, the
shot photographed the room the survivor starts in, and the follow lerp left the survivor off centre.
The interior camera sits on an odd x in both the before and after shots. That predates this work and
is left as it is. `godot:check:trees` (`TREES_OK`, with its OCCUPANCY lane) holds the layer order,
the picks, the roll, the clearing, the occupancy and the placement fields, and
`godot:check:world_bake` (`WORLD_BAKE_OK`) holds the DECOR rebake and mask rule.

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
