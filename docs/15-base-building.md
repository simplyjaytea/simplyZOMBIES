# 15 — Base Building

*Why this exists: this is the tower defense half. But because [zombies ascend a stimulus
gradient](03-attention.md) rather than walking a fixed path, defense here is about **steering** rather
than blocking — which makes it a more interesting problem than a maze.*

---

## Design rules

1. **Structures are defensive engineering, not decoration.** Every buildable earns its place by
   changing how the horde moves or how long people survive.
2. **Nothing is permanent.** Everything degrades from use, weather, and time
   ([world decay](13-world-decay.md)).
3. **You cannot wall your way to safety.** Walls buy time and shape approach. A sufficient crowd gets
   through anything.
4. **Building is loud.** Construction is 30 noise, sustained, all day. Fortifying is itself a risk.
5. **The best defense writes to the attention field**, not just to the map.

## Steering, not blocking

In a normal tower defense, enemies path from A to B and you build a maze. Here, they walk *up a
gradient* — so the actual skill is arranging your emissions and your geometry so that pressure arrives
where you want it.

```
        ✗ NAIVE                          ✓ DESIGNED

   [ ~~~ noise ~~~ ]              [ quiet, dark, downwind ]
   ████████████████              ████████░░░░░░░░████████
   █   generator  █              █                      █
   █   kitchen    █              █   traps ▓▓▓  ← bait ●
   ████████████████              ████████░░░░░░░░████████
                                          ↑
   pressure hits everywhere        pressure funnels here,
   including the food stores       into the prepared ground
```

The tools for this are: **geometry** (walls, gates, chokepoints), **emission placement** (put the loud
things where you want them to come), and **bait** (deliberate emitters away from the base).

## Structures

### Walls and barriers

| Structure | Material | Notes |
|---|---|---|
| **Scrap barricade** | Wood, nails | Fast, cheap, weak. Rots in rain. The week-one answer. |
| **Timber wall** | Planks | The working standard. Needs upkeep. |
| **Reinforced wall** | Planks + scrap metal | Slow, expensive, holds against [heavies](14-zombies.md) |
| **Stone wall** | Stone | Excellent, extremely slow to build — a months-long project |
| **Gate** | Varies | The necessary weak point. Every base has one and it's always where the trouble is. |
| **Window barricade** | Wood | Cheap; also **blocks light emission**, which is half its value |
| **Watch platform** | Timber | Elevation: better sightlines, better ranged accuracy, safe from grabs |

**Structures do not have health bars** ([hardcore contract](01-hardcore-contract.md)). They show
damage: intact → scratched → splintering → gaps → breach. A survivor with Craft skill reads the state
accurately; anyone else guesses.

### Traps — the tower defense proper

| Trap | Effect | Cost |
|---|---|---|
| **Spike pit** | Damages and immobilizes; silent | Wood, dig time; must be re-set |
| **Caltrops** | Slows and damages locomotion; silent | Scrap; scattered, cheap, recoverable |
| **Snare line** | Immobilizes for melee cleanup; silent | Cordage; re-set after each catch |
| **Deadfall** | Heavy damage in a chokepoint; **loud** | Timber, mechanism; single-use |
| **Alarm line** | No damage — wakes the colony early | Cordage, tin; cheap and invaluable |
| **Fire trap** | Very effective, **massive light and noise** | Fuel — and fire spreads |

Traps are **consumable infrastructure**. Every one that fires needs re-setting, which is a dawn job,
which is labor, which competes with repairs and hauling. A well-trapped approach is a standing daily
cost.

### Bait — writing to the field on purpose

The signature mechanic, and the reason this isn't just a wall game.

| Emitter | Channel | Notes |
|---|---|---|
| **Wind-up noisemaker** | Noise | Runs for a set duration, then needs winding — someone has to go out and do that |
| **Timed lamp** | Light | Fuel or battery cost; extremely effective at night |
| **Hung carcass** | Scent | Slow, wide, long-lasting pull. Cheap if you have meat you can spare. |
| **Decoy fire** | All three | Very strong, very expensive, and you must be certain of the wind |

Placed 150–300m out, correctly downwind, bait collects the drift and buys a quiet night. It costs
resources, it must be maintained, and **placing it means going out there** — usually at dusk, which is
exactly when you don't want to be outside.

Bait is also how you *aim* a siege: pull the pressure onto the approach where your traps and firing
positions are, and away from your food stores.

### Power and utilities

| Structure | Function | Cost |
|---|---|---|
| **Generator** | Powers everything electrical | **45 noise continuously**, [fuel](12-resources.md) |
| **Floodlight** | Makes night ranged combat viable | 90 light — visible across the map |
| **Refrigeration** | Slows food spoilage | Power |
| **Turret** (late) | Automated ranged defense | Power, ammo, and it is *extremely* loud |

Every powered structure is an attention cost that runs while you sleep. The generator is the
single loudest ongoing decision in the game — and after the
[grid fails in week 3–5](13-world-decay.md), it's the only way to have electricity at all.

### Interior

Beds (rest quality), stoves, workbenches ([crafting](11-crafting.md)), storage, water collection,
latrines (place downwind), **and quarantine rooms**.

A [quarantine room](06-infection.md) deserves specific mention: a lockable, reinforced, observable
space, built before you need it. Colonies that improvise one under time pressure are the colonies that
lose several people at once.

## Degradation and upkeep

| Cause | Effect |
|---|---|
| Combat damage | Direct, and the obvious one |
| Rain | Rots wood, warps timber |
| Heat | Dries and cracks |
| Freeze/thaw | Splits everything |
| Time | Everything, slowly |

Repair needs materials, labor, and Craft skill, and this is a **permanent daily draw** on the colony's
work capacity. A large base is a large upkeep bill. Building more than you can maintain is a common
and quiet way to fail.

## Base siting

Choosing where to settle is a real decision with permanent consequences:

| Factor | Trade |
|---|---|
| **Wind direction** | Determines where your scent goes. The most under-appreciated factor. |
| **Elevation** | Sightlines and drainage vs. exposure and visible light |
| **Water access** | Essential; also a route others follow |
| **Chokepoints** | Bridges and narrow streets are defensible and also trap *you* |
| **Proximity to loot** | Convenient early, and it's where the crowds already are |
| **Existing structures** | A pre-built shell saves weeks of labor and dictates your layout forever |

Relocating is possible, brutally expensive, and sometimes correct — particularly once
[trackers](14-zombies.md) arrive or the local sites are exhausted.

## Content shape

Every structure is JSON ([content](20-ecs-and-content.md)): materials, build time, skill requirement,
durability, degradation rates by cause, attention emissions, and effects via the
[modifier pipeline](21-extensibility.md).

Adding a structure is a data entry. Adding a new *trap behavior* is a small system plus a tag; see the
[cookbook](21-extensibility.md).

## Cut list

- **Free-form multi-story construction.** Existing buildings have floors; player-built structures are
  single-story plus platforms. Massive complexity for modest payoff.
- **Decoration and furniture for its own sake.** Comfort comes from beds, warmth, light, and space —
  all functional.
- **Blueprint mode / ghost planning of large builds.** Post-slice quality-of-life.
- **Automated resource logistics** (conveyors, chutes). Wrong genre.
- **Player-placed doors that zombies can open.** Only [faction raiders](18-factions.md) use doors —
  that distinction is the whole point of that threat type.

---

**Previous:** [14 — Zombies](14-zombies.md) · **Next:** [16 — Weather](16-weather.md) ·
[Doc index](../README.md#documentation)
