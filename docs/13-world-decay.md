# 13 — World Decay

*Why this exists: colony sims die of comfort. Once food and defense are solved the game becomes
chores. This document defines the clock that ensures no solution is permanent — the world gets worse
whether or not you play well.*

---

## The thesis

> Every stable equilibrium you build has an expiry date.

The [director](17-director.md) reacts to the player. World decay does not. It runs on a fixed schedule
from day one and it does not care how competent you are, how many walls you have, or how many people
you're feeding. It is the game's second hand.

The player's relationship with it isn't "beat it" — it's **notice it early enough to prepare.**

## The decay clock

Indicative timings for the Standard preset; all data-driven and exposed to the
[sandbox settings](01-hardcore-contract.md#sandbox-settings).

| Week | Event | Consequence |
|---|---|---|
| **1** | Grace period | The director holds back. Learn the map. |
| **2–3** | **Mains water fails** | Taps stop. Rain collection, wells, and boiling become mandatory. |
| **3–5** | **The power grid fails** | Permanent. Lights, refrigeration, and powered defenses now need [fuel](12-resources.md), which is finite. Food starts spoiling faster the same week. |
| **4+** | **Fresh food is gone** | Everything left in the world is canned, preserved, or growing. |
| **6–8** | **First mutation wave** | [Zombie types](14-zombies.md) diversify. Whatever tactic carried you here stops working. |
| **8+** | **Canned goods begin expiring** | Scavenged food yields drop. The stockpile you were proud of is quietly rotting. |
| **10–14** | **Second mutation wave** | Armored and specialized types. Melee-only colonies are in real trouble. |
| **12+** | **Local sites exhausted** | Runs become overnight expeditions. See the [expanding radius](12-resources.md#depletion-and-the-expanding-radius). |
| **16+** | **Third mutation wave, sustained pressure** | The endgame state. Attrition wins eventually. |

## The five decay tracks

### 1. Infrastructure
Water mains, then the power grid, both permanent and both announced by symptom before failure (flicker,
pressure loss). The grid failing is the single largest quality-of-life cliff in the game — it converts
every comfort into a fuel expenditure, and fuel is finite.

### 2. Consumables
Fresh food spoils in days. Canned goods have a real expiry measured in months. Batteries lose charge
whether or not you use them. Medical supplies degrade in potency — **including
[antibiotics](12-resources.md)**, which means hoarding them is not a strategy.

### 3. Equipment
Everything [degrades with use](10-items.md), and repair permanently lowers the ceiling. Structures
weather; [barricades](15-base-building.md) rot in rain and warp in heat even without being hit. There
is no state in which your gear stops needing attention.

### 4. Scavenging supply
Sites deplete permanently, pushing the viable radius outward. This is covered fully in
[resources](12-resources.md); listed here because it's the track the player feels most continuously.

### 5. The virus
The one that changes *how you play* rather than how comfortable you are.

Mutation waves are scheduled, not power-scaled, and each introduces types that invalidate a strategy:

| Wave | Introduces | Invalidates |
|---|---|---|
| **First (~wk 6)** | Faster movers, [screamers](14-zombies.md) | Casual noise discipline; "shoot it and walk away" |
| **Second (~wk 10)** | Armored, heavy | Bows and light melee; thin barricades |
| **Third (~wk 16)** | Composite threats, better sensory range | Static defense as a complete answer |

The design intent is that **there is no permanent build**. Whatever solved week 5 will not solve week
12, and that's what keeps [crafting](11-crafting.md) and scavenging alive across a long run.

## Warning, not ambush

Per the [fairness rules](01-hardcore-contract.md#fairness-rules), decay always telegraphs:

- Water pressure drops before the mains fail.
- Lights flicker and brownouts happen before the grid dies.
- Canned goods show as "old stock" before they turn.
- **Mutations are visible in the wild before they're at your wall** — a scout who sees something new
  moving too fast is a warning worth acting on.

Being surprised by decay is a scouting failure, not a design ambush.

## What the player does about it

Decay isn't unbeatable, it's a treadmill that speeds up. Counters exist and all of them cost:

| Decay | Counter | Cost |
|---|---|---|
| Water mains | Rain collection, wells, boiling | Construction, fuel, labor |
| Grid failure | Generators | Fuel — finite, and 45 noise continuously |
| Food spoilage | Curing, canning, drying, root cellars | Labor, materials, scent |
| Equipment wear | Repair, salvage, fresh bases | Materials, Craft skill, longer runs |
| Site depletion | Longer expeditions, [faction trade](18-factions.md), farming | Time away, exposure, permanent scent |
| Mutation | New tactics, better gear, redesigned defenses | Everything — this is the real one |

Notice that almost every counter *increases your [attention](03-attention.md) footprint*. Surviving
decay makes you louder, which makes nights worse. The two systems push the same direction, and that
compounding is the intended shape of a long run.

## The optional escape

[The escape endgame](01-hardcore-contract.md#7-there-is-no-victory) exists because of this document.
Decay guarantees the location eventually becomes untenable, so leaving is a coherent goal rather than
a bolted-on win button: a working vehicle, the fuel to run it, a scouted route, and enough people left
alive to be worth going with.

Most runs won't get there. That's fine — it exists to give the late game a direction other than
waiting.

## Content shape

The entire clock is data ([content](20-ecs-and-content.md)): a list of scheduled events with a week
range, a trigger, and effects, all going through the [modifier pipeline](21-extensibility.md) or
publishing events on the bus.

Adding a decay event — "week 20: winter kills the crops" — is one JSON entry. Retiming the whole clock
for a sandbox preset is a data override. Disabling decay entirely leaves the game running, per the
[module rule](19-architecture.md).

## Cut list

- **Scaling decay to player performance.** That's the [director's](17-director.md) job. Decay is fixed
  precisely so that something in the game is honest and indifferent.
- **A hard end date / forced run termination.** The world becomes untenable gradually; it never
  hands you a timer.
- **Seasonal collapse of all food production.** Winter is hard ([weather](16-weather.md)), not
  terminal.
- **Structural collapse of buildings over time.** Good texture, expensive to simulate, post-slice.

---

**Previous:** [12 — Resources](12-resources.md) · **Next:** [14 — Zombies](14-zombies.md) ·
[Doc index](../README.md#documentation)
