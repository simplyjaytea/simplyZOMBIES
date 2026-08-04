# 00 — Vision

*Why this exists: to state what the game is in one page, so every later document can be checked
against it. If a proposed feature doesn't serve a pillar below, it doesn't go in.*

---

## The pitch

You control one survivor in a dead town. You can recruit others, and together you fortify a place to
sleep. Every comfort you build — a fire, a light, a generator, a gunshot — is a signal, and the dead
follow signals. The better you live, the harder they come.

You will not win. You will last a while, and then something will go wrong, and the story of how it
went wrong is the game.

## The five pillars

**1. You are prey.**
Not a hero, not a soldier, not eventually a god. One zombie is dangerous. Three is probably fatal. A
fully-developed veteran is *competent*, never invincible. Every design decision that would make the
player feel powerful gets checked against this pillar first.

**2. Comfort is the currency of danger.**
The [attention field](03-attention.md) is the spine of the whole game. Warmth, light, cooked food,
electricity, gunfire, more people, unburied corpses — all of it emits noise, light, or scent, and the
horde walks up that gradient. Survival and tower defense aren't two systems glued together; they're
the same system read from two directions.

**3. Investment, not headcount, is what you lose.**
Survivors are unlimited and [procedurally generated](07-survivors.md). New ones arrive knowing
nothing, owning nothing, and eating immediately. What death actually costs you is the hours you sank
into someone — their [skill web](08-skill-web.md) and the [gear](10-items.md) you built onto them.
That's what makes [infection](06-infection.md) hurt.

**4. The world decays on a clock you don't control.**
The grid fails. Water stops. Food rots. Tools break. Scavenging sites empty out and push you further
from home. The virus mutates and the horde gets worse on its own schedule. Every stable equilibrium
you build has an expiry date, and that's what stops hour forty from being a farming simulator. See
[world decay](13-world-decay.md).

**5. Everything is a module.**
The design changed substantially four times before a line of code existed, and it will change again.
The tick loop and the attention field are the kernel; every other system plugs in and can be pulled
out. See [architecture](19-architecture.md) and [extensibility](21-extensibility.md).

## Genre, honestly

Four influences, and what each one contributes:

| Influence | What we take | What we leave |
|---|---|---|
| **Project Zomboid** | Lethality, slow deliberate actions, injury depth, imperfect information, permadeath | Its map scale and its 3D isometric fidelity |
| **RimWorld** | Colony job priorities, pawn traits and relationships, the storyteller/director | Its comedy tone; its readiness to let you snowball |
| **Tower defense** | Building fortifications that channel and kill, bait and routing as skill expression | Fixed wave timers and a build-phase/fight-phase split |
| **Path of Exile** | Gear-as-build, rolled affixes, materials-as-currency, no classes | Its power curve, its speed, its economy |

## What this game is **not**

Stated because each of these is a thing the design will drift toward if unattended:

- **Not a power fantasy.** There is no build that trivializes the game. If one appears in playtesting,
  it's a bug.
- **Not a base-decorating game.** Building is defensive engineering, not interior design. Every
  structure earns its place by changing how the horde moves or how long people survive.
- **Not a story campaign.** There is no plot, no cure quest, no chosen one. The director generates
  situations; the player supplies the narrative.
- **Not a wave shooter.** Nights aren't a timer counting down to a fight. Most nights are quiet and
  tense. The bad ones are earned.
- **Not a squad tactics game.** You control *one* survivor directly. The others are people with
  priorities, not units with orders.
- **Not RTS-scale.** A large colony is a dozen people, not a hundred, and the cap is economic rather
  than numeric.

## Scope honesty

This document set describes a game far larger than a first build. That's deliberate — it's a backlog,
not a promise. The [roadmap](23-roadmap.md) defines a vertical slice that proves the pillars with the
minimum content, and explicitly labels everything else post-slice.

If a decision must be made and this document doesn't settle it, the tiebreaker is pillar 1: choose the
option that leaves the player more afraid.

## Cut list

Deliberately excluded from the design entirely, not merely deferred:

- **Multiplayer.** Changes the pause model, the succession model, and the director's job. Not a
  "later" feature — a different game.
- **A cure, or any narrative resolution to the outbreak.** Contradicts pillars 1 and 4.
- **Base raiding by the player against other player colonies.** Faction raids go one direction; see
  [factions](18-factions.md).
- **Vehicles.** Tempting, and they'd wreck the attention economy and the map scale at once. Revisit
  only after the slice proves out.

---

**Next:** [01 — The Hardcore Contract](01-hardcore-contract.md) ·
[Doc index](../README.md#documentation)
