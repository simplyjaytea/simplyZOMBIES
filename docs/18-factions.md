# 18 — Factions

*Why this exists: other survivors are a fundamentally different threat shape from zombies — they open
doors, they take rather than eat, and they can be negotiated with. This is the largest post-slice
system in the design, and the game must be good without it.*

**Status: post-slice.** Everything here is designed but explicitly deferred. See the
[roadmap](23-roadmap.md).

---

## Why factions are deferred, not cut

They add the best late-game beats in the design — a raid landing *during* a horde night is the single
most dramatic situation these systems can produce. But they also depend on human combat AI, dialogue,
diplomacy state, and trade economy, none of which the core loop needs.

**Test:** if the game isn't good with only zombies, factions won't fix it. So they ship after the core
is proven.

### What multiplayer changes about that, and what it doesn't

[PVP](27-multiplayer.md#what-pvp-is-and-is-not) is survivor-versus-survivor, and it needs the same
thing a raider needs: a human being shot at, injured, and killed by the ordinary
[combat model](09-combat.md). That resolution is
[no longer deferred with this document](09-combat.md#cut-list) — PVP is its first customer, and it
arrives without waiting for anything here.

**Nothing else moves.** Raider *approach* AI — scouting, picking a line, avoiding known traps,
withdrawing once loaded — is the expensive half and it stays post-slice. What changes is the
ordering argument, not the status: when factions are finally built, the part of them that is "a human
who can be fought" will already exist, and what is left to build is the part that makes them
[a different threat shape](#why-humans-are-a-different-threat).

The counter to a raid — *"watch coverage and sightlines, not chokepoints"* — is also
[a system now](28-visibility-and-sightlines.md) rather than a phrase, for the same reason.

## Why humans are a different threat

| | **Zombies** | **Raiders** |
|---|---|---|
| Navigation | Ascend the [attention gradient](03-attention.md) | Scout, plan, and pick an approach |
| Doors | Break through | **Open them** |
| Walls | Grind against them | Go around, over, or through the gate |
| Goal | Reach you | **Take your things** and leave |
| Numbers | Overwhelming | Few, competent, armed |
| Retreat | Never | When it stops being worth it |
| Counter | Geometry, traps, chokepoints | Watch rotations, sightlines, and being a hard target |

Everything you built to stop the horde is the wrong shape for raiders. A killbox funnels the dead into
a trap; raiders look at it, walk around, and come in the side. **Defending against both at once is a
genuinely different design problem**, and that's the whole reason this system exists.

## Faction types

| Type | Disposition | Interaction |
|---|---|---|
| **Traders** | Neutral, self-interested | Barter, information, forecasts, rare [consumables](11-crafting.md) |
| **Settlement** | Wary, potentially friendly | Trade, joint defense, [recruits](07-survivors.md), unique survivors |
| **Scavengers** | Opportunistic | Compete for the same sites; sometimes trade, sometimes rob |
| **Raiders** | Hostile | Take supplies, take people, take gear |
| **Remnant authority** | Unpredictable | Military or government leftovers. Demand rather than trade. |

## Relations

A per-faction standing driven by trade, aid given or refused, competition over
[sites](12-resources.md), raids repelled, and prisoners taken or released.

Relations decay toward neutral over time — nobody stays grateful — so alliances need maintenance and
grudges eventually fade. Trade is the primary lever and the reason to keep anyone friendly: factions
are the only source of [Salvage Rights](11-crafting.md) and a reliable route to antibiotics after the
medical sites are stripped.

## Raids

Raids are announced by scouting activity, missing supplies, and watchers on the treeline — never
unheralded, per the [fairness rules](01-hardcore-contract.md#fairness-rules).

Raiders:
- Approach deliberately, avoiding known traps and covered approaches
- Prefer the [gate](15-base-building.md) or an unwatched wall section
- **Target stores first**, people second, and will withdraw once loaded
- Retreat when losses outweigh the haul — they're not a horde, they're a business

Defending against a raid is about **watch coverage and sightlines**, not chokepoints. Which means a
colony optimized for hordes has to build a second, overlapping defensive posture — the interesting
problem.

### The signature beat: a raid during a siege

The director may land a raid on a night the [attention field](03-attention.md) has already loaded. Now
the horde is at the wall and people are coming through the back, and every defender you commit to one
is unavailable for the other.

This is the best situation these systems can produce, it's rare, and it's why factions are worth
building eventually.

## Trade

Barter only — no currency ([resources](12-resources.md)). Factions have needs and surpluses that shift
over time and with [world decay](13-world-decay.md), so what's valuable changes across a run. Fuel and
antibiotics appreciate enormously in the late game; food fluctuates with the seasons.

Trade is also the main route to a **radio**, which gives [weather forecasts](16-weather.md) and
faction news — one of the few legitimate ways to reduce the game's uncertainty.

## Prisoners and defectors

Raiders can be captured. A prisoner eats, needs a secure space (the same one you built for
[quarantine](06-infection.md)), and can eventually be recruited — arriving with real skills, unlike a
generic [recruit](07-survivors.md), and with relationship penalties from anyone who lost someone in the
raid.

Your own survivors can leave for a faction if mood collapses, taking their gear. Losing a developed
survivor to misery rather than to teeth is a distinct and deserved kind of failure.

## Content shape

Factions, dispositions, trade tables, raid compositions, and dialogue are JSON
([content](20-ecs-and-content.md)). Raids reuse the existing combat, pathing, and AI systems with a
different behavior tree — which is why this is expensive but not architecturally disruptive.

Per the [module rule](19-architecture.md), the entire faction system is disableable, and the slice
ships with it off.

## Cut list

- **Full diplomacy** (alliances, treaties, tribute, wars between factions you observe). Post-1.0 at
  best.
- **Player-initiated raids on faction settlements.** Cut at the [vision](00-vision.md) level.
- **Faction territory control on a strategic map.** Wrong scale.
- **Dialogue trees.** Interactions are menu-based offers and outcomes, not conversation.
- **Faction-specific zombie behavior or a faction that controls zombies.** No.

---

**Previous:** [17 — The Director](17-director.md) ·
**Next:** [24 — World & Scale](24-world-and-scale.md) · [Doc index](../README.md#documentation)
