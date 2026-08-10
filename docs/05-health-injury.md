# 05 — Health & Injury

*Why this exists: hardcore lives here. A game where damage is a bar that refills is not lethal, it's
attritional. This document defines the injury model that makes a single bad decision echo for two
weeks.*

---

## Core rules

1. **No health bar.** Not for the player, not for NPCs. There is a *body* with parts, and each part
   has conditions on it. Condition is communicated in prose and animation.
2. **Injuries are located.** A wound is on a limb, and which limb determines what it costs you.
3. **Healing takes days, not seconds.** Nothing regenerates passively at a meaningful rate.
4. **Treatment is a skill and a resource.** Both can be absent.
5. **Injured survivors consume without producing.** The real cost of a wound is measured in
   colony-days of lost work and eaten food.

## Body parts and what they cost

| Part | Impaired effect |
|---|---|
| **Head** | Concussion: blurred description text, slowed reactions, mood damage. Severe: unconsciousness. |
| **Torso** | Blood loss and stamina capacity. Deep torso wounds are the most lethal. |
| **Arms** | Melee power and accuracy, ranged steadiness, reload speed, carry capacity, work speed |
| **Hands** | Fine work — reloading, treating others, crafting, [item modification](11-crafting.md) |
| **Legs** | Movement speed. **This is the one that kills you**, because escape is the primary survival tool |
| **Feet** | Movement speed, stealth (limping is loud) |

**Design note:** legs are deliberately the worst place to be hurt. In a game where "run away" is the
correct answer to most encounters, taking that away is more frightening than any damage number.

## Injury types

| Injury | Cause | Effects | Treatment | Typical recovery |
|---|---|---|---|---|
| **Scratch** | Zombie claw, debris | Minor bleed, infection risk, **[possible bite ambiguity](06-infection.md)** | Clean, bandage | 2–3 days |
| **Laceration** | Zombie, sharp environment | Moderate bleed, pain, part impairment | Clean, suture, bandage | 5–8 days |
| **Deep wound** | Serious combat | Heavy bleed, high infection risk, severe impairment | Suture urgently; needs a skilled medic | 2–3 weeks |
| **Bite** | Zombie | As laceration, plus [zombie infection](06-infection.md) | See infection doc | N/A |
| **Fracture** | Falls, crush, heavy hits | Near-total loss of the part; **legs are catastrophic** | Splint, then immobility | 4–8 weeks |
| **Sprain** | Falls, fence climbs, exhaustion | Partial impairment | Rest, wrap | 4–7 days |
| **Burn** | Fire, cauterization | Pain, infection risk, impairment | Clean, dress, keep clean | 1–3 weeks |
| **Concussion** | Head impact | Reaction and perception loss | Rest, darkness, quiet | 3–10 days |
| **Hypothermia / heatstroke** | [Temperature](04-survival-needs.md) exposure | Global impairment, then collapse | Warmth/cooling, fluids | 1–3 days |

## The four continuous conditions

Alongside discrete injuries, four values run continuously:

### Blood loss
Accumulates from any bleeding wound until it's dressed. Causes weakness, then dizziness, then
unconsciousness, then death. **This is the acute killer** — bleeding out is the most common way a
survivor dies away from combat, because the party couldn't stop to treat them.

Bandaging is a [timed action](01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die),
which is why people die of it during a fight.

### Pain
Sums across all injuries. Degrades everything — accuracy, work speed, mood, sleep quality. Painkillers
suppress it without healing anything, which is a genuine tactical option and a way to get someone
killed because they didn't notice how hurt they were.

### Exhaustion
Physical fatigue from combat and labor, distinct from [rest need](04-survival-needs.md). Recovers with
short breaks. Depleted stamina means slower swings, worse blocks, and failure to run — the thing
between "a fight going badly" and "a fight killing you."

### Bacterial infection
**Kept deliberately separate from zombie infection**, and this is one of the design's better ideas.

Any open wound can go septic, with probability driven by wound severity,
[hygiene](04-survival-needs.md), whether it was cleaned, bandage cleanliness, and treatment skill. It
presents as fever, pain, and worsening — *which is also how zombie infection presents in its early
stages*.

Two consequences:
- **Antibiotics are pulled in two directions.** The finite, uncraftable supply that saves someone from
  a bite is the same supply that saves someone from a dirty laceration. Every ordinary wound spends
  the infection budget.
- **Diagnostic ambiguity gets worse.** A feverish survivor with a scratch might have sepsis, or might
  be turning. See [infection](06-infection.md).

## Diagnosis: what you actually see

Per the [hardcore contract](01-hardcore-contract.md#4-information-is-scarce-and-unreliable), you never
see numbers. You see text whose *precision* scales with the examining survivor's medical skill.

| Examiner | What you get |
|---|---|
| **No training** | "There's a lot of blood. He doesn't look good." |
| **Basic** | "Deep cut on the left forearm, bleeding badly. Needs stitches." |
| **Skilled** | "Deep laceration, left forearm. Sutured and clean — low infection risk. Off work five days." |
| **Expert** | All of the above, plus early and confident discrimination between sepsis and zombie infection |

A trained medic is therefore one of the most valuable people in the colony, and the fastest way to
lose your grip on a situation is for the medic to be the one who got hurt.

## The condition view

Everything above is the *model*. This is the one screen that shows it, and it is where the design is
most likely to be talked into a health bar, so the rules are written down here rather than left to
the UI work.

### A body map, not a health display

The condition view is a **paperdoll**: the parts from the table above — head, torso, arms, hands,
legs, feet — laid out as a body, with located conditions sitting on the part they are on. That is
the entire idea. It changes the *layout* of the information in
[diagnosis](#diagnosis-what-you-actually-see), not the information.

Which means it inherits every property that section already established:

- **What a part says is skill-scaled prose.** An untrained survivor looking at a wounded arm gets
  *"there's a lot of blood, he doesn't look good"* on that arm. A skilled one gets *"deep
  laceration, sutured and clean, off work five days."* Same body, same wound, different reader.
- **It inherits the ambiguity, and this is the point.** A [bite that presents as a
  scratch](06-infection.md) presents as a scratch *here*, on the forearm, in the same words. The
  paperdoll does not know something the examiner doesn't. It is a layout for uncertainty, not a
  resolution of it.

### Colour, never fill

A part reads as **unhurt / hurt / badly hurt / unusable** through tint and through the prose beside
it. Four states, because four is how many distinctions the prose actually supports.

**Prohibited, explicitly:** percentages, hit points, segmented pips, a fill level of any kind, and
tooltips carrying numbers the screen itself does not show — a bar with the number hidden behind a
hover is still a bar, and
[clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) names "helpful tooltips"
for exactly this reason.

**This strengthens the clause rather than carving an exception to it.** A health bar answers *how
much* is left. The condition view answers *what is wrong and where*, which is the question this
design has always wanted the player to be asking, and it answers it in words that can be wrong.

### The continuous conditions are read from the world

The four values above — blood loss, pain, exhaustion, bacterial infection — plus stamina do not
appear on the paperdoll as anything measured. They are read from what the survivor *does*:

| Condition | How you read it |
|---|---|
| **Blood loss** | Movement slows, the description goes grey and vague, the screen edges close in. Blood on the ground where they have been standing |
| **Pain** | Slower work, worse aim, a survivor who flinches; the prose says so plainly |
| **Exhaustion** | Breathing. Swings get slow and short. Then sprint simply stops answering — see [stances](29-movement-and-stances.md) |
| **Stamina** | The same channel as exhaustion, on a shorter clock. Weapon sway and swing recovery are the readout |
| **Bacterial infection** | Fever, and the wound's own description worsening day over day — *which is also how [zombie infection](06-infection.md) presents* |

Every one of these is already a mechanical consequence specified elsewhere in this document. The only
change is that **the consequence is the readout**. Nothing is displayed twice, once as an effect and
once as a meter, and a player who learns to read a survivor has learned something about the
simulation rather than about the HUD.

## Treatment

Sequential steps, each needing time, a supply, and skill:

1. **Stop the bleeding** — pressure, tourniquet, bandage. Urgent.
2. **Clean** — water, alcohol, or antiseptic. Skipping this is how you get sepsis. Tempting when
   supplies are thin.
3. **Close** — sutures for deep wounds, splint for fractures.
4. **Dress** — clean bandages; must be *changed* over subsequent days, which is ongoing labor.
5. **Rest and feed** — recovery needs sleep and calories. A survivor who's rushed back to work
   reopens the wound.

Supplies degrade in quality: sterile medical bandages > cloth bandages > dirty rags, with rising
infection risk down the chain. Late-game, when the medical loot is gone, you are stitching people
with boiled rags and it shows in the outcomes.

## Permanent consequences

Injuries can resolve into permanent conditions — which is how a long-lived survivor accumulates a
readable history:

- Badly-set fracture → permanent limp (movement penalty)
- Repeated concussions → permanent perception loss
- [Amputation](06-infection.md) → the limb is gone, with all its capabilities
- Deep scarring → mood modifier, minor social effects

**These do not remove a survivor from play.** A one-armed survivor can't fight but can cook, haul,
watch, and talk. The colony half of the game gives injured people somewhere to go, which is precisely
what makes amputation a real choice rather than a euphemism for death.

## Cut list

- **Health, stamina, or condition bars of any kind.** Rule 1 of this document and
  [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable). The
  [condition view](#the-condition-view) is what ships instead, and it carries more information than a
  bar would — just none of it numeric.

- **Surgery as a distinct minigame or operating-theatre facility.** Post-slice; treatment steps carry
  enough weight.
- **Chronic illness (heart conditions, diabetes) requiring maintenance meds.** Good texture, high
  content cost, post-slice.
- **Blood types and transfusion.** Rejected as fiddly for the payoff.
- **Mental trauma as a separate condition track.** Currently handled as mood modifiers in
  [survival needs](04-survival-needs.md).

---

**Previous:** [04 — Survival Needs](04-survival-needs.md) ·
**Next:** [06 — Infection & Turning](06-infection.md) · [Doc index](../README.md#documentation)
