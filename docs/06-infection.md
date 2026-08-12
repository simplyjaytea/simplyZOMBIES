# 06 — Infection & Turning

*Why this exists: this is the mechanic that gives every other system stakes. Gear, the skill web,
relationships, and the whole colony half exist so that infection has something to take away.*

---

## The thesis

Survivors are [unlimited](07-survivors.md). Bodies are cheap. So infection cannot be about death —
it's about **losing an investment under uncertainty, on a deadline, in front of people who liked
them**.

Three properties make it work:

1. **You often don't know.** A bite can present as a scratch.
2. **Every treatment costs something irreplaceable**, and the cheap treatment is mutilation.
3. **The infected are still people** until they aren't. They talk. They ask what you're going to do.

## Contracting it

| Vector | Infection chance | Notes |
|---|---|---|
| **Bite, bare skin** | Very high | The classic. Rarely survivable without intervention. |
| **Bite through clothing** | Reduced by armor coverage and material | [Armor](10-items.md) exists primarily for this, not for damage reduction |
| **Deep scratch** | Low but real | The ambiguous case that drives the whole system |
| **Blood in an open wound** | Low | Melee splashback — a quiet argument for [reach weapons](09-combat.md) |
| **Blood in eyes/mouth** | Moderate | Eye protection is a real, unglamorous piece of gear |
| **Corpse handling without protection** | Very low, non-zero | Why corpse disposal isn't a free chore |

**Design note:** the bite-through-clothing rule is what makes armor matter in a game where damage
mitigation would otherwise break [pillar 1](00-vision.md). Armor doesn't make you tanky — it makes you
*less likely to lose someone permanently*, at the cost of weight, heat, and stamina.

## The uncertainty model

This is the heart of the system.

When a survivor takes a wound from a zombie, the simulation privately records whether it transmitted.
The **player is not told**. What the player gets is an observation, filtered through the examiner's
medical skill.

| Wound presentation | What it might actually be |
|---|---|
| Clear deep bite, torn flesh | Almost certainly infected. Little ambiguity — and little hope. |
| Shallow bite / bad scratch | **Genuinely ambiguous.** Could be nothing. Could be the end of them. |
| Scratch, cleaned quickly | Probably nothing. Probably. |

Then symptoms begin — and **early zombie infection is indistinguishable from ordinary
[sepsis](05-health-injury.md)**: fever, pain, sweating, weakness, loss of appetite. Both are common.
Both get worse. One of them ends with the patient eating someone.

### What skill buys you

| Examiner skill | Certainty |
|---|---|
| None | Nothing useful. You're guessing from vibes and fever. |
| Basic | Can rule out obvious non-cases; still can't discriminate mid-stage |
| Skilled | Confident call in the second half of the timeline |
| Expert | Confident call early — early enough for amputation to still work |

**A skilled medic doesn't save the bitten. A skilled medic tells you sooner, which is worth more.**

### The rules the uncertainty must obey

Per the [fairness rules](01-hardcore-contract.md#fairness-rules):

- The game **never displays false information.** Ambiguity is presented as ambiguity, never as a
  confident wrong answer.
- The outcome is **decided at wound time and never retroactively changed** to be dramatic. It's
  deterministic and reproducible from the seed.
- Symptoms always precede turning by enough time to act.

## The timeline

Roughly 2–4 in-game days, varying by vector, wound severity, Constitution, and traits. The player sees
stages, not a percentage. Milestone 2 implements the complete timeline with a neutral Constitution
modifier; when survivor attributes arrive, CON activates that existing hook. It may lengthen or
shorten progression within the authored band, but never changes the wound-time transmission result.

| Stage | Duration | Presentation | Distinguishable from sepsis? |
|---|---|---|---|
| **1 — Latent** | ~12 h | Nothing. They feel fine. | No — nothing to see |
| **2 — Onset** | ~12–24 h | Fever, fatigue, appetite loss | No |
| **3 — Progression** | ~24 h | Worsening fever, pallor, tremor, confusion, mood collapse | Skilled+ only |
| **4 — Critical** | ~12 h | Unable to work, delirious, dark vein tracery, terrifying to be near | Yes — obvious to anyone |
| **5 — Turn** | — | Death, then reanimation minutes later | — |

**Amputation only works during stages 1–2**, before it's spread past the limb. That's the cruelty of
the design: the window in which the cure works is the window in which you can't be sure it's needed.

## The five responses

### 1. Amputate
- **Window:** stages 1–2 only, and only for a limb wound.
- **Cost:** the limb, permanently ([health & injury](05-health-injury.md)). Surgery needs a skilled
  medic, supplies, and time; the operation itself can kill them, and always causes severe blood loss,
  pain, and trauma.
- **Result:** they live. Disabled, alive, and still part of the colony — cooking, hauling, watching,
  talking.
- **The decision:** cut off your best fighter's arm on a *suspicion*, or wait for certainty you can no
  longer act on.

### 2. Cauterize
- **Window:** immediately after the wound.
- **Cost:** a serious [burn](05-health-injury.md), heavy pain, its own infection risk. Needs fire —
  which is light, heat, and noise.
- **Result:** a modest reduction in transmission chance. Not a cure — a gamble that hurts.
- **Use case:** in the field, far from the medic, with nothing else available.

### 3. Antibiotics
- **Window:** most effective early; declining through stage 3.
- **Cost:** the game's scarcest resource. **Never craftable, medical-locations only,
  [strictly finite](12-resources.md)** — and the same stock that treats ordinary sepsis.
- **Result:** a real chance of clearing it, not a guarantee. A full course is multiple doses over
  days; stopping early wastes what you spent.
- **The decision:** spend an irreplaceable course on a *maybe*, knowing that in three weeks someone
  will have a septic leg wound and nothing left to treat it with.

### 4. Quarantine
- **Window:** any time.
- **Cost:** they produce nothing, eat the whole time, and need a lockable, guarded space. Their mood
  collapses. Everyone who cares about them takes a mood hit for as long as it goes on.
- **Result:** you find out for certain — by watching. If they turn, they turn **inside your walls, at
  night**, and whether that's a contained incident or a catastrophe depends entirely on how seriously
  you built the room.
- **The decision:** the honest option, and the one that most often goes wrong. Quarantine built out of
  optimism is how colonies end.

### 5. Put them down
- **Window:** any time.
- **Cost:** severe mood damage colony-wide, scaled by relationships to the deceased and by whether it
  was clearly justified yet. Doing it at stage 2 on a suspicion is *much* worse for morale than doing
  it at stage 4.
- **Result:** certainty, immediately, cheaply.
- **The decision:** the efficient answer, and the game makes you look at it. Survivors who were close
  to them remember, and some of them will not forgive it.

**Their gear comes off the body in every case.** Even the worst outcome returns the equipment — which
is the design saying, again, that what you lost was the *person you built*, not the loot.

## Turning inside the walls

If someone turns in the base:

- They reanimate where they died — in a bed, in a quarantine room, on the watch platform.
- They attack the nearest living thing, which at night is someone asleep.
- **The noise cascades.** Screaming is a massive [attention](03-attention.md) event, drawing whatever
  is outside toward a base that is now fighting itself.
- A turn in an unsecured space during a Pressure night is one of the ways a run ends.

## Design consequences elsewhere

- **[Combat](09-combat.md):** melee's cost isn't damage, it's exposure to this system. That's the
  parity contract's whole basis.
- **[Items](10-items.md):** armor's value is coverage, not mitigation.
- **[Resources](12-resources.md):** antibiotics are the hardest currency in the game; medical
  locations are the most contested.
- **[Survivors](07-survivors.md):** relationships exist so that response #5 has a price.
- **[Skill web](08-skill-web.md):** medical nodes buy *certainty*, which is the scarcest thing here.

## Cut list

- **Immune survivors / a cure.** Contradicts [pillar 4](00-vision.md). Permanently excluded.
- **Player-visible infection percentage,** even at expert medical skill. The whole system is the
  uncertainty.
- **Airborne or environmental transmission.** Would make the base uninhabitable rather than tense.
- **Infected survivors retaining any control after turning.** No pet zombies, no partial turns.

---

**Previous:** [05 — Health & Injury](05-health-injury.md) ·
**Next:** [07 — Survivors](07-survivors.md) · [Doc index](../README.md#documentation)
