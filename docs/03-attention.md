# 03 — The Attention Field

*Why this exists: this is the kernel mechanic. Survival, colony sim, tower defense, and RPG blend
because they all write to and read from one shared field. If you only read one system document, read
this one.*

---

## The thesis

Zombies don't hunt. They *drift toward stimulus*. The map carries a per-tile field of three stimulus
channels, and the horde performs gradient ascent on it.

Everything the player does to live better emits into that field. That is the entire game:

> **You cannot be comfortable and hidden at the same time.**

Cold, dark, and hungry is safe. Warm, lit, and fed is loud. [Mood](04-survival-needs.md) punishes the
first; the horde punishes the second. The player lives in between, and the [director](17-director.md)
keeps moving the line.

## Three channels

Kept separate because each behaves differently and each has a different counter.

| Channel | Propagates | Decays | Blocked by | Amplified by |
|---|---|---|---|---|
| **Noise** | Fast, far, radially; passes through walls attenuated | Fast (seconds to a minute) | Mass — walls, hills, distance | Enclosed hard surfaces, night quiet |
| **Light** | Line-of-sight only, long range at night | Instant (it's on or off) | Any opaque obstruction, shutters, curtains | Darkness, elevation, fog scatter |
| **Scent** | Slow, drifts downwind, pools in still air | Slow (hours) | Nothing — only wind and time disperse it | Heat, humidity, rot, mass of organic material |

The three are deliberately non-interchangeable:

- **Noise** is *spiky*. A gunshot is a huge instantaneous event that fades. You can be quiet again in
  a minute; the horde it summoned is still walking.
- **Light** is *binary and directional*. It's the easiest to fix (shutters, discipline) and the
  easiest to forget.
- **Scent** is *cumulative and slow*. It's the one that punishes long-term habits — corpse piles,
  a big population, a smokehouse — and it's why a base can become untenable over weeks without any
  single mistake.

## Scale and calibration

The emitter tables below were authored as *ratios* — melee against gunfire, a bow against a
suppressed shot, an engine against everything. The ratios were right. What was never written down is
the **unit**, and the [spike](23-roadmap.md#spike-findings-attention-field) found out the expensive
way: it picked an attenuation constant arbitrarily, and one shout flooded an entire district.

Four constants fix that, and none of the magnitudes change:

| Constant | Value |
|---|---|
| Tile scale | **1 tile = 1 metre** |
| Field cell | **4 m** (4×4 tiles — the field is deliberately coarser than the tile grid) |
| Open-ground attenuation | **0.7 magnitude per metre** |
| District | **256 × 256 m** = 64 × 64 field cells ([world & scale](24-world-and-scale.md#the-region)) |

> **Magnitude is reach.** A source carries `magnitude ÷ 0.7` metres through open ground before it
> falls under the audible floor.

Which makes the table below read in metres, against a 256 m district:

| Emitter | Reach | What that means |
|---|---|---|
| Walking (1) | 1.4 m | Silent. Moving carefully genuinely works. |
| Bow (4) | 5.7 m | The [quiet branch](09-combat.md) is quiet in absolute terms, not just relative ones |
| Sprinting (6) | 8.6 m | Sprinting past something wakes it |
| Melee connect (8) | 11 m | A fight draws the neighbours, not the block |
| Breaking a window (25) | 36 m | The building, and the street outside it |
| Generator (45) | 64 m | A continuous quarter-radius beacon that runs all night |
| [Engine](25-vehicles.md) (120–220) | 171–314 m | **Continuous, and it moves.** Most of a district, sustained |
| Unsuppressed firearm (180) | 257 m | **One district, exactly.** One shot is a district-wide event |
| [Screamer](14-zombies.md) (300) | 428 m | Over 1.5 districts — *and it relays* |
| Explosion (400) | 571 m | Past the district edge, which is what makes it self-limiting |

**Walls.** A solid field cell costs an extra **18 m-equivalent** of travel on top of the distance, so
a gunshot that carries 257 m outdoors reaches ~180 m through one wall and ~100 m from deep inside a
building. Being indoors is worth real distance.

**Noise routes around obstructions.** It is a flood through open space, not a ray, so a wall shadows
only what is directly behind it *with no path around*. In a built-up district the streets are noise
highways and a building casts a much smaller shadow than its footprint suggests — which is the same
property [roads](24-world-and-scale.md#roads) already relies on, seen from the other side. Do not
budget for buildings as noise insulation; budget for them as detours.

**Decay** is multiplicative with a **~3 s half-life**, so a spike is inaudible roughly 15 seconds
after a shout and 25 after a gunshot. That is what "fast — seconds to a minute" above means
numerically. The horde it already summoned is still walking, which is the entire point.

## Emitters

Written as data (see [ECS & content](20-ecs-and-content.md)); magnitudes are in the units
[calibrated above](#scale-and-calibration).

### Noise

| Source | Magnitude | Notes |
|---|---|---|
| Walking | 1 | |
| Sprinting | 6 | |
| Melee swing (connect) | 8 | Blunt louder than blade |
| Breaking a window | 25 | |
| Hammering / construction | 30 | Sustained — a build project is a beacon all day |
| Generator (running) | 45 | Continuous, and it doesn't stop when you sleep |
| Bow / crossbow | 4 | The [quiet branch](09-combat.md) |
| Suppressed firearm | 40 | Much quieter than unsuppressed; still very loud in absolute terms |
| Unsuppressed firearm | 180 | Category-defining for a *single event* |
| Explosion | 400 | |
| A [screamer](14-zombies.md) that has seen you | 300 | And it relays — this is the horror |
| [Vehicle](25-vehicles.md) engine | 120–220 | **Continuous.** A gunshot is a moment; driving is a broadcast. |
| Vehicle horn | 350 | |

### Light

| Source | Magnitude | Notes |
|---|---|---|
| Candle | 3 | |
| Campfire | 20 | Also heat, also smoke → scent |
| Electric lamp | 35 | |
| Floodlight | 90 | Excellent for shooting accuracy at night. Visible across the map. |
| Muzzle flash | 60 (instant) | Ranged combat at night gives away position twice over |
| [Vehicle](25-vehicles.md) headlights | 70–110 | And they move, sweeping across everything ahead |

### Scent

| Source | Magnitude | Notes |
|---|---|---|
| One living human | 1 | Population is a permanent, unavoidable scent floor |
| Unwashed human | 2 | [Hygiene](04-survival-needs.md) has a mechanical purpose |
| Cooking | 15 | |
| Fresh corpse | 8 | |
| Rotting corpse | 25, rising | The single worst thing to neglect |
| Butchery / blood | 30 | |
| Livestock | 20 | Food security costs you permanently |
| Latrine | 12 | Place it downwind. Yes, wind direction matters. |

## How the horde reads the field

Per [zombie](14-zombies.md) tick, at a coarse rate for distant entities
([performance](22-performance.md)):

1. Sample the three channels in the local neighborhood.
2. Weight them by the individual's sensory profile — types differ. Most are scent-led; some are
   noise-led; a few see well.
3. Move up the combined gradient, with noise applied as an *impulse* (a sharp bearing change toward a
   recent loud event) and scent as a *bias* (a slow drift).
4. On arriving at the source and finding nothing, mill and disperse — which raises local scent from
   their own mass, so a place that drew them stays slightly attractive afterward.

Point 4 matters: **the field has memory**. Somewhere you made a mistake stays a bad neighborhood for
a while.

### Field memory is a scent mechanic

Stated explicitly, because the [spike](23-roadmap.md#spike-findings-attention-field) got it wrong and
the mistake is an easy one to repeat:

- Milling residue writes to **scent only, and never to noise.** A crowd standing around is not a
  noise event; it is a smell that lingers after they leave. Noise is event-driven and spiky by
  design, and a continuous noise emitter would undo that.
- Residue is emitted at **30 magnitude per milling body per emission interval**, which is above the
  scent propagation floor. This is the number the spike got wrong: it emitted 5 against a per-cell
  falloff of 4, so the residue died inside its own cell and toggling the mechanic off changed
  nothing observable.
- Because scent decays over **hours** rather than seconds, memory outlives the event that caused it
  by the right order of magnitude. Noise could never have produced this behaviour.

**Verified in Milestone 1, and kept.** The acceptance check was: switch residue off and confirm
something changes. It does, and not merely in the field's contents — in where the horde ends up.

A crowd drawn to a spot and then left in silence for a full minute settles **19.4 m** from it with
residue on, against **25.4 m** with it off. Somewhere you made a mistake really does stay a bad
neighbourhood after the crowd has gone, which is the behaviour this mechanic was kept for.

Asserted in `test/integration/milestone-1.test.ts`, deliberately on the behavioural consequence
rather than on "the emitter fires" — the spike's residue also existed, and was still a no-op,
because nothing downstream could perceive it.

### Route trails

[Vehicles](25-vehicles.md) write to the field differently from everything else: they leave a decaying
**corridor** of noise and scent along the exact path driven, stored on the road graph rather than the
fine grid ([world & scale](24-world-and-scale.md#route-trails)).

A trail leading from a hospital campus to your gate is an arrow pointing at everything you own, and
[trackers](14-zombies.md) read it. Varying your route home is basic discipline, the vehicular
equivalent of shutting the shutters at dusk.

## Playing the field

The field isn't only a punishment. It's the tower-defense skill expression, because **you can write
to it deliberately**.

- **Bait.** A wind-up noisemaker, a lit lamp on a timer, a hung carcass. Placed 200m from your wall,
  it collects the drift and gives you a night off. Bait consumes resources and must be replaced.
- **Routing.** Since the horde ascends a gradient, a wall isn't just an obstacle — it's a *steering
  surface*. Correct play is arranging your emissions so the pressure arrives where your traps and
  firing positions are, not where your food is.
- **Corridors.** A deliberately weak-looking approach that's actually a killbox. This is a killbox
  built out of *stimulus*, not just geometry, which is what makes it more interesting than a maze.
- **Silence discipline.** Shutters at dusk, melee over guns, cold food, corpses burned promptly. A
  colony run this way is genuinely safe and genuinely miserable — see
  [survival needs](04-survival-needs.md).

## The counter-pressure

Every mitigation costs something the player wants:

| Mitigation | Cost |
|---|---|
| No lights | Mood, sleep quality, ranged accuracy at night |
| No cooking | Mood, worse nutrition, disease risk from raw food |
| No generator | No powered defenses, no refrigeration → faster spoilage |
| Melee only | Bite risk, and bite risk is [infection](06-infection.md) |
| Fewer survivors | Less labor, fewer defenders |
| Bait | Resources, and it must be re-placed constantly |
| Prompt corpse disposal | Labor hours, plus smoke if burned |
| Not driving | Range — and once the local sites are stripped, range is food |

There is no configuration that is quiet *and* comfortable. That's the design working.

## Implementation notes

- Stored as three scalar layers over a coarse grid — **4 m cells**, per
  [scale and calibration](#scale-and-calibration) — updated on a fixed tick. Attention is a smooth
  gradient and doesn't need per-tile precision.
- Noise resolves via attenuated flood-fill with material-based falloff; light via shadowcasting from
  emitters; scent via a diffusion step with a global wind vector from [weather](16-weather.md).
- Spatial hashing and update budgets in [performance](22-performance.md).
- The field is deterministic and part of the save state.
- A debug overlay visualizes all three channels — developer-only, per the
  [imperfect information rule](01-hardcore-contract.md#4-information-is-scarce-and-unreliable).

## Cut list

- **A visible attention meter for the player.** Rejected: it would collapse the game's central
  uncertainty into a number. The player reads the field through diegetic cues — how far the lamplight
  throws, whether smoke is visible, how bad the corpse pile smells in the description text.
- **A fourth channel (vibration/tremor).** Interesting, doesn't earn its complexity yet.
- **Per-zombie scent memory / tracking a specific survivor.** Post-slice; a "hunter" mutation could
  use it later.

---

**Previous:** [02 — Core Loop](02-core-loop.md) ·
**Next:** [04 — Survival Needs](04-survival-needs.md) · [Doc index](../README.md#documentation)
