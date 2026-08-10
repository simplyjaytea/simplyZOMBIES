# 14 — Zombies

*Why this exists: the antagonist is a weather system, not an enemy roster. This document defines how
individual zombies behave, how crowds form, and how the virus escalates over a run.*

---

## Design rules

1. **They are stupid and relentless.** No tactics, no flanking, no morale. They follow stimulus.
2. **Numbers are the difficulty.** One is a skill check. Eight is a wall. The design never needs a
   zombie that's individually scary — a crowd is scarier.
3. **They read the [attention field](03-attention.md).** Their pathing is gradient ascent, which means
   **the player's own behavior decides where they arrive.**
4. **They never flinch, only stagger.** Physics interrupts them. Fear doesn't.
5. **New types invalidate strategies, not stats.** Each [mutation wave](13-world-decay.md) should break
   a habit, not add a bigger number.

## Baseline behavior

Every zombie, regardless of type, runs the same loop:

1. **Sample** the three attention channels locally, weighted by its sensory profile.
2. **Ascend** the combined gradient — noise as a sharp impulse, scent as a slow bias, light as a
   [line-of-sight pull](28-visibility-and-sightlines.md#what-the-zombies-see). **Not naively** — see
   below.
3. **Investigate** on arrival. Find nothing, mill about, disperse — leaving their own **scent** behind
   (never noise, per [field memory](03-attention.md#field-memory-is-a-scent-mechanic)), so the spot
   stays mildly attractive. **The field remembers.**
4. **Pursue** on direct contact, indefinitely, without pathfinding cleverness — they'll grind against
   a wall between them and you for as long as you're audible.

### Gradient ascent is not sufficient on its own

The [spike](23-roadmap.md#spike-findings-attention-field) proved this the hard way. Every zombie
sharing a field cell samples the same gradient and picks the same one of eight neighbours, so they
collapse into **single-file queues** along the steepest path. It reads as ants on a pheromone trail,
which is the wrong genre entirely.

The fix: every individual carries a **persistent angular bias of ±0.62 rad (±35°)**, applied to the
sampled gradient direction before it moves. Reference implementation in `spike/zombies.ts`. Three
properties make it the right fix rather than a patch:

- **Assigned once at spawn, from the seeded RNG stream**, and never changed — so it is deterministic
  and reproduces from the seed, per [architecture](19-architecture.md#determinism).
- **It needs no neighbour queries.** Cost is O(1) per zombie with no spatial lookup, so it survives
  contact with the horde counts in [performance](22-performance.md). Measured: 0.04 ms sim without,
  0.05 ms with, at identical seek counts.
- **It is per-individual and persistent**, which makes it part of **save state** — not a per-tick
  random jitter. Re-rolling it every tick would produce a shimmer, not a crowd.

### Damage model
Meaningful damage is to the **head** or to **locomotion**. Body damage slows and staggers but doesn't
stop them. A zombie with a destroyed pelvis crawls, is quiet, is easy to miss in a dark breach, and is
still perfectly capable of biting an ankle.

### Grabs
The primary threat and the primary [bite](06-infection.md) vector. A grabbed survivor is immobilized
until they break free. Two simultaneous grabs is usually fatal. See [combat](09-combat.md).

### Against vehicles
They cannot open doors — [raiders](18-factions.md) can, which is the distinction that makes human
threats a different shape everywhere in this design. What they do instead is **mass around a
stationary [vehicle](25-vehicles.md)** and stay interested for as long as the engine runs, climb onto
it, and block it in. A vehicle is a metal box, and being surrounded inside one is the vehicular
version of being cornered indoors.

## Types

### Baseline

| Type | Behavior | Counter |
|---|---|---|
| **Shambler** | Slow, scent-led, poor senses. The bulk of every crowd. | Anything. In numbers, chokepoints. |

The starting map is shamblers only. Everything below arrives on the
[mutation schedule](13-world-decay.md).

### First wave (~week 6)

| Type | Behavior | Counter | Invalidates |
|---|---|---|---|
| **Stalker** | Faster; noise-led; investigates aggressively | Reach weapons, doors | Casual noise discipline |
| **Screamer** | Weak, but on sighting a survivor emits **300 noise** and relays to others | Kill it silently, first, from range — the [quiet branch's](09-combat.md) purpose | "Shoot it and walk away"; any plan that tolerates being seen |

The screamer is the most important design object in this document. It converts a small mistake into a
regional event, and it makes bows and suppressors mandatory equipment rather than a flavor choice.

It is also the type that cannot be built from the field alone. *"On sighting a survivor"* is an
observer query, not a gradient sample — which makes the screamer, and the runner behind it,
downstream of [visibility](28-visibility-and-sightlines.md) rather than of content.

### Second wave (~week 10)

| Type | Behavior | Counter | Invalidates |
|---|---|---|---|
| **Armored** | Accumulated debris and gear; resists light weapons | Heavy blunt, high-power firearms, traps | Bows, light melee, thin barricades |
| **Heavy** | Slow, enormous, wrecks [structures](15-base-building.md) fast | Ranged focus fire, spike traps, not being there | Static walls as a complete answer |
| **Bloater** | Bursts on death — heavy scent cloud, contamination risk | Kill at range, never indoors, never near the gate | Melee cleanup habits |

The bloater is a trap for competent players: killing it correctly costs ammunition, killing it cheaply
poisons your own doorstep with scent for days.

### Third wave (~week 16)

| Type | Behavior | Counter | Invalidates |
|---|---|---|---|
| **Runner** | Fast, sustained pursuit | Doors, elevation, chokepoints. **Not outrunning it.** | Escape as a reliable option |
| **Tracker** | Superior scent range; follows a specific survivor's trail home — **including a [vehicle's route trail](24-world-and-scale.md#route-trails)** | Water crossings, rain, decoys, varying your route, killing it | Sloppy return routes; "we lost them" |

The tracker is the one that punishes the base's location, and it's the design's late-game argument for
relocating or taking the [escape route](13-world-decay.md#the-optional-escape).

## Crowds and hordes

Zombies don't spawn in waves; they **accumulate and coalesce**.

- Individuals drifting up the same gradient converge, because a crowd emits its own noise and scent
  and becomes self-reinforcing.
- **The [angular bias](#gradient-ascent-is-not-sufficient-on-its-own) is what makes that read as a
  crowd** rather than a queue. It fans a convergence into a broad front, which is also what makes the
  bearing below legible — a wall of bodies has a direction; a conga line just has a head.
- A crowd above a size threshold becomes a **horde entity** — simulated coarsely at zone level for
  [performance](22-performance.md), resolving into individuals only near the player.
- Hordes have momentum. They arrive on a **bearing**, and the bearing is predictable from where your
  attention footprint is loudest. A player who understands the field knows which wall is going to get
  hit.
- Hordes disperse slowly after finding nothing, so a bad night has a tail.

**The [director](17-director.md) does not spawn hordes.** It adjusts pressure, migration, and
composition. Where and when they arrive remains a consequence of the field. That distinction is what
keeps the system feeling fair and diegetic rather than scripted.

## Sensory profiles

Each type weights the three channels differently, which is what makes counterplay type-specific rather
than generic:

| Type | Noise | Light | Scent |
|---|---|---|---|
| Shambler | Low | Low | **High** |
| Stalker | **High** | Moderate | Moderate |
| Screamer | Moderate | **High** | Low |
| Armored | Moderate | Low | Moderate |
| Heavy | **High** | Low | Low |
| Bloater | Low | Low | **High** |
| Runner | **High** | **High** | Moderate |
| Tracker | Low | Low | **Extreme** |

So a lightless, scent-managed base is invisible to shamblers and bloaters while a generator still pulls
in every heavy and runner in the district. **There is no single silence.** You choose which channel to
be quiet on, and that choice determines what kind of night you get.

**The Light column is not live yet.** Every sensory weight in this table is read by
`src/sim/modules/shambler.ts`, but light has no field behind it until
[visibility](28-visibility-and-sightlines.md) ships. Until then a light-led type is a JSON entry
weighting a channel that is always zero — which is why the types below the shambler are gated on that
work and not merely on the [mutation schedule](13-world-decay.md).

## Content shape

Every type is a JSON entry ([content](20-ecs-and-content.md)): sensory weights, speed, health by body
part, grab strength, damage, noise emission, special behavior tags, and the mutation wave that
introduces it.

**Adding a zombie type is one JSON entry with zero code**, provided its behavior composes from existing
tags. This is worked example #1 in the [cookbook](21-extensibility.md).

The qualifier is doing real work. Stalkers and armored zombies compose from tags that exist or nearly
do — different sensory weights, different speeds, different per-part health. Screamers and runners
need [sight](28-visibility-and-sightlines.md); heavies need
[structure damage](15-base-building.md); bloaters need a death effect that writes to the scent
channel. **The roster is cheap; three of its behaviours are not**, and the
[roadmap](23-roadmap.md) orders them accordingly.

## Cut list

- **Intelligent zombies / coordinated behavior.** Breaks rule 1 and the horror.
- **Zombie factions or infighting.** No.
- **A boss zombie.** Wrong genre; the horde is the antagonist.
- **Player-controllable or tamed zombies.** Cut at the [infection](06-infection.md) level.
- **Zombie corpse reanimation after being killed.** Considered — undermines the value of clearing an
  area, which the [attention field](03-attention.md) already handles more elegantly.
- **Day/night behavioral differences beyond sensory ones.** Light matters at night because light
  matters at night; they don't need a separate nocturnal mode.

---

**Previous:** [13 — World Decay](13-world-decay.md) ·
**Next:** [15 — Base Building](15-base-building.md) · [Doc index](../README.md#documentation)
