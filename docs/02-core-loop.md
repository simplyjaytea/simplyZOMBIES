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

## What is built

**The clock, the four phases, the dark, and the speed controls.** Not the content of any phase —
dawn has no repair queue, day has no job system, night has no director deciding what tonight is.
What exists is the rhythm those will hang from, plus the one mechanical consequence that could be
built with what the spine already has.

| Piece | State |
|---|---|
| Four phases in docs/02's proportions | **Built** — `src/sim/time/clock.ts` |
| `phase.changed` · `night.fell` · `day.started` | **Built.** The vocabulary declared all three in Milestone 0 with no publisher |
| Ambient light, ramping through dawn and dusk | **Built** |
| **A survivor sees less at night** | **Built** — 48 m at noon, 12 m at midnight |
| Speed controls: pause · 1× · 3× · 10× | **Built**, with 10× dropping to 1× on contact |
| Nights that vary by type | Needs the [director](17-director.md). Milestone 2 |
| Anything phase-*gated* | Never. See the rule below |

Three things are worth stating because they are decisions rather than implementation:

- **Time of day is a pure function of `world.tick`.** There is no clock state and nothing new in
  the save, so a save cannot disagree with the world it was taken in. Starting a run at dusk is not
  a setting; it is starting at a different tick. The price is that `world.tick` no longer means
  "ticks since the run began", and code wanting elapsed time has to subtract a start tick.
- **A run opens at 09:00, not at tick 0.** Tick 0 is the start of dawn, which is the *darkest*
  moment of the cycle. docs/02 opens its day at dawn because dawn is when the previous night's bill
  arrives — and a fresh run has no night behind it to send one.
- **Night is not a tint.** The survivor's view genuinely shrinks, because
  [range is a property of light](28-visibility-and-sightlines.md#what-an-observer-is). The screen
  darkens to *report* that, using the same ambient number, so the picture and the simulation cannot
  drift apart.

**And night is deliberately not dark enough yet.** Ambient bottoms out at a quarter of daylight
rather than near zero, because there is no [light channel](03-attention.md#light) — nothing to
carry, nothing to light, no counterplay. A survivor at zero would simply be blind with no answer
available. That number should go *down* the day lamps and torches exist, and until then the dark is
softer than the design wants it.

## Time scale

| Unit | Real time | Notes |
|---|---|---|
| Full day | ~4 hours at 1× | Nobody plays at 1× the whole time |
| Dawn / Dusk | ~30 min each | Deliberately short — they're decision phases |
| Night | ~1 hour | Longer in winter (see [weather](16-weather.md)) |
| Speed controls | Pause, 1×, 3×, 10× | 10× auto-drops to 1× on any threat contact |

**Four hours is a guess**, and has been flagged as one since the roadmap was written. It is one
constant — `DAY_SECONDS` — so answering the question is editing one line. It is also why the speed
controls are a prerequisite rather than a convenience: at 1× nobody in a development session will
ever see nightfall.

**Contact is a distance, not a sightline.** Ten metres of anything, whether or not the survivor can
see it. A sightline-based rule would fire constantly in daylight and stop firing at night — exactly
when a fast-forward is most dangerous — and "I was at 10× and never saw it" is not an explanation
of a death, it is a complaint about the time controls.

Pause is unlimited and pauses everything. This is a game about deciding under pressure, not about
clicking fast — the tension comes from irreversibility, not from APM.

**Design rule:** any mechanic that punishes the player for pausing is prohibited.

**Scope:** this rule governs single-player, completely. It cannot hold with more than one player —
vote-to-pause makes pausing a negotiation, and per-player pause is time travel, not pause. In
[multiplayer](27-multiplayer.md) time control is host-owned, the session runs at 1×, and speed
controls default off. That exception is the price of the mode and is paid there rather than here.

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
