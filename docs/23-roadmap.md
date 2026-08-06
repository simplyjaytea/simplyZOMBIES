# 23 — Roadmap

*Why this exists: the preceding 23 documents describe a game far larger than a first build. This one
says what actually gets made, in what order, and admits what might be wrong.*

---

## It's a lot. We know.

This document set is a **backlog, not a promise**. Written down, the design is:

> A hardcore survival colony sim with tower defense, a procedural survivor generator, a
> Path-of-Exile-shaped item system, a classless skill web, an injury model, an infection model with
> diagnostic uncertainty, weather, an AI director, factions, and world decay — in a browser.

That is several years of work as specified. The response isn't to cut the vision; it's to build a
**vertical slice** that proves the thesis, then decide what's worth expanding based on whether the
slice is fun.

## The thesis to prove

Everything in the slice exists to test one claim:

> **A player managing the [attention field](03-attention.md) — trading comfort for safety, day after
> day, with people they've invested in and can permanently lose — is doing something fun.**

If that's true, the rest of the design is worth building. If it isn't, no amount of factions and
weather will save it.

## Milestone 0 — Foundations

The [architecture](19-architecture.md) work with no game on top.

- Fixed-timestep tick loop, seeded RNG, plain serializable state
- Minimal ECS: entities, components, ordered systems ([ECS & content](20-ecs-and-content.md))
- Event bus and modifier pipeline ([extensibility](21-extensibility.md))
- Content registry with schema validation, loading from directories
- Canvas renderer reading sim state; input via a command queue
- Save/load with a version stamp and clean rejection of stale saves
- **CI: determinism test, module-isolation boot test, lint rules enforcing `sim/` purity**

**Exit criterion:** an entity moves around a tile map, deterministically, and the same seed plus
inputs reproduces it byte-identically.

## Milestone 1 — The spine

The [attention field](03-attention.md) and something that reacts to it.

- Three-channel field on a coarse grid, with emit, propagate, and decay
- Shamblers performing gradient ascent
- One controlled survivor with direct movement
- Melee combat: swing, stagger, grab, stamina
- Day/night cycle
- Debug overlay for all three channels

**Exit criterion:** make noise, and they come. Go quiet, and they don't. This is the first moment the
game is legible as a game.

## Milestone 2 — The vertical slice

Everything needed to test the thesis, and nothing else.

| System | Slice scope |
|---|---|
| **Map** | One hand-authored map: a small district with a defensible building |
| **Survivors** | The [generator](07-survivors.md) with a small name/trait/backstory pool; ~3 recruitable |
| **Work** | Four jobs: Haul, Construct, Cook, Doctor |
| **Needs** | Hunger, thirst, rest, mood. *(Temperature and hygiene deferred.)* |
| **Health** | **Full [injury model](05-health-injury.md)** — it *is* the hardcore thesis |
| **Infection** | **Full, including [diagnostic uncertainty](06-infection.md)** — same reason |
| **Zombies** | Shamblers only |
| **Combat** | Melee and ranged, both, with the [parity contract](09-combat.md) live |
| **Items** | ~12 bases across melee and ranged; ~10 affixes; 3 tiers; attachment slots on 2 classes |
| **Crafting** | Two modification consumables: **Duct Tape** and **Scrap Kit** |
| **Web** | Stub: one melee branch, one ranged branch, ~12 nodes |
| **Building** | Walls, a gate, barricades, one trap, one bait emitter |
| **Decay** | Food spoilage only |
| **Director** | Full — pacing is what makes a slice feel like a game rather than a sandbox |
| **Death** | **Succession** ([hardcore contract](01-hardcore-contract.md)) |
| **Resources** | ~15 resource types, 3 location loot tables |

**Explicitly not in the slice:** weather, factions, the full decay clock, mutation waves, temperature,
hygiene, relationships, unique survivors, named items, the full web, most zombie types, the escape
endgame.

**Exit criterion:** a player survives ten in-game days, loses someone they cared about, and wants to
start again.

## Milestone 3 — Depth and range

Only if Milestone 2 answers the thesis affirmatively.

**Depth:** weather · the full decay clock and mutation waves · the remaining zombie types (screamer
first — it's the most interesting object in [that document](14-zombies.md)) · the full skill web ·
named items and unique survivors · relationships and grief · temperature and hygiene · the remaining
modification consumables · more traps and bait.

**Range** — the [world](24-world-and-scale.md), [vehicles](25-vehicles.md), and
[mobile bases](26-mobile-bases.md), in this order, because each depends on the last:

1. **World scale first.** The continuous region, district types, the road graph, procedural assembly
   from authored templates, district-tier simulation, and streaming. Vehicles are pointless without
   somewhere to drive, and this is the larger and riskier half.
2. **The drive benchmark before the vehicles.** Per
   [the performance pillar](22-performance.md#the-ci-benchmark-suite), the streaming-at-speed scenario
   is written and running against synthetic load *before* a drivable vehicle exists. Finding out the
   region isn't affordable is much cheaper now than after building three documents' worth of systems
   on top of it.
3. **Vehicles.** Bases, slots, affixes, driving, fuel, breakdowns, route trails, and the attention
   emissions that make an engine the loudest thing in the game.
4. **Mobile bases and nomad play.** Interior modules, volume budgeting, convoys, relocation, and the
   long-expedition mode where NPCs run the colony in your absence.

## Milestone 4 — Breadth

Factions ([the whole document](18-factions.md)) · the escape endgame · storyteller presets and the
full sandbox layer · the balance harness at scale · content volume.

---

## Risks

The design's live problems, stated plainly. Each has a checkpoint where we find out.

### 1. The micromanagement cliff — *highest design risk*
Unlimited survivors × affixed gear × a skill web is a lot of interface. The
[Focus auto-allocation system](07-survivors.md#focus-and-auto-allocation-the-anti-micromanagement-rule)
is the mitigation, and it's a design constraint rather than a solved problem.

**Checkpoint:** Milestone 2, with 6+ survivors. If playing on full auto isn't viable, the item and web
systems need shrinking, not the UI needs improving.

### 2. Unlimited survivors may undercut permadeath
The counterweight — recruits arrive as [worthless nobodies](07-survivors.md) — is a theory. If players
treat survivors as ammunition, [infection](06-infection.md) loses its teeth and the emotional core of
the game goes with it.

**Checkpoint:** Milestone 2. Watch whether players quarantine or just execute. Universal execution
means the investment curve is too shallow.

### 3. Unscheduled hordes may starve the tower defense half
[No wave timer](02-core-loop.md) is right for tension and might mean the elaborate
[base building](15-base-building.md) system rarely gets tested by anything.

**Checkpoint:** Milestone 2. If sieges are too rare to justify building, the [director](17-director.md)
needs to guarantee a minimum siege cadence — a change to pacing, not to the attention model.

### 4. ECS plus a modifier pipeline may be over-engineering for a slice
Real risk of spending Milestone 0 on architecture for a game that turns out not to be fun.

**Mitigation:** Milestone 0 is deliberately small — the minimum ECS, not a good one. The bet is that
this design *will* keep changing, and it has already changed four times, so the bet looks sound.

**Checkpoint answered — see [spike findings](#spike-findings-attention-field) below.** A throwaway
prototype ran the thesis before any architecture existed. The mechanic works; two tuning problems
surfaced that would have been much more expensive to find later.

### 5. Attention field performance
Continuous scent diffusion is the [most likely thing to need rework](22-performance.md).

**Checkpoint:** Milestone 1, under a synthetic 500-zombie load.

**Partially answered.** Event-driven *noise* propagation plus gradient ascent is effectively free —
0.13 ms average sim at 1,560 zombies, two orders of magnitude inside the 8 ms budget, with rendering
dominating instead. **Scent remains untested**, and scent is the continuous channel this risk actually
names. The measurement below narrows the risk; it does not close it.

Scent now carries a second question as well as its cost. Because
[field memory is a scent mechanic](03-attention.md#field-memory-is-a-scent-mechanic) and the spike
could only test it on noise, the Milestone 1 scent work has to answer *does residue do anything
observable* at the same time as *what does diffusion cost* — one build, two checkpoints.

---

## Spike findings: attention field

A disposable prototype (`spike/`, and not part of the real build) tested the core thesis — *make noise
and they come, go quiet and they don't* — before Milestone 0. One noise channel, shamblers, a tile map,
and nothing else. Measured in Chromium at 1280×800.

**All three problems below are now folded into the documents that specify the systems.** The findings
are kept here because they are the evidence; the specifications are the authority:

| Finding | Resolution | Specified in |
|---|---|---|
| Conga lines | Persistent per-individual angular bias, ±0.62 rad | [14 — Zombies](14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own) |
| Noise not calibrated to district size | District pinned at 256 m; magnitudes unchanged, the *unit* supplied | [03 — Attention](03-attention.md#scale-and-calibration), [24 — World & Scale](24-world-and-scale.md#how-big-a-district-is) |
| Field memory a no-op | Respecified as scent-only at a magnitude that propagates; verified at Milestone 1 | [03 — Attention](03-attention.md#field-memory-is-a-scent-mechanic) |
| Rendering dominates simulation | Draw budget added; every benchmark asserts frame time | [22 — Performance](22-performance.md#aim-the-budgets-at-the-renderer) |

### It works

Convergence on a noise event is **legible with the debug overlay off**. Zombies visibly stream in from
across the district and the ones outside the radius carry on wandering. The core mechanic reads.

*Caveat:* the spike colour-codes zombies by AI state, which flatters legibility. What carries it
without that crutch is the *direction of travel* being obviously coordinated — which is a real
property, not a debug affordance.

### Problem 1 — gradient ascent produces conga lines, not a horde

Every zombie in a given field cell picks the same one of eight neighbours, so they collapse into
single-file queues along the steepest path. It reads as ants on a pheromone trail rather than a crowd
of the dead.

**Fixed, at zero cost.** A persistent per-individual angular bias (±0.62 rad) applied to the gradient
direction fans them into a broad convergence. Sim cost was 0.04 ms without and 0.05 ms with; the seek
count was unchanged. The fix needs no neighbour queries, so it survives contact with
[the horde counts in performance](22-performance.md).

**Resolved:** [zombies](14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own) now specifies it,
including that the bias comes from the seeded RNG stream and belongs in save state.

### Problem 2 — the noise magnitudes are not calibrated to district size

A single 120-magnitude shout floods an entire 80×80-tile district and stays audible for over thirteen
seconds. Buildings barely cast a noise shadow, because propagation simply routes around them along the
streets.

This is a **calibration** problem, not a model problem, and it landed directly on the open question
*"how big is a district, in metres?"*

**Resolved, and the diagnosis turned out to be narrower than it looked.** The magnitude table was
never wrong — its *ratios* are load-bearing design, quoted across six documents. What was missing was
the **unit**: nothing had ever defined metres per tile or attenuation per metre, so the spike picked a
constant arbitrarily (2.0 per tile, about 3× too steep) and ran it in a district that was 80 m across
when a shout carries 171 m.

Supplying the unit fixes it with **zero changed magnitudes**: 1 tile = 1 m, 0.7 attenuation per metre,
4 m field cells, and a **256 m district** — chosen so that one unsuppressed gunshot (257 m) equals
exactly one district. See [scale and calibration](03-attention.md#scale-and-calibration) and
[how big a district is](24-world-and-scale.md#how-big-a-district-is). Linear falloff is kept; it is
what makes propagation cost bounded by magnitude.

### Problem 3 — field memory is currently a no-op

Milling bodies emitting residue is [specified](03-attention.md) but, at the magnitudes given, residue
never propagates past its own cell — the emission is smaller than one cell of falloff. Toggling it off
changes nothing observable.

**Resolved, and the spike was testing the wrong channel.** Both specifying documents describe field
memory as **scent** — bodies leaving their smell behind, decaying over hours. The spike has no scent
channel, so it implemented residue as *noise*, where an emission of 5 against a per-cell falloff of 4
dies inside its own cell by arithmetic. The null result is real but it is a property of the
substitution, not of the mechanic.

[Attention](03-attention.md#field-memory-is-a-scent-mechanic) now states that residue writes to scent
and never to noise, at a magnitude above the propagation floor. It remains **unverified** — scent has
never been built — so Milestone 1 carries an explicit acceptance check: toggle residue off, and if
nothing observable changes, cut it.

### Performance

| Scenario | Zombies | Sim avg / p95 | Frame avg | Field cells live |
|---|---|---|---|---|
| Idle, quiet | 60 | 0.01 / 0.10 ms | 2.10 ms | 0 |
| Idle, quiet | 560 | 0.06 / 0.20 ms | 2.60 ms | 6 |
| After a shout | 560 | 0.07 / 0.30 ms | 3.71 ms | 1,112 |
| After a shout | 1,560 | 0.13 / 0.50 ms | 3.68 ms | 1,112 |

Two things worth carrying into Milestone 1:

- **Quiet genuinely costs nothing.** Six live field cells at rest. The event-driven design for noise is
  vindicated.
- **Rendering dominates, not simulation.** Sim is ~0.1 ms while draw is ~3 ms.

**Resolved:** [performance](22-performance.md#aim-the-budgets-at-the-renderer) now carries a draw
budget and a sim-share-of-frame budget, every benchmark scenario asserts frame time as well as tick
time, and *Quiet night* was tightened from `≤2 ms tick` — a budget the measured 0.01 ms could have
regressed 200× without failing.

### Not answered

- **Is quiet *tense*, or just slow?** This needs a human playing, not a measurement. With noise as the
  only channel, being quiet is completely safe — which is the design working as specified, and also the
  strongest argument that **scent is not optional**. Perfect safety through stillness is a boring
  equilibrium, and scent is what makes hiding imperfect.
- **Scent cost.** Untested, and it is the continuous channel risk 5 is actually about.

### 6. Melee/ranged parity may not survive contact
The [contract](09-combat.md) is elegant on paper. Elegant-on-paper parity usually collapses in
playtesting.

**Checkpoint:** Milestone 2, using the [balance harness](19-architecture.md) — thousands of headless
runs measuring whether melee-only and ranged-only colonies both survive comparably.

### 7. Streaming a continuous region at driving speed — *highest engineering risk*
The design commits to one continuous [drivable world](24-world-and-scale.md) with no abstracted travel.
In a browser, promoting a district into existence while the player drives into it at 60 km/h — with a
horde possibly loaded behind — is **the hardest engineering problem in the design**. The mitigations
(road-topology prefetch, staged promotion, a load-tied speed cap) are designed but unproven.

**Checkpoint:** Milestone 3, step 2 — the drive benchmark runs against *synthetic* load before any
vehicle exists. If it can't hold 60 fps, the honest options are a smaller region or abstracted travel
legs between districts, and both are much cheaper to accept before vehicles are built than after.

### 8. Full nomad viability roughly doubles the balance surface
Making a [convoy](26-mobile-bases.md) a genuine alternative to a fixed colony means every system needs
a nomad answer: what [world decay](13-world-decay.md) means to someone with no farm, what the
[director](17-director.md) paces against a colony with no walls, whether "just drive away" becomes the
correct response to everything.

The design's answer is that the two playstyles have **opposite failure modes** — fixed colonies die to
sieges and mutation, nomads die to fuel and attrition. That's a theory until it's measured.

**Checkpoint:** Milestone 3, step 4 — run the balance harness on nomad-only, fixed-only, and hybrid
colonies. If nomads dominate, fuel scarcity and the attrition tax are undertuned. If they're
unplayable, the failure modes are stacked rather than parallel.

## Open questions

Deliberately unresolved, to be answered by playing rather than arguing:

- **How long is a day, really?** Four hours at 1× is a guess.
- **How lethal is *too* lethal?** [The contract](01-hardcore-contract.md) says three zombies is
  probably fatal. That may be one too few or one too many.
- **Does succession feel like continuity or like a consolation prize?**
- **Is the skill web earning its complexity** on top of gear-as-build, or should progression be
  purely items after all?
- **Should the map be hand-authored or procedural?** The slice uses hand-authored; the
  [region](24-world-and-scale.md) uses authored templates in a procedural layout. Whether that hybrid
  holds up is a Milestone 3 question.
- **How rare should recruits be?** Too rare and the colony never grows; too common and risk #2 lands.
- **Does a mobile base make the fixed colony feel like a burden?** If the honest answer after
  Milestone 3 is "just drive away," risk #8 has landed.

**Answered since this list was written:** *how big is a district, in metres?* — 256 m, forced by the
noise calibration above and recorded in
[world & scale](24-world-and-scale.md#how-big-a-district-is).

## Definition of done for the doc set

The verification criteria this document set is checked against:

1. Every document has substantive content and a cut list.
2. Every cross-document link resolves.
3. The [cookbook examples](21-extensibility.md#the-cookbook) are achievable using only mechanisms
   these documents define.
4. No document contradicts the [vision](00-vision.md) or the
   [hardcore contract](01-hardcore-contract.md).

---

**Previous:** [22 — Performance](22-performance.md) · [Doc index](../README.md#documentation)
