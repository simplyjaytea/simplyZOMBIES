# 29 — Movement & Stances

*Why this exists: movement speed is currently two constants and a shift key, and at least five
designed systems want to modify it — [injury](05-health-injury.md), pain, exhaustion,
[encumbrance](10-items.md), and permanent conditions. More importantly, speed is already wired to
the [attention field](03-attention.md): walking emits 1 and sprinting emits 6. A number that is both
heavily modified and directly coupled to the spine mechanic is a system, not a constant.*

---

## The rule

> **A stance is a decision about the attention field, not a speed setting.**

This is the [vision's](00-vision.md) central trade in its smallest possible form. Getting somewhere
faster costs you noise, and noise costs you tonight. Every other movement mechanic in this document
exists to make that trade legible.

The corollary is a design rule: **no stance may be strictly better than another.** Sprint is not an
upgrade over walk, and crouch is not a free stealth mode — it is slower, which in a game about being
somewhere before dark is a real price.

## The five stances

| Stance | Speed | Noise | Reach of that noise | Stamina | Also |
|---|---|---|---|---|---|
| **Crawl** | Very slow | Lowest | Under a metre | Drains slowly; tiring to hold | Cannot swing or aim; passes below **Low** [cover](28-visibility-and-sightlines.md#what-blocks-sight) |
| **Crouch** | Slow | Very low | ~1 m | Neutral | Sight blocked by **Low** cover, in both directions |
| **Walk** | **2.1 m/s** | **1** | **1.4 m** | Neutral | The shipped default |
| **Jog** | Moderate | Low-moderate | A few metres | Slow drain | The stance most travel actually happens in |
| **Sprint** | **6.3 m/s** | **6** | **8.6 m** | Fast drain | Cannot aim; [stance changes take time](01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die) |

**The speeds moved, and the magnitudes did not.** This document previously said walk and sprint
"are shipped and do not move", at 1.4 and 4.2 m/s — the real-world figures. They were changed to
2.1 and 6.3 by the repo owner, on game feel: at a walking pace of 1.4 the district is a
three-and-a-half minute crossing and it plays slowly.

What protects the sentence that got overruled is *how* they moved. There is a single
[`PACE` multiplier in `src/sim/locomotion.ts`](../src/sim/locomotion.ts) and everything that moves
is scaled by it, so **every ratio this document rests on is unchanged**: sprint is still three times
walk, a shambler is still eight tenths of a walk, and the sprint threshold is still exactly halfway
between the two — derived now rather than the hardcoded `2.8` it used to be, which was the midpoint
of the *old* pair and would have silently stopped being the midpoint of anything. There is a guard
on that specifically.

**The noise magnitudes did not move and must not.** `walking: 1` and `sprinting: 6` are calibrated
against the field, and reach is a property of magnitude, not of speed. The one balance effect worth
naming: noise is emitted per tick rather than per metre, so moving faster shortens every exposure.
A large pace increase would quietly make stealth *easier*. At 1.5× the effect is small; anyone
reaching for 3× is making a balance change, not a game-feel one.

The three new stances still slot between and below, and they are still picked rather than measured.

Planned [Dexterity](23-roadmap.md#planned-survivor-attributes) may scale every rung, but it cannot ship
on top of the current per-tick footstep rule. Before DEX changes speed, movement attention must be
normalized by distance travelled or scaled equivalently. Otherwise faster survivors also spend fewer
ticks emitting noise over the same route, turning DEX into an unintended second stealth stat.

**All five are built.** `src/sim/stances.ts` is the ladder; `src/sim/modules/stance.ts` owns the rung
a body is on. What the build added that this document did not specify: **exhaustion is asymmetric**.
Jog and sprint drop to a walk when the pool empties, which is this document's own "sprint becomes
unavailable before it becomes slow" — but **crawl does not**, because it is "the last resort that is
not running" and forcing an exhausted crawler to stand up would take away the one option this
document says is always there. See
[the decision log](30-decisions.md#what-the-stance-ladder-and-the-condition-view-made-structural).

**They are calibrated, not derived** — the same admission [docs/27](27-multiplayer.md#the-registers)
makes about its voice registers, which were picked to sit in the right band against the shipped shout
at 120. These are picked to sit in the right band against the shipped walk and sprint, and they are
the first thing to tune once the mechanic is played. Deliberately no exact figures for the three new
rows here: writing them down would make them look measured.

**Reach is what the player experiences**, not magnitude, and since the
[surface layer](24-world-and-scale.md#the-ground) landed it is not a property of the stance alone —
the same walk carries 1.4 m on tarmac, 0.9 m on grass and 2.4 m across rubble. A stance is a
decision about the attention field; so is a route. Per
[the calibration](03-attention.md#scale-and-calibration), `reach = magnitude ÷ 0.7` metres in open
ground. Sprinting is audible from about eight and a half metres and walking from under a metre and a
half, which is why *"moving carefully genuinely works"* is already true and why a crouch that halves
walking's already-tiny footprint is a smaller upgrade than it sounds. **The large gap is between jog
and sprint**, and that is where the decision lives.

## Why crawl exists

Three things in the design already want it, and all three predate this document:

- [Docs/14](14-zombies.md#damage-model) has a crawler — *"a zombie with a destroyed pelvis crawls, is
  quiet, is easy to miss in a dark breach, and is still perfectly capable of biting an ankle."* If
  the dead can be at ankle height, the living can be too.
- [Doc 28's **Low** occluder class](28-visibility-and-sightlines.md#what-blocks-sight) — low walls,
  cars, window sills, rubble — needs something to be low *relative to*. Crawl and crouch are it, and
  they are the only way a flat 2D map gets a height without
  [z-levels](23-roadmap.md#deferred-z-levels).
- It is the last resort that is not running. In a game where escape is the primary survival tool and
  [legs are the worst place to be hurt](05-health-injury.md#body-parts-and-what-they-cost), a
  survivor whose legs are gone still needs a verb.

Crawling costs everything else: you cannot swing, cannot aim, and cannot break a
[grab](09-combat.md#grabs) worth the name. It is the stance you choose when being unseen is the only
thing left that helps.

## What modifies a stance's speed

Every one of these already exists as a designed consequence somewhere. The change is that they now
have one number to write to.

| Source | Effect |
|---|---|
| **Leg injury** ([docs/05](05-health-injury.md#body-parts-and-what-they-cost)) | Reduces speed; a fracture removes the fast stances entirely |
| **Foot injury** | Speed, and **noise** — [docs/05](05-health-injury.md) already says limping is loud |
| **Pain** | Broad reduction, compounding with everything else |
| **Exhaustion** | Sprint becomes unavailable before it becomes slow. Failure to run is the thing between a fight going badly and a fight killing you |
| **Encumbrance** ([docs/10](10-items.md)) | Speed down, noise up — a loaded survivor is a loud one |
| **Permanent limp** | The same, forever, on a survivor who is otherwise fine |

**Design rule:** all of it goes through the
[modifier pipeline](21-extensibility.md#mechanism-2-the-modifier-pipeline) with named sources — no
hardcoded multipliers anywhere. That pipeline already answers *"why is this stat this number?"* with
the full contribution list, which is exactly the question a player asks after failing to outrun
something, and exactly the question
[every death is explicable](01-hardcore-contract.md#fairness-rules) obliges us to be able to answer.

## How stances touch the rest of the design

- **Combat.** You cannot aim from a sprint and you cannot swing from a crawl. Changing stance is a
  [timed, interruptible action](01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die)
  like everything else, which means *committing* to a sprint is a real commitment — the mechanic
  clause 2 exists to produce.
- **Visibility.** Crouch and crawl interact with the **Low** occluder class in
  [doc 28](28-visibility-and-sightlines.md#what-blocks-sight), in both directions: cover that hides
  you also blinds you. *Built, and both directions came free — `shadowcast` is symmetric, so there is
  no way to write a crouch that sees out without also being seen over.*
- **[Multiplayer](27-multiplayer.md).** A stance is a command carrying an enum, ordered by
  `(tick, playerId, seq)` like every other. It serialises, replays and fingerprints exactly the way
  the [voice register](27-multiplayer.md#the-transport-split-and-determinism) does — and for the same
  reason, which is that it is an integer decision rather than an analogue one.
- **Zombies.** They already have stances in all but name: `src/sim/modules/shambler.ts` runs seek
  speed, wander at 0.35× and mill at 0.25×. Unifying those under the same model is how a
  [type's](14-zombies.md#types) speed becomes one more field in its JSON entry rather than three
  constants in a module.

## Cut list

- **A stamina bar, or any other bar.** Read stamina from breathing, from swing speed, and from the
  moment sprint stops answering. See [docs/05](05-health-injury.md#the-condition-view) and
  [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable).
- **Vaulting, climbing, and door-opening as stances.** They are
  [timed actions](01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die), which is a
  different and already-specified mechanic. A fence climb that costs a
  [sprain](05-health-injury.md#injury-types) is not a movement mode.
- **Acceleration and momentum modelling.** Wrong genre and a determinism liability for a feel
  improvement the camera would barely show.
- **Dodge rolls.** Already cut in [docs/09](09-combat.md#cut-list); restating it here because a
  stance list is exactly where one would try to sneak back in.
- **Per-stance stealth checks.** A stance changes what you emit. It does not roll against anything —
  the field is the only detection model this game has.
- **Per-stance surface interaction beyond what the ground already does.** The
  [surface layer](24-world-and-scale.md#the-ground) multiplies speed and footstep noise for every
  body that crosses it, whatever stance it is in. A table of five stances against five surfaces is
  twenty-five numbers nobody can hold, to express something two multipliers already express.

---

**Previous:** [09 — Combat](09-combat.md) · **Next:** [10 — Items](10-items.md) ·
[Doc index](../README.md#documentation)
