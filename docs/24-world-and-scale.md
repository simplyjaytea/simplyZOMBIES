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

### How big a district is

Previously an open question, and everything here was sensitive to it. Settled by the
[attention spike](23-roadmap.md#spike-findings-attention-field), which needed a real number to
calibrate noise against:

| | |
|---|---|
| **District** | **256 × 256 m** (1 tile = 1 m; 64 × 64 [field cells](03-attention.md#scale-and-calibration)) |
| **Between districts** | **300–500 m of road**, not a shared edge |
| **Region span** | ~1.7 km (3×3) to ~2.2 km (4×4) |

The number came from the noise ladder: an unsuppressed firearm carries 257 m, and *one gunshot equals
one district* is the relationship the whole [attention design](03-attention.md) is built on. A
generator's 64 m is then a quarter-radius beacon, and an
[engine's](25-vehicles.md) 171–314 m covers most of a district continuously — which is exactly the
claim that vehicles are the loudest thing you own.

**Districts do not touch.** That matters more than it looks. Packed edge-to-edge, a 3×3 region would
span 768 m — and the radius diagram below has the player walking 800 m by week 6, so they would have
covered the entire region on foot before ever needing a vehicle. Connecting road stretches of
300–500 m put the region at 1.7–2.2 km, which restores the progression *and* gives
[road blockages](#roads), [route trails](#route-trails), and roadside wrecks somewhere to live. A
gate-to-far-edge drive is then roughly two minutes at 60 km/h.

**The content cost is the footprints.** At suburban density a 256 m district holds **~40–70
buildings**. Since [interiors are authored, never generated](#generation), that pool — shared across
districts with rotation and variation — is the real per-district cost, not the district definition
itself. Worth remembering when [content shape](#content-shape) says adding a district type is a data
entry: the type is, the buildings aren't.

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

## The ground

**Built.** A tile has two independent stories: what is *in* it, which the
[occluder classes](28-visibility-and-sightlines.md#what-blocks-sight) answer, and what is *under*
it, which is this. Two arrays, never one enum — a tree stands on grass, rubble lies on tarmac, and a
single enum expressing every combination would be a product of two sets rather than a list. It is
the same lesson doc 28 learned about opacity and solidity, applied one layer down.

The ground answers two questions the simulation already asks every tick, and both of them were
promised in [Roads](#roads) below before any of it existed:

| Surface | Speed | Footstep noise | What it is |
|---|---|---|---|
| **Paved** | ×1.0 | ×1.0 | Tarmac, concrete, floorboards. The baseline |
| **Dirt** | ×0.95 | ×0.85 | Worn earth, the trodden edge of a green |
| **Grass** | ×0.9 | ×0.6 | Lawns, verges, playing fields |
| **Undergrowth** | ×0.6 | ×1.3 | Brambles and long grass. Always under [screening](28-visibility-and-sightlines.md#what-blocks-sight) |
| **Rubble** | ×0.7 | ×1.7 | Spill from a frontage. Always under [low cover](28-visibility-and-sightlines.md#what-blocks-sight) |

**Noise is the half that makes this a mechanic rather than a texture.** Against the
[emitter table](03-attention.md#noise), the same walk carries 1.4 m on tarmac, 0.9 m on grass and
2.4 m across rubble — and a *sprint* across rubble carries 14.6 m, which is most of a street. The
street is the fast way and it announces you; the green is slow and it hides you. **A route is a
decision about the attention field, in exactly the way a
[stance](29-movement-and-stances.md) is.**

Two rules keep it from becoming a free lunch:

- **The ground multiplies the emitter; it never replaces it.** Sprinting stays six times a walk on
  every surface. Terrain modulates a calibrated table rather than overriding it, so docs/03 goes on
  meaning what it says.
- **Nothing may be strictly better than anything else** (docs/29's rule). Undergrowth is the only
  cover on open ground — it breaks a sightline — and it is *both* the slowest surface and a loud
  one. You can be unseen or you can be unheard. The ground makes you choose.

Trees are a solid, opaque tile standing on grass, so a stand of them breaks a sightline down a
street the way a building does — which is what gives a district somewhere to be that is neither
indoors nor exposed.

## Roads

Roads are the region's spine, and they carry more design weight than their footprint suggests:

- **The travel surface.** Off-road is slow, damaging, and impassable for most
  [vehicle bases](25-vehicles.md). **On foot this is built** — see [the ground](#the-ground). For
  vehicles it waits on vehicles.
- **Where the vehicles are.** Every wreck is a potential chassis or a parts donor.
- **Where noise carries.** Long, straight, hard-surfaced corridors propagate
  [noise](03-attention.md) much further than built-up terrain — **also built**, from the emitting
  end: a footstep on tarmac is emitted at full magnitude and one on grass at 0.6 of it. The spike confirmed the mechanism from
  the other direction: noise floods *around* buildings through open ground rather than being stopped
  by them, so **streets are noise highways** and a building shadows much less than its footprint
  suggests. Street layout is therefore an attention-design decision, not just a navigation one.
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
week 1    on foot, 200m           ████░░░░░░░░░░░░░░░░   most of your own district
week 6    on foot, 800m           ░░░░████░░░░░░░░░░░░   your district and its neighbours
week 12   vehicle, next district  ░░░░░░░░████░░░░░░░░   across a road stretch
week 20   vehicle, far region     ░░░░░░░░░░░░████░░░░   the 2 km corner
week 30+  relocate, or nomad      ░░░░░░░░░░░░░░░░████
```

Read against [the numbers above](#how-big-a-district-is), that progression is what the region has to
be sized for: week 1 is one district, and week 20 is the far corner of sixteen.

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
