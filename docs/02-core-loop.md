# 02 — The Core Loop

*Why this exists: four genres need one rhythm, or the game is four games taking turns. This document
defines that rhythm — the daily ratchet where every choice made in daylight is collected after dark.*

---

## The ratchet

A day has four phases. They are not modes — the simulation never stops and you can do anything at any
time — but each phase has a distinct pressure, and the game's texture comes from the handoff between
them.

```
   DAWN            DAY                    DUSK           NIGHT
   ~30 min ────────────────────────────── ~30 min ──────────────────
   aftermath       the colony half        preparation    the defense half
   triage          scavenge & work        commit         survive
   │                                                                │
   └──────────── what you spent ──────────► what comes for you ─────┘
```

The ratchet: **what you did in daylight determines what arrives after dark**, via the
[attention field](03-attention.md). Cooking, building, running a generator, and firing a gun all
accumulate. Night collects.

## Phase 1 — Dawn (~30 minutes of a ~4 hour day)

Short, quiet, and administrative. The bill for last night arrives.

- **Triage.** Wounds get treated now or get worse ([health & injury](05-health-injury.md)). Bites get
  examined, and the [infection](06-infection.md) question opens.
- **Repairs.** Damaged barricades and walls are assessed. Damage that isn't repaired today is
  tonight's breach.
- **The dead.** Corpses inside the perimeter must be moved and burned or buried. Left alone they rot
  into scent, which raises attention, which brings more of them tomorrow. Burning them is fast, but
  smoke is *also* attention. There is no free disposal.
- **Mood fallout.** People who saw someone die, or who slept badly, or who ate nothing, register it
  now.

**Design intent:** dawn is where consequence becomes concrete. Nothing new threatens you; you simply
find out what last night actually cost.

## Phase 2 — Day (the long phase)

The colony half. Two things happen at once, in different places, and that split is the day's whole
tension.

### At home: the job queue

NPCs work autonomously against a RimWorld-style priority grid ([survivors](07-survivors.md)) —
building, farming, hauling, cooking, purifying water, treating the wounded, crafting, repairing. You
set priorities; you do not micromanage tasks.

### Away: the scavenging run

You personally lead a party off-site. This is where [resources](12-resources.md) come from, where
[gear](10-items.md) is found, where encounters and rare recruits happen, and where most
[skill web](08-skill-web.md) points are earned.

### The choice that makes the day work

**The people who fight best are the people who build best.** Take your capable survivors on the run
and the base is defended by the unskilled. Leave them home and the run is thin, which means less loot,
which means a worse tomorrow.

Compounding it: scavenging sites [deplete](13-world-decay.md), so runs get longer over time, and a
long run means being caught out at dusk — which is its own way to die.

## Phase 3 — Dusk (~30 minutes)

Short and decisive. The commitment phase.

- **Fortify.** Last barricades placed, gates shut, [traps](15-base-building.md) armed and baited.
- **Post.** Assign firing positions and melee stations. Who's on the wall, who's on the breach, who
  sleeps.
- **Ration.** Feed people, or don't. Feeding well costs food and produces cooking smoke; feeding badly
  costs mood and tomorrow's work output.
- **Decide about light.** Lights and heat make people rest properly and keep morale up. They are also
  the loudest thing you can do to the attention field short of gunfire. This choice, every dusk, is
  the game's central dilemma in miniature.

**Design intent:** dusk forces a commitment under incomplete information. You do not know what's
coming. You are guessing, from the noise you made today.

## Phase 4 — Night

The defense half — and, importantly, **there is no wave timer**.

### Nights vary

The [director](17-director.md) reads your accumulated attention footprint and colony strength and
decides what tonight is:

| Night type | Feel |
|---|---|
| **Quiet** | Nothing comes. Tense, because you don't know that until dawn. Earned by living like a rat. |
| **Wanderers** | A handful drift in along the gradient. Manageable, noisy to resolve, and the noise feeds tomorrow. |
| **Pressure** | A sustained trickle all night. Nobody sleeps well. Mood and stamina damage more than casualties. |
| **Siege** | A real horde, arriving on a bearing you can predict from where your attention is loudest. This is the tower defense game. |

You are never told which one you're getting. You infer it from how loud your week was.

### The feedback loop

Fighting at night generates attention — gunfire enormously, melee barely. So a bad night makes the
*next* night worse, unless you switch to quiet weapons and eat the risk of being in reach
([combat](09-combat.md)). This is the loop that keeps the ratchet turning rather than settling.

### Breach, not game over

Walls failing is not a loss screen. A breach means: zombies inside, structures destroyed, stores
eaten or spoiled, people bitten, and possibly your controlled character dead — in which case you
[succeed into another survivor](01-hardcore-contract.md#succession-what-happens-when-you-die) and keep
playing. The game continues, poorer.

## Time scale

| Unit | Real time | Notes |
|---|---|---|
| Full day | ~4 hours at 1× | Nobody plays at 1× the whole time |
| Dawn / Dusk | ~30 min each | Deliberately short — they're decision phases |
| Night | ~1 hour | Longer in winter (see [weather](16-weather.md)) |
| Speed controls | Pause, 1×, 3×, 10× | 10× auto-drops to 1× on any threat contact |

Pause is unlimited and pauses everything. This is a game about deciding under pressure, not about
clicking fast — the tension comes from irreversibility, not from APM.

**Design rule:** any mechanic that punishes the player for pausing is prohibited.

## What each genre gets from the loop

| Pillar | Where it lives | Where it's paid for |
|---|---|---|
| Survival | All phases — needs run continuously | Food and water consumed during the day |
| Colony sim | Day (job queue) | Dawn (repairing what the night broke) |
| Tower defense | Night, dusk (prep) | Day (materials scavenged for walls) |
| RPG | Day (runs, loot, web points) | Night (where the build is tested) |

Nothing is a separate mode. Each pillar's payoff phase is another pillar's cost phase.

## Cut list

- **A discrete build phase** where the world pauses for construction. Contradicts the "nothing is
  instant" clause of the [hardcore contract](01-hardcore-contract.md).
- **A visible horde forecast.** Considered and rejected — telling you a siege is coming in 3 days
  makes preparation tactical but kills the dread that makes attention management matter.
- **Seasons changing the phase structure.** Winter changes lengths and modifiers
  ([weather](16-weather.md)), not the four-phase shape.

---

**Previous:** [01 — The Hardcore Contract](01-hardcore-contract.md) ·
**Next:** [03 — The Attention Field](03-attention.md) · [Doc index](../README.md#documentation)
