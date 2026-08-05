# 25 — Vehicles

*Why this exists: vehicles were originally cut from this design on the grounds that they'd wreck the
attention economy. That was wrong — they don't break the spine, they become its loudest possible
expression. This document defines them as found, customizable, degrading machines that are extremely
useful and extremely dangerous to switch on.*

---

## Design rules

1. **An engine is the loudest thing in the game.** Driving announces you to an entire district,
   continuously, for as long as it runs.
2. **Vehicles are [items](10-items.md)**, using the same grammar — found not built, `base + rolled
   affixes`, four tiers, movable attachments.
3. **Vehicles are not weapons.** Hitting zombies damages the vehicle. Ramming is a last resort with a
   repair bill, never a strategy.
4. **Nothing is permanent.** Vehicles degrade faster than anything else you own, and repair
   [lowers the ceiling](10-items.md#condition-and-degradation) the same way it does for weapons.
5. **Fuel bounds everything.** A vehicle without fuel is a shed.

## The attention cost

The single most important table in this document:

| Source | Noise | For comparison |
|---|---|---|
| Motorcycle | 120 | Hammering / construction: 30 |
| Car / SUV engine | 150 | Generator: 45 *(continuous)* |
| Van / pickup | 175 | **Unsuppressed firearm: 180** |
| Box truck / bus | 220 | Screamer: 300 |
| Horn | 350 | Explosion: 400 |
| Collision | 250 | |

| Source | Light |
|---|---|
| Headlights, low | 70 |
| Headlights, high | 110 |
| Interior light | 15 |

Compare against [the attention field's emitter tables](03-attention.md#emitters). Driving a bus across
a district is louder than firing a rifle, and you do it for ten minutes straight.

**A muffler is the most valuable attachment in the game.** It fills exactly the role a suppressor fills
for firearms: it doesn't make you quiet, it makes you survivable, and it wears out.

### Route trails

A driven route leaves a [decaying corridor of noise and scent](24-world-and-scale.md#route-trails).
[Trackers](14-zombies.md) follow it. Driving the same road home twice is how a colony gets found.

## Bases

Found in the world, in whatever condition the apocalypse left them. Never manufactured.

| Base | Volume | Speed | Fuel | Notes |
|---|---|---|---|---|
| **Motorcycle** | None | High | Excellent | Quietest option. No protection whatsoever. |
| **Hatchback** | Tiny | Moderate | Excellent | Everywhere. The first vehicle most runs get. |
| **Sedan** | Small | Moderate | Good | Common, balanced, unremarkable |
| **SUV** | Moderate | Moderate | Poor | Handles rough ground and blocked roads |
| **Pickup** | Moderate (bed) | Moderate | Moderate | Tows. Open bed means exposed cargo. |
| **Van** | **Large** | Low | Poor | The [mobile base](26-mobile-bases.md) workhorse |
| **Ambulance** | Large | Low | Poor | Arrives with a medical module fitted |
| **Box truck** | **Very large** | Low | Terrible | A rolling warehouse that announces itself for a mile |
| **Bus** | **Enormous** | Very low | Appalling | Maximum interior, minimum everything else |

## Slots

Attachments are **found, not crafted**, and **move between compatible bases** — so upgrading from a van
to a box truck doesn't discard the muffler and reinforced tires you spent a month assembling. Same
principle as [weapon attachments](10-items.md#attachment-slots).

| Slot | Options | Trade |
|---|---|---|
| **Engine** | Stock · rebuilt · high-output | Power vs. fuel burn vs. **noise** |
| **Exhaust** | Stock · **muffled** · straight-pipe | The noise dial. Muffled costs power and wears fast. |
| **Tires** | Road · all-terrain · run-flat | Grip and off-road vs. speed and fuel |
| **Plating** | None · scrap · reinforced | Protects the radiator and glass; costs speed, fuel, and handling |
| **Storage** | Racks · roof box · trailer *(hitch)* | Capacity vs. weight vs. noise |
| **Lights** | Stock · off · floods | Night driving vs. a 110-magnitude beacon |
| **Winch** | — | Clears [road blockages](24-world-and-scale.md#roads), self-recovery |
| **Interior** | See [mobile bases](26-mobile-bases.md) | Volume budget |

## Affixes and tiers

Same four tiers as every other item: **Scavenged · Modified · Field-Tested · Named**.

**Prefixes:** Rusted (fragile, cheap to find) · Reinforced (durable, heavy) · Muffled (quieter, less
power) · Overbored (fast, thirsty, loud) · Stripped (light and fast, no protection) · Well-Kept (slow
condition loss).

**Suffixes:** *of the Long Haul* (fuel efficiency) · *of Salvage* (cheap, fast repair) · *of Ruin*
(powerful, degrades fast) · *of the Quiet Road* (reduced noise emission).

### Named vehicles

Hand-authored, very rare, always with a real drawback — same balance philosophy as
[named items](10-items.md#named-items) and [unique survivors](07-survivors.md#unique-survivors).

| Vehicle | Gain | Drawback |
|---|---|---|
| **The Coroner** | Ex-hearse. Excellent interior volume, unusually quiet | Permanent mood penalty for anyone who sleeps in it |
| **Gospel Truck** | Box truck with a working PA system — the best **bait** emitter in the game | Cannot be made quiet. Ever. |
| **The Long Sunday** | Superb fuel economy and range | Painfully slow; cannot outrun anything |
| **Ex-Nine** | Ex-police interceptor. Genuinely fast | Straight-piped and unmufflable; 240 noise |
| **Rust Bucket** | Free to repair from scrap, endlessly | Breaks down constantly, offers no protection |

## Driving

- **Momentum and weight.** A loaded box truck does not stop. Braking distance is a real number that
  kills people, and cargo weight changes it.
- **Terrain.** Roads are fast. Off-road is slow, damaging, and impassable for most bases.
- **Fuel burn** scales with weight, speed, terrain, and engine. Idling burns fuel — parking with the
  engine running to keep the heater on is a decision with a price.
- **Blocked roads** need a winch, manual clearing (loud, slow, exposed), or a detour.

### Hitting things

Ramming is not a mechanic, it's a mistake with a bill:

| Impact | Consequence |
|---|---|
| One zombie at low speed | Minor damage, 250 noise, they get up |
| One at speed | They go down; radiator, grille, or headlight damage |
| A crowd | **You stop.** Bodies under the wheels, a wrecked front end, and a mob around a stationary vehicle |
| A wall or wreck | Serious structural damage, possible immobilization |

The design intent: driving through a horde looks like the obvious answer and is how you lose the
vehicle *and* the people in it.

### Zombies and vehicles

- They **mass around a stationary vehicle** and don't lose interest while the engine runs.
- They **climb on**, blocking sightlines and clinging.
- They can **trap you inside** — a vehicle is a metal box, and being surrounded in one is the
  vehicular equivalent of being cornered indoors ([hardcore contract](01-hardcore-contract.md)).
- They cannot open doors. [Raiders](18-factions.md) can, which is the same distinction that makes
  human threats a different shape everywhere else.

## Condition, breakdowns, and repair

Vehicles degrade **faster than anything else you own** — from use, impacts, weather, and time.

Components fail individually: engine, radiator, tires, battery, fuel line, transmission. A degraded
vehicle doesn't lose a percentage of its speed, it fails in a specific way at a specific moment,
usually the worst one.

| State | Effect |
|---|---|
| Sound | Nominal |
| Worn | Slower, thirstier, occasional stalling |
| Failing | Frequent stalls; a **breakdown roll** on every trip |
| Broken | Immobile. Repair in place, tow it, or strip it. |

**A breakdown far from home is a disaster**, and it's the nomad death spiral's first domino
([mobile bases](26-mobile-bases.md#how-nomads-die)). Repair needs parts, Craft skill, tools, and
ideally a workshop — and, like all [repair](10-items.md#condition-and-degradation), never restores the
full ceiling.

## Where vehicles sit in the economy

- **[Fuel](12-resources.md)** stops being the comfort resource and becomes the strategic one. Every
  litre is a choice between light, heat, refrigeration, powered defenses, and *range*.
- **[World decay](13-world-decay.md)** is what makes vehicles necessary rather than optional — once the
  local sites are stripped, a vehicle is the only way to keep eating.
- **The [escape endgame](01-hardcore-contract.md#7-there-is-no-victory)** now has a real system behind
  it: a working vehicle, fuel, a scouted route, and enough people alive to be worth leaving with.

## Content shape

Bases, slots, attachments, affixes, and named vehicles are JSON
([content](20-ecs-and-content.md)) with stable string IDs, using the same affix and modifier structures
as every other item. Component failure rates and fuel curves are data.

**Adding a vehicle base is a data entry.** Adding a new slot type is a data entry plus a line in the
compatibility table.

## Cut list

- **Vehicle crafting from scratch.** You find chassis; you never build one.
- **Full vehicle physics** (suspension, individual wheel traction, rollover). Momentum, weight, and
  terrain class are enough.
- **Aircraft and boats.** No.
- **Vehicle-mounted weapons.** A turret on a truck trivializes hordes and breaks
  [pillar 1](00-vision.md). The PA system on the *Gospel Truck* is the deliberate exception, and it's a
  bait emitter, not a gun.
- **Player-driven vehicle combat against [factions](18-factions.md).** Post-1.0 at best.
- **Fuel types and engine compatibility** (diesel vs. petrol). Realistic, tedious, cut.

---

**Previous:** [24 — World & Scale](24-world-and-scale.md) ·
**Next:** [26 — Mobile Bases](26-mobile-bases.md) · [Doc index](../README.md#documentation)
