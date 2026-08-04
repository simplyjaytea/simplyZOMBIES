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

## Milestone 3 — Depth

Only if Milestone 2 answers the thesis affirmatively.

Weather · the full decay clock and mutation waves · the remaining zombie types (screamer first — it's
the most interesting object in [that document](14-zombies.md)) · the full skill web · named items and
unique survivors · relationships and grief · temperature and hygiene · the remaining modification
consumables · more traps and bait · procedural map generation.

## Milestone 4 — Breadth

Factions ([the whole document](18-factions.md)) · the escape endgame · storyteller presets and the
full sandbox layer · the balance harness at scale · content volume.

---

## Risks

The design's live problems, stated plainly. Each has a checkpoint where we find out.

### 1. The micromanagement cliff — *highest risk*
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

### 5. Attention field performance
Continuous scent diffusion is the [most likely thing to need rework](22-performance.md).

**Checkpoint:** Milestone 1, under a synthetic 500-zombie load.

### 6. Melee/ranged parity may not survive contact
The [contract](09-combat.md) is elegant on paper. Elegant-on-paper parity usually collapses in
playtesting.

**Checkpoint:** Milestone 2, using the [balance harness](19-architecture.md) — thousands of headless
runs measuring whether melee-only and ranged-only colonies both survive comparably.

## Open questions

Deliberately unresolved, to be answered by playing rather than arguing:

- **How long is a day, really?** Four hours at 1× is a guess.
- **How lethal is *too* lethal?** [The contract](01-hardcore-contract.md) says three zombies is
  probably fatal. That may be one too few or one too many.
- **Does succession feel like continuity or like a consolation prize?**
- **Is the skill web earning its complexity** on top of gear-as-build, or should progression be
  purely items after all?
- **Should the map be hand-authored or procedural?** The slice uses hand-authored. Procedural is more
  replayable and much more expensive.
- **How rare should recruits be?** Too rare and the colony never grows; too common and risk #2 lands.

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
