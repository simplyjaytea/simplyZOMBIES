# 17 — The Director

*Why this exists: RimWorld isn't great because of its systems, it's great because Cassandra paces
them. Without a director, a survival sim degenerates into either a flat grind or an unwinnable slope.
This is the cheapest system in the design and the one with the largest effect on whether the game is
fun.*

---

## What the director is and isn't

**It is** a pacing system. It decides *when pressure rises and falls*, seeds events, and guarantees
that the run has a rhythm rather than a texture.

**It is not** a spawner. Per [zombies](14-zombies.md), the director never places a horde at your gate.
Where and when zombies arrive remains a consequence of the [attention field](03-attention.md). The
director adjusts regional pressure, migration, and composition; the field decides where that lands.

That distinction is load-bearing. It's what keeps a bad night feeling like a consequence of your
choices rather than a scripted punishment, which is what the
[fairness rules](01-hardcore-contract.md#fairness-rules) require.

**It is also not** the difficulty curve. [World decay](13-world-decay.md) provides the long-run
escalation on a fixed schedule and does not care how you're doing. The director works *within* that,
handling the short-term shape.

| System | Responds to player? | Timescale | Job |
|---|---|---|---|
| Attention field | Directly and immediately | Seconds–days | Where threat goes |
| Director | Yes, adaptively | Days–weeks | When pressure rises and falls |
| World decay | **No** | Weeks–months | The long escalation |

## What it reads

Each cycle the director estimates **colony power** and **colony strain**:

**Power:** population and their [web depth](08-skill-web.md) · [gear tier](10-items.md) and coverage ·
[fortification](15-base-building.md) quality and upkeep state · food and water reserves ·
ammunition and [fuel](12-resources.md) stock · medical supplies.

**Strain:** injuries and infections in progress · mood across the colony · recent casualties · how far
the [scavenging radius](12-resources.md) has pushed · [attention](03-attention.md) footprint over the
past week · nights since the last quiet one.

Note that strain includes attention footprint — so a colony that has been noisy has both *earned*
pressure through the field and is *read as* ready for more. Those compound deliberately.

## What it does

The director doesn't pick a number for the night. It maintains a set of dials and seeds events:

| Lever | Effect |
|---|---|
| **Regional pressure** | How many zombies exist in the area at all — migration in or out |
| **Composition** | Which types are in the mix, bounded by the [mutation wave](13-world-decay.md) |
| **Migration events** | A distant crowd starts moving through the region — arriving somewhere the field decides |
| **Site seeding** | An untouched building appears in the scavenging pool; relieves the radius squeeze |
| **Encounters** | Survivors met on runs, [recruits](07-survivors.md), [faction](18-factions.md) contacts |
| **Unique appearances** | The gated arrivals of [unique survivors](07-survivors.md) and named items |
| **Grace** | Actively suppressing pressure after something devastating |

## Pacing rules

The parts that matter most, stated as hard constraints:

### 1. Guaranteed lulls
After a night that costs the colony badly — deaths, a breach, a major structure loss — the director
**suppresses pressure for a period**. Not because it's kind, but because unrelenting pressure reads as
noise rather than tension. The quiet after a disaster is when the player feels the loss, rebuilds, and
starts caring again.

Without this rule, a colony in a bad spiral simply dies, and the player learns nothing except that they
lost.

### 2. The grace period
Week one is quiet. The player learns the map, finds a base, works out what the interface means.
Fatalities in week one are earned by ambition, not by the schedule.

### 3. Escalating quiet
Extended quiet stretches raise pressure — but slowly, and always with warning signs a scout can read.
The player who turtles perfectly gets a slow squeeze, not a sudden ambush. The squeeze mostly arrives
via [world decay](13-world-decay.md) rather than the director, which is the honest way to do it.

### 4. Variance floor and ceiling
Nights are never *all* quiet or *all* siege. The director maintains distribution bounds so that both
"nothing has happened in ten days" and "every night is a siege" are impossible states.

### 5. Never rubber-band silently
The director's adjustments must be explicable and, in principle, observable. It does not scale zombie
health to your gear or make the RNG kinder because you're losing. Per the
[hardcore contract](01-hardcore-contract.md), any difficulty adjustment the player can't reason about
is prohibited.

## Storytellers

Presets that change the director's *personality*, alongside the
[sandbox settings](01-hardcore-contract.md#sandbox-settings) that change raw parameters.

| Storyteller | Character |
|---|---|
| **The Slow Winter** | The default. Steady, patient escalation. Real lulls, real sieges, gradual squeeze. The balance target. |
| **Hard Rain** | High variance. Brutal spikes and generous recoveries. Dramatic, streaky runs. |
| **The Long Quiet** | Low pressure, heavy reliance on [world decay](13-world-decay.md) for difficulty. A colony-management-forward run. |
| **Nothing Personal** | The director's adaptive layer is off entirely. Fixed schedules, pure attention-field consequences. For players who consider adaptive pacing a form of cheating — and useful as a balance baseline. |

**Nothing Personal** doubles as a testing tool: if the game is unplayable with the director disabled,
the underlying systems are mistuned and the director is papering over it.

## Event seeding

Events are the director's narrative surface. Each is a JSON entry
([content](20-ecs-and-content.md)) with trigger conditions, weights, and effects.

Examples: a survivor at the gate during a bad night · a distant gunfight audible to the north · smoke
on the horizon · a trader's radio contact · an untouched pharmacy spotted on a run · a
[faction](18-factions.md) asking for help · a wounded stranger who is *maybe* bitten.

Events are gated on colony state, so the game asks questions the colony is positioned to find hard: the
refugee arrives when food is short, the trade offer comes when antibiotics are gone. Not because the
director is cruel, but because a decision is only interesting when it costs something.

## Content shape

The director is data-configured: power/strain weightings, pacing constraints, storyteller presets, and
the event pool are all JSON. Tuning pacing is a data pass.

The director is also a **module**, per the [kernel rule](19-architecture.md) — the game runs with it
disabled (that's the Nothing Personal preset), which keeps it from becoming load-bearing for anything
except pacing.

## Verifying it works

Because the simulation is [deterministic](19-architecture.md), the director is testable in a way most
pacing systems aren't: run a thousand headless colonies across seeds and storytellers, and measure the
distribution of quiet nights, sieges, deaths, and run lengths. Pacing regressions become a number that
moved, rather than a feeling someone reports. See [performance](22-performance.md) and the
[roadmap](23-roadmap.md).

## Cut list

- **Narrative scripting / authored story arcs.** Contradicts [vision](00-vision.md).
- **Difficulty scaling of zombie stats to player power.** Explicitly prohibited by rule 5.
- **A visible director state / threat meter.** Violates the information rule.
- **Director-controlled weather.** [Weather](16-weather.md) runs on its own seasonal distribution; the
  director doesn't get to summon a storm for drama.
- **Multiple simultaneous directors** (one for zombies, one for factions). One pacing authority.

---

**Previous:** [16 — Weather](16-weather.md) · **Next:** [18 — Factions](18-factions.md) ·
[Doc index](../README.md#documentation)
