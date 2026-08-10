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
| Shouting (120) | 171 m | Most of a district. The cheapest way to make a mistake on purpose |
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

### Scent, and the constants it needed of its own

Scent is the *continuous* channel, and building it turned up the same class of problem the spike hit
with noise: a constant that had never been written down.

| Constant | Value |
|---|---|
| Scent half-life | **90 minutes** (minutes, not seconds — the unit difference is the point) |
| Diffusion rate | **0.02** of a cell per step |
| Diffusion step | every **5 ticks**, so 4 Hz |
| Scent floor | **0.005** |
| Per-cell ceiling | **5,000** |
| Wind | a constant global vector, **(+0.6, −0.2)** until [weather](16-weather.md) owns it |

Three of those are worth stating as decisions rather than numbers:

**Scent needs its own floor, and sharing noise's silently broke it.** The noise floor is near zero so
that `reach = magnitude ÷ attenuation` holds exactly — an identity a diffusive channel does not have
at all. Sharing it made the *floor*, not the half-life, decide how long a smell lasted: diffusion
dilutes a plume until every one of its cells crosses the threshold at about the same moment, so a
deposit evaporated in roughly two minutes while this table claimed ninety. A scent-specific floor at
a tenth of noise's fixes it. A residue deposit now lasts around 40 minutes, against half a minute for
a shout.

**Scent sums where noise takes a maximum.** Two people shouting together are not louder; two people
standing together do smell more. This is the only place the two channels' arithmetic disagrees, and
it is what makes "population is a permanent, unavoidable scent floor" true rather than decorative.
Summing is why scent needs a ceiling and noise does not.

**Nothing blocks scent, including walls.** Per the channel table above, only wind and time disperse
it. Unlike noise there is no wall penalty and no solid-cell shadow — a smell goes under the door.

**Decay** is multiplicative with a **~3 s half-life**, applied to the propagated field. That is what
"fast — seconds to a minute" above means numerically.

What decays is **loudness everywhere at once, not the radius**. This is worth stating explicitly
because the intuitive reading is wrong, and Milestone 1 found it the moment there was something to
measure: multiplying the stored field leaves its *shape* untouched, so five half-lives after a shout
every cell is 1/32 of what it was, and the edge has barely moved. The audible radius only retreats as
the faint tail crosses the floor — around half a minute for a shout, and a little longer for a
gunshot.

The behaviour that produces is the one the design wants, arrived at by a different route than "the
spike is inaudible in 15 seconds" suggests: a shout stops being a *strong* attractor within seconds,
while staying faintly audible across most of its original reach for long enough that the horde it
summoned is still walking. You can be quiet again in a minute; they are still coming, which is the
entire point.

## Emitters

Written as data (see [ECS & content](20-ecs-and-content.md)); magnitudes are in the units
[calibrated above](#scale-and-calibration).

### Noise

| Source | Magnitude | Notes |
|---|---|---|
| Walking | 1 | |
| Sprinting | 6 | |
| Speaking — whisper | 2 | ~3 m. Same room. See [voice as an emitter](27-multiplayer.md#voice-is-an-emitter) |
| Speaking — talk | 8 | ~11 m. Conversational — exactly a melee connect |
| Melee swing (connect) | 8 | Blunt louder than blade |
| Breaking a window | 25 | |
| Hammering / construction | 30 | Sustained — a build project is a beacon all day |
| Shouting | 120 | Loud enough to be a district event, quiet enough not to be a gunshot |
| Generator (running) | 45 | Continuous, and it doesn't stop when you sleep |
| Bow / crossbow | 4 | The [quiet branch](09-combat.md) |
| Suppressed firearm | 40 | Much quieter than unsuppressed; still very loud in absolute terms |
| Unsuppressed firearm | 180 | Category-defining for a *single event* |
| Explosion | 400 | |
| A [screamer](14-zombies.md) that has seen you | 300 | And it relays — this is the horror |
| [Vehicle](25-vehicles.md) engine | 120–220 | **Continuous.** A gunshot is a moment; driving is a broadcast. |
| Vehicle horn | 350 | |

> **Voice obeys the table.** In [multiplayer](27-multiplayer.md#audible-range-equals-emission-reach)
> the player's own voice is an emitter on this channel, and the rule binding it is that **audible
> range equals emission reach** — what a teammate can hear is exactly what a zombie can hear, on the
> same curve, through the same walls. Shouting is the register already in the table at 120; whisper
> and talk extend it downward. No register carries further to a human than it does to the dead.

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
   their own mass. Where that leads is [not where this document originally guessed](#what-field-memory-turned-out-to-actually-do).

Point 4 matters: **the field has memory** — and the memory turned out to travel. See
[what field memory turned out to actually do](#what-field-memory-turned-out-to-actually-do).

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

### What field memory turned out to actually do

**Verified, kept, and not what this document used to claim.** Milestone 1 built the scent channel and
ran the acceptance check: boot two identical districts, disable the `field-memory` module in one,
shout, and watch. Something observable changes, emphatically — so the mechanic stays. But the thing
that changes is not "the site stays attractive".

**The horde migrates.** A crowd that mills lays residue; the residue drifts downwind; the crowd
climbs the gradient into its own plume, mills further along, and lays more. An hour after a single
shout the horde's centre of mass had crossed most of a district — 128,128 to roughly 217,73 with the
wind at (+0.6, −0.2) — while the same district with residue disabled left it sitting where it
gathered, about 7 m from the spot.

So the mill site does not stay crowded. It *empties faster*, because the crowd walks off downwind
following itself: 37 bodies within 50 m at twenty minutes against 73 with the mechanic off.

This is better than what was originally specified, and it is worth being clear about why rather than
quietly rewriting history:

- The horde acquires a **location and a heading** between events. It is somewhere, and it is going
  somewhere, without a director scripting it and without a wave timer.
- **Wind becomes tactical exactly as [weather](16-weather.md) always claimed it would be**, before
  the weather system exists. Where a horde goes after you disturb it is now a thing the player can
  read off the wind and plan around.
- It is **self-limiting**, which is the part that could have gone badly. The migration needs a dense
  crowd to sustain the emission; once the horde reaches the district edge and spreads along it, the
  residue burns out and they disperse normally. Measured: at the boundary by 60 minutes, scent gone
  by 90, and drifting apart again by 180.

The original claim — that a place you made a mistake stays a bad neighbourhood — is **not** what the
mechanic delivers, and is struck rather than reworded. What replaces it is a horde that carries the
memory *with it* instead of leaving it behind.

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
- **Scent diffusion is a gather, not a scatter.** Each cell pulls a share from its four neighbours
  rather than pushing its own outward. Both express the same physics, but only the gather is
  deterministic for free: a scatter accumulates into a cell from several sources in whatever order
  the loop reaches them, and float addition is not associative, so the result would depend on
  iteration order. All of the wind bias lives in four normalised outflow weights derived once at
  construction, so the diffusion loop itself does not know which way the wind blows.
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
