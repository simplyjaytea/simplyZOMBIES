# 26 — Mobile Bases

*Why this exists: a [vehicle](25-vehicles.md) with an interior is a different object from a vehicle
that carries loot. This document defines mobile bases, the volume budget that makes fitting one out a
real build decision, and how a full nomad playstyle can be genuinely viable without making fixed
colonies pointless.*

---

## Two ways to survive

Nomad play is viable, and it does not invalidate the colony half of the game — because the two
playstyles **fail in opposite directions**:

| | **Fixed colony** | **Nomad convoy** |
|---|---|---|
| **Defense** | Walls, traps, chokepoints, [killboxes](15-base-building.md) | Leaving |
| **Food** | Farming — renewable, eventually self-sufficient | Scavenging only, forever |
| **Water** | Collection at scale, wells | Tank capacity, refilled opportunistically |
| **Production** | Forge, full [crafting](11-crafting.md), bulk repair | A workbench at reduced quality |
| **Storage** | Stockpiles limited by floor space | **Volume-bounded. You cannot hoard.** |
| **Rest** | Proper beds, warmth, personal space | Always worse. A permanent mood and attrition tax. |
| **Scent footprint** | Accumulates, permanent, findable | Left behind every time you move |
| **Dies to** | Sieges, mutation waves, local depletion | **Fuel**, breakdowns, and attrition |

A fixed colony is a machine for producing surplus that eventually cannot defend itself. A convoy is a
machine for outrunning consequences that eventually cannot refuel.

**Most runs will do both** — a fixed base plus an expedition vehicle — and the design treats that as
the natural default rather than a compromise.

## The volume budget

Interior volume is the constraint that makes fitting out a mobile base a build rather than a shopping
list. Modules compete for space with each other *and* with cargo capacity.

| Base | Module slots | Practical use |
|---|---|---|
| SUV | 1 | A bunk, or a little cargo. Barely a mobile base. |
| Van | 3 | The workhorse. Real choices, real compromises. |
| Ambulance | 3 *(one pre-fitted medical)* | Strong start, less freedom |
| Box truck | 6 | A genuine rolling home, and audible for a mile |
| Bus | 8 | Everything you want, and it can barely climb a hill |

Every module fitted is cargo capacity lost — so a fully-equipped bus is comfortable and brings almost
nothing home, which is exactly the tension worth designing around.

## Modules

| Module | Provides | Cost |
|---|---|---|
| **Bunk** | Real sleep. Without one, [rest](04-survival-needs.md) recovery is poor and never fully recovers. | Volume, per person |
| **Water tank** | Storage plus rain collection | Volume; heavy when full |
| **Stove** | Cooked food, boiled water | **Scent in an enclosed space**, fire risk, fuel |
| **Workbench** | [Modification and repair](11-crafting.md) on the road | Volume; **worse outcome odds** than a fixed bench |
| **Medical station** | Proper [treatment and surgery](05-health-injury.md) away from home | Volume; still worse than a real clinic |
| **Storage racks** | Organized capacity, reduced spoilage | Volume — the honest trade |
| **Radio** | [Faction](18-factions.md) contact, [weather](16-weather.md) forecasts | Volume, power |
| **Aux fuel tank** | Range — **the module that decides how far you can go** | Volume, weight, and it is a fire risk |

**Design note:** the aux fuel tank is the nomad keystone. It converts volume directly into range, and
range is the nomad's only real defense.

## Parked

A parked mobile base is where nomad play is most dangerous, and it deserves specific rules.

- **The engine off is the only quiet state.** Idling for heat or power is a continuous 150+ noise
  emission next to where everyone is sleeping.
- **You are in a metal box.** Being surrounded means you cannot leave, and cannot fight from anywhere
  but a doorway — the vehicular version of being cornered indoors.
- **No escape routes.** A fixed base has multiple exits and firing positions by design. A van has two
  doors and no sightlines.
- **Driving away is the answer**, and starting the engine in a crowd means noise, a slow start, and
  bodies under the wheels.

So the nomad's safety is entirely in *site selection and readiness to move*, not in fortification.
Park facing out. Park where you can reverse. Don't park downwind of anything.

## Convoys

Multiple vehicles let a large group move together, and scale the trade-offs rather than removing them:

- Capacity and module space multiply
- **Noise stacks** — a three-vehicle convoy is unmissable
- Fuel consumption multiplies, and the convoy moves at the speed of its worst vehicle
- One breakdown halts everyone, or forces the group to split
- More people means more [scent](03-attention.md), wherever you stop

A convoy is a town that never stops announcing itself. It works, and it is never subtle.

## Running the colony while you're away

The user's stated purpose for all of this: long expeditions while NPCs keep the base running.

That already works — NPCs work the [priority grid](07-survivors.md#work-the-priority-grid)
autonomously, and [Focus auto-allocation](07-survivors.md#focus-and-auto-allocation-the-anti-micromanagement-rule)
means they maintain their own loadouts. What extended absence adds:

- **You aren't there when night falls at home.** The [attention field](03-attention.md) and the
  [director](17-director.md) resolve the night without you. You find out at dawn, over the radio if you
  have one, or when you get back.
- **You took the capable people with you.** The expedition/garrison split
  ([core loop](02-core-loop.md)) stops being a day-long tension and becomes a week-long one.
- **Coming home to a breach you weren't present for** is a designed beat — the colony half of the game
  producing consequences while the RPG half was elsewhere.
- **Supply lines are real.** The expedition eats, drinks, and burns fuel. Provisioning for eight days
  away means eight days of food that the colony doesn't have.

## How nomads die

The failure mode must be as specific as the siege is for fixed colonies, or "just drive away" becomes
the correct answer to everything:

1. **Fuel runs out.** You are now a fixed base with no walls, no farm, and no forge, parked wherever
   you happened to stop. This is the death spiral's first step and it's usually irreversible.
2. **A breakdown far from anywhere.** No workshop, limited parts, and a repair job in the open.
3. **Attrition.** Worse sleep, worse food, no personal space. Mood declines steadily and nothing
   about nomad life reverses it.
4. **Regional depletion.** Nomads produce nothing. When the region is stripped —
   [and it will be](13-world-decay.md) — the farmers are still eating.
5. **Getting boxed in.** A blocked road ahead, a crowd behind, in a vehicle that needs twenty metres to
   turn around.

## Relocation

For fixed colonies, vehicles make **moving the whole operation** practical rather than theoretical —
which matters once [trackers](14-zombies.md) find you, or the local sites are exhausted, or the
[decay clock](13-world-decay.md) has made the site untenable.

Relocation is expensive: multiple trips or a convoy, everything not carried is abandoned, and the new
site has no walls. But it converts "this base is finished" from a run-ending problem into a hard
decision, which is the better version of that moment.

## Content shape

Modules, volume budgets, and per-base slot counts are JSON ([content](20-ecs-and-content.md)). A module
declares its volume cost, what it provides via [modifiers](21-extensibility.md), and its own emissions.

**Adding a module is a data entry** — provided what it provides is expressible as modifiers or as an
existing facility type.

## Cut list

- **Vehicle interiors as separately-rendered walkable spaces.** Modules are fitted and used; you don't
  walk around inside a van at tile resolution.
- **Towed trailers as second mobile bases.** A hitch adds cargo, not modules. Revisit post-1.0.
- **Nomad-specific [factions](18-factions.md) or a nomad progression track.** The playstyle uses the
  same systems; it doesn't get a parallel one.
- **Vehicle-to-vehicle transfer while moving.** No.
- **Sleeping in shifts while driving through the night.** Tempting, and it removes the "where do we
  stop" decision that makes nomad play tense.

---

**Previous:** [25 — Vehicles](25-vehicles.md) · **Next:** [19 — Architecture](19-architecture.md) ·
[Doc index](../README.md#documentation)
