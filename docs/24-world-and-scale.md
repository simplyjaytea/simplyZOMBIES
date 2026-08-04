# 24 — World & Scale

*Why this exists: the moment [vehicles](25-vehicles.md) exist, "how big is the world and how do you
move across it" stops being an implementation detail and becomes a design question. Nothing else in
this set answered it. This document does.*

---

## The region

The world is **one continuous coordinate space** — a region of 9–16 districts joined by a road
network. No loading screens, no travel menus, no abstracted legs. You can drive from your gate to the
far edge of the map without the simulation handing off to a different representation.

That is an expensive choice, and it's the one the whole
[performance pillar](00-vision.md#the-six-pillars) exists to pay for.

```
    ┌────────┬────────┬────────┐
    │ farm   │ suburb │ suburb │      ~9-16 districts
    ├────────┼────────┼────────┤      one continuous space
    │ suburb │  town  │ retail │      roads are the spine
    ├────────┼────────┼────────┤
    │ indust │ hosp.  │ mil.   │      danger rises with distance
    └────────┴────────┴────────┘         from wherever you started
```

## District types

Each district is a loot profile, a danger profile, and a shape. They map onto the
[location types in the resource economy](12-resources.md#3-scavenged-finite-risk-gated-off-site).

| District | Character | Yields |
|---|---|---|
| **Residential suburb** | Open, low density, many small interiors | Canned food, cloth, tools, duct tape |
| **Town center** | Dense, narrow streets, terrible sightlines | Mixed; the best early trade in risk for reward |
| **Retail strip** | Big open floors, nowhere to hide, big hauls | Bulk food, clothing, sporting goods |
| **Industrial park** | Cramped, dark, loud, machinery | Scrap, parts, **fuel**, electronics, scrap kits |
| **Hospital campus** | Dense interiors, and everybody died there | **Antibiotics**, surgical kits, sterile supplies |
| **Military depot** | Fenced, defensible, and full of what killed the garrison | Firearms, **ammo**, armor, optics |
| **Farmland** | Open, quiet, defensible, poor loot | Seeds, livestock, fuel from farm equipment |

**Design rule:** danger correlates with yield, never with your power level. A military depot is
equally lethal on day 3 and day 300. What changes is whether you have a reason to go.

## Generation

**Authored templates, procedurally assembled.** Building footprints and interiors are hand-made — a
procedurally generated house interior reads as noise, and interiors are where the game happens.
District layouts and the region's road graph are generated from the world seed.

So: the *buildings* are designed, the *world* is rolled. A region is reproducible from its seed, which
[determinism](19-architecture.md#determinism) requires anyway.

## Roads

Roads are the region's spine, and they carry more design weight than their footprint suggests:

- **The travel surface.** Off-road is slow, damaging, and impassable for most
  [vehicle bases](25-vehicles.md).
- **Where the vehicles are.** Every wreck is a potential chassis or a parts donor.
- **Where noise carries.** Long, straight, hard-surfaced corridors propagate
  [noise](03-attention.md) much further than built-up terrain.
- **Where [factions](18-factions.md) move.** Traders and raiders use roads too, so roads are where you
  meet people.
- **Blockable.** Wrecks, collapses, and jams close routes. Clearing one needs a winch, or manual work
  (loud, slow, exposed), or a detour that costs fuel and daylight.

Road blockages are the mechanism that keeps a "solved" region from staying solved — combined with
[world decay](13-world-decay.md), your known-good route home has an expiry date.

## Route trails

A concept the attention field gains once vehicles exist.

A vehicle driving through leaves a **decaying corridor of noise and scent** along its exact path. It
fades over hours. Two consequences:

1. **[Trackers](14-zombies.md) follow it home.** A route trail leading from a hospital campus to your
   gate is an arrow pointing at everything you own.
2. **Taking a different route back stops being flavor** and becomes basic discipline — the vehicular
   equivalent of light discipline at dusk.

Trails are stored on the road graph rather than the fine field, which keeps them cheap.

## Simulation tiers by distance

Extends the [tiered simulation model](22-performance.md#the-core-idea-tiered-simulation) with a fourth,
coarsest tier:

| Tier | Scope | What runs |
|---|---|---|
| **Detailed** | Your immediate surroundings | Full ECS — pathing, combat, grabs, per-part damage |
| **Coarse** | Rest of the loaded district | Position, gradient following, aggregate health |
| **Abstract** | Neighboring districts | Hordes as single entities with a position and a count |
| **District** | Everywhere else | **No entities at all.** A population number, a depletion state, a faction presence, a threat level. |

District tier is what makes a continuous region affordable. A district you haven't visited in three
weeks is six numbers, and it resolves into a world when you drive into it — deterministically, from
the seed, so it's the same world every time.

### Promotion at speed

The hard case: driving at 60 km/h means promoting a district from six numbers to a populated world
*while the player is already moving into it*. Handled by:

- **Prefetch along road topology**, not a radius — travel follows roads, so the next chunks are
  predictable from the road graph and your velocity vector
- **Staged promotion** across several ticks, beginning well before contact
- A **speed cap tied to load state** — if streaming can't keep ahead, the vehicle can't accelerate
  further. Diegetic, and it means the frame never dies for the sake of the throttle.

## Distance and the expanding radius

[World decay](13-world-decay.md) pushes your viable scavenging radius outward as sites deplete. In a
one-district world that's a slow strangulation. In a region, it's a reason to drive.

```
week 1    on foot, 200m           ████░░░░░░░░░░░░░░░░
week 6    on foot, 800m           ░░░░████░░░░░░░░░░░░
week 12   vehicle, next district  ░░░░░░░░████░░░░░░░░
week 20   vehicle, far region     ░░░░░░░░░░░░████░░░░
week 30+  relocate, or nomad      ░░░░░░░░░░░░░░░░████
```

**Fuel bounds the whole thing.** The region is large enough that you can never strip it, but
[fuel](12-resources.md) is finite and industrial-only — so your real radius is not how far the roads go,
it's how far you can afford to go and still get back.

That's the constraint that keeps a drivable region from trivializing scarcity.

## Base siting, revisited

[Choosing where to settle](15-base-building.md#base-siting) gains a regional dimension: road access,
distance to each district type, defensibility of approach roads, and whether you sit on a route others
use. A base with excellent walls at the end of the only road into a district is both very safe and very
findable.

**Relocation** becomes practical rather than theoretical once you can move your things — see
[mobile bases](26-mobile-bases.md).

## Content shape

District templates, building footprints, road-graph generation rules, and district type definitions are
JSON ([content](20-ecs-and-content.md)). A district template declares its type, footprint pool, density,
loot table reference, and road connection points.

**Adding a district type is a data entry** plus its loot table. Adding new buildings is authoring
footprints, no code.

## Cut list

- **Multiple regions / a world map above the region.** One region is already a large content and
  performance commitment.
- **Procedurally generated building interiors.** Authored only — generated interiors read as noise, and
  interiors are where the game happens.
- **Seasonal or dynamic terrain change** (flooding, collapse). Post-1.0.
- **Fast travel of any kind.** Contradicts the whole reason for choosing a continuous world.
- **Underground layers / sewers / metro.** Tempting, doubles the navigation problem, deferred.

---

**Previous:** [18 — Factions](18-factions.md) · **Next:** [25 — Vehicles](25-vehicles.md) ·
[Doc index](../README.md#documentation)
