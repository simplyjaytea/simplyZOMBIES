# 09 — Combat

*Why this exists: the design requires melee and ranged to both be good, permanently, at every stage.
That doesn't happen by accident — it happens because each pays a different, non-substitutable
currency. This document defines that contract and the mechanics that enforce it.*

---

## The parity contract

The naive approach — "guns are loud, so melee is viable" — is a *nerf to ranged*, not parity. It makes
guns an emergency button and melee the default, which is one playstyle wearing two hats.

Real parity requires each side to spend something the other doesn't, where neither currency is
convertible into the other:

|  | **Melee** | **Ranged** |
|---|---|---|
| **Pays with** | Stamina, injury, and **bite risk** → [infection](06-infection.md) | Finite **ammo** and **[attention](03-attention.md)** → tonight's horde |
| **Spends** | The present — your body, possibly a person | The future — your stock and your next night |
| **Strength** | Silent, endlessly repeatable, scales hard with web and affixes | Kills at zero personal risk; the only answer to what you cannot let close |
| **Weakness** | You are inside the thing's reach | Every shot withdraws from two accounts that don't refill |
| **Fails against** | Numbers, and anything that hits harder than you heal | Poverty, and being surprised at four metres |
| **Best at** | Attrition, quiet clearing, sustained defense | Emergencies, breaches, armored mutations, protecting someone else |

**The test:** if a player can beat the game while never firing a gun *or* while never swinging a
weapon, one of these is undertuned. Both must be indispensable, at hour 2 and at hour 60.

## The melee model

### Swing loop
Wind-up → connect or miss → recovery. All three are interruptible windows, and being caught in
recovery is how melee kills you.

- **Stamina** per swing, scaled by weapon weight. Exhausted swings are slow, weak, and miss.
- **Stagger** — landing a solid hit interrupts the target. Blunt weapons stagger better; blades kill
  faster. Stagger is the actual survival mechanic in a crowd, because a staggered zombie isn't
  grabbing you.
- **Reach** governs whether you can hit before being hit. A spear outranges a knife and that matters
  more than damage.
- **Kill quality** — a clean head strike is instant; anything else takes multiple hits from a thing
  that is still trying to bite you.

### Grabs
Zombies grab. A grabbed survivor cannot move or swing until they break free, which costs stamina and
takes time. **Grabs are the primary bite vector**, and being grabbed by two at once is usually
terminal.

This is what makes crowds categorically dangerous rather than just numerically dangerous: fighting one
is a skill check; fighting three is a check you fail once and then can't retry.

### Bite risk
Every melee connect carries a small chance of taking damage back, and every damage-taken carries a
chance of being a [bite](06-infection.md). Reduced by reach, stagger, [armor coverage](10-items.md),
and Melee-region [web nodes](08-skill-web.md).

**Melee's progression is fundamentally about buying down this number.** A veteran with reach, stagger
control, and coverage fights a long night and comes back unbitten — usually.

### Noise
Melee is nearly silent (~8 per connect vs. ~180 for an unsuppressed shot). A colony that clears its
approaches with axes at dusk earns a quiet night. That's the reward, and it costs bodies.

## The ranged model

### Shot loop
Raise → steady → fire → recover → (reload). Steadying takes real time and is ruined by movement,
exhaustion, pain, injured arms, and being hit.

- **No crosshair certainty.** Accuracy is a cone that tightens with steadiness, skill, weapon
  condition, optics, and light. You are never told the hit chance.
- **Reloading is slow and interruptible.** Reloading with something ten metres away is a decision, not
  a reflex.
- **Weapon condition matters.** Degraded firearms jam, and clearing a jam takes longer than a reload.
  See [items](10-items.md).

### The two costs

**Ammo** is finite. Late-game hand-loading is possible and produces *worse* ammunition — reduced
power, higher jam chance. There is no point at which ammo stops being precious.

**Attention** is the big one. An unsuppressed shot is 180 noise, an order of magnitude above anything
else you do routinely, plus a 60-magnitude muzzle flash at night. **Firing a gun is a decision about
tonight**, and firing a gun *during* the night is a decision about how much worse this night gets.

The result: ranged is the emergency tool that trades tomorrow for right now. Which is genuinely
powerful — sometimes there is no tomorrow unless you spend it.

## The quiet branch — a third option, not an upgrade

Bows, crossbows, suppressors, subsonic loads.

| Property | Effect |
|---|---|
| Noise | Bow ~4; suppressed firearm ~40 (vs. 180) |
| Ammunition | Arrows and bolts are **recoverable** — the only renewable ranged ammo |
| Rate of fire | Much slower; crossbow reloads are punishing |
| Stopping power | Poor against [armored and heavy mutations](14-zombies.md) |
| Suppressor cost | Wears out fast, degrades accuracy, occupies a barrel [attachment slot](10-items.md) |

So the quiet branch buys attention relief and pays in throughput and reliability. It's excellent for
scouting, clearing approaches, and eliminating [screamers](14-zombies.md) before they scream — and it
gets you killed in a breach.

**Three viable answers, none dominant.** That's the shape.

## Night tactics: why mixed loadouts win

The [night phase](02-core-loop.md) is authored so that neither side alone is sufficient:

- **Ranged on the walls** thins the approach before contact — and every shot raises attention, which
  draws more of them toward the wall you're shooting from. Shooting more makes the night bigger.
- **Melee at the breach** handles what gets through, silently, but puts your people in bite range in
  the dark.
- **Lights** make ranged effective at night and are a massive attention emitter. Fighting in the dark
  is quiet and inaccurate.

Correct play is a *composition*: a couple of shooters with discipline about when to fire, melee
holding the chokepoints, and a decision each night about whether tonight is worth spending on.

## Zombie combat behavior

Details in [zombies](14-zombies.md); the combat-relevant parts:

- They do not flinch from injury, only from mass — stagger works, fear doesn't.
- They don't flank tactically; they flow up the [attention gradient](03-attention.md), which means
  **your own noise decides where they arrive**.
- Damage is meaningful only to the head or by destroying locomotion. A zombie with a shattered pelvis
  crawls and is still lethal at ankle height, which is a real and unpleasant threat during a breach.
- Numbers are the difficulty. Individually they are slow and stupid; in a crowd they are a wall of
  grabs.

## Player-directed vs. NPC combat

- **You control one survivor directly** — aim, swing, back off, reload, break a grab.
- **NPCs fight autonomously** from their post and Focus, using their loadout and web. They break off
  when critically injured, per traits.
- **Pause** is unlimited and lets you reposition and re-post everyone. Positioning is the tactical
  layer; the game is never about clicking fast.

## Cut list

- **Damage numbers, hit chances, or floating combat text.** Violates the
  [no-numbers rule](01-hardcore-contract.md#4-information-is-scarce-and-unreliable).
- **Dodge rolls / i-frames.** Wrong genre; escape is positional, not acrobatic.
- **Directional blocking as a timing minigame.** Blocking exists as a stance with a stamina cost, not
  a parry window.
- **Human-vs-human combat depth.** Deferred with [factions](18-factions.md).
- **Explosives as a mainline option.** They exist as rare loot; 400 noise makes them self-limiting,
  which is the joke.

---

**Previous:** [08 — The Skill Web](08-skill-web.md) · **Next:** [10 — Items](10-items.md) ·
[Doc index](../README.md#documentation)
