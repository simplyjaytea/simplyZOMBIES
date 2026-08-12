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
Zombies grab at physical contact (1 m centre-to-centre). A grabbed survivor cannot move or swing
until they break free, which costs stamina and takes one committed second. `F` is contextual: swing
while free, struggle while held. **Grabs are the primary bite vector.**

Every additional grabber adds its strength to the same escape contest. It makes escape progressively
less likely, but never imposes a hard zero: one default shambler gives a two-thirds chance, two give
one-half, and three give two-fifths. A successful struggle throws off every current hold. Future
survivor progression may raise the escape-power side of this contest through **Strength**; that is a
roadmap hook, not current Milestone 1 behaviour.

This is what makes crowds categorically dangerous rather than just numerically dangerous: fighting one
is a skill check; fighting three is a check you fail once and then can't retry.

### Bite risk
Melee has no invisible per-hit counterattack roll. Exposure is physical: at reach, or while a stagger
keeps the zombie off balance, a connecting swing is safe; letting one close to grab range creates the
bite window. The first bite lands after 1.5 seconds and further bites every 2 seconds while the hold
continues. A bite currently has an 85% private transmission roll, and 30% of real bites initially
present as scratches. [Armor coverage](10-items.md), richer diagnosis and the full
[infection timeline](06-infection.md) arrive in Milestone 2.

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

## Aiming

Both models above describe what a weapon *does*. Neither says how the player points it, and that gap
is where a game of this shape usually acquires a reticle with a hit percentage under it.

### Facing is the input

A survivor has a heading — the same heading
[visibility](28-visibility-and-sightlines.md#what-an-observer-is) is built on, specified there once
and read here. Aiming is turning that heading toward something and holding it, and the
raise → steady → fire → recover loop is what the holding *is*: the cone tightens while you keep it
pointed and while you keep still, and it opens the moment either stops being true.

This makes the loop's interruptibility physical rather than administrative. Being shoved, being
grabbed, or breaking into a [sprint](29-movement-and-stances.md) does not cancel an abstract
"aiming state" — it moves the muzzle, and the cost is the steadiness you had accumulated.

### The cone is felt, not drawn

**No reticle that reports its own accuracy.** No expanding crosshair calibrated in degrees, no hit
chance, no floating damage. What the player reads instead:

- **Weapon sway** — the barrel's own movement, which *is* the cone, drawn as the thing rather than as
  a number about the thing. A steady survivor's weapon is visibly still. An exhausted one with a
  wounded arm is visibly not.
- **Where the shots go.** Missing at fifteen metres because you fired the instant you raised is a
  lesson the player can learn without ever being shown a percentage.

This is the [no-numbers rule](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) paying
for itself rather than costing something: sway communicates steadiness continuously, in the same
glance as the situation, which a number in a corner does not.

### Melee aims too

Reach and swing arc read from the same facing. This is what makes
[reach](#the-melee-model) legible as a property rather than a stat on a sheet — a spear connects
from where a knife does not, and the player sees exactly that rather than reading it in a tooltip.
It is also what makes being surrounded lethal in the way
[clause 1](01-hardcore-contract.md#1-you-are-weak-permanently) promises: your arc covers one of them
at a time, and the other two are outside it.

### What you cannot see, you cannot aim at

Aiming inherits [visibility](28-visibility-and-sightlines.md) wholesale. Firing at a body you
remember rather than one you can see is allowed, and it is a decision with a cost — the shot is 180
noise and 60 of muzzle flash whether or not anything was still standing there.

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
- **Human-vs-human combat *depth*.** Scoped rather than deferred outright, now that
  [multiplayer](27-multiplayer.md) exists as a specification. What stays deferred with
  [factions](18-factions.md) is the expensive half: raider approach AI, morale, surrender, and
  NPC-vs-NPC engagements. What is *not* deferred is survivor-versus-survivor resolution, because
  [PVP](27-multiplayer.md#what-pvp-is-and-is-not) needs it and factions still do not ship — and it
  needs nothing new, since a player survivor is hit, injured, and killed by the model this document
  already describes. It is gated on the melee loop existing at all, not on factions.
- **Explosives as a mainline option.** They exist as rare loot; 400 noise makes them self-limiting,
  which is the joke.

---

**Previous:** [08 — The Skill Web](08-skill-web.md) ·
**Next:** [29 — Movement & Stances](29-movement-and-stances.md) ·
[Doc index](../README.md#documentation)
