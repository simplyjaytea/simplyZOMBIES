# 07 — Survivors

*Why this exists: the game has no fixed cast. Survivors are generated, unlimited, and worthless on
arrival — which is the mechanism that makes [infection](06-infection.md) hurt without making the run
fragile.*

---

## The core principle

> **Bodies are cheap. People are expensive.**

Anyone can walk up to your gate. What you can't get back is the two months you spent turning someone
into a competent medic with a suppressed rifle and a good relationship with everyone inside.

So: unlimited supply, and a steep, slow, non-transferable investment curve. Losing a veteran is
devastating; losing a newcomer is an accounting note.

## Everyone is a blank slate

There are no classes, no archetypes at creation, and **no mechanical difference between your
controlled character and anyone else**. A fresh survivor — yours at run start, or a recruit on day
40 — has:

- No [skill web](08-skill-web.md) points allocated
- Low skills across the board, with a small backstory-driven bias
- Whatever they were carrying, which is close to nothing
- A set of traits, a backstory, and relationships-to-be

Identity is assembled afterward from what the world hands them. See
[skill web](08-skill-web.md) and [items](10-items.md).

## The generator

Survivors are rolled from data tables ([content](20-ecs-and-content.md)), not authored. The generator
composes:

| Field | Source |
|---|---|
| **Name** | Weighted name pools |
| **Appearance** | Feature pools — enough variety to make people recognizable at a glance |
| **Age** | Distribution skewed to working age; the old and young exist and are mechanically harder |
| **Backstory** | One entry from a backstory table — this is the load-bearing field |
| **Traits** | 2–4 drawn from a pool with conflict rules |
| **Skill bias** | Derived from backstory, small — a nudge, not a class |
| **Starting kit** | Derived from backstory, usually pitiful |

### Backstory is the point

A backstory is a sentence that produces mechanics. *School caretaker. Line cook. Failed pharmacy
student. Long-haul driver. Veterinary nurse. Fired security guard. Semi-professional cyclist.*

Each grants a modest skill bias, occasionally a trait, and a scrap of starting equipment. The
pharmacy student reads wounds slightly better than nothing. The line cook wastes less food. The
cyclist has legs.

**These are biases, not builds.** A line cook who spends two months on the walls becomes a fighter who
happens to cook well. That's the blank-slate promise: history explains where someone started, never
where they'll end up.

### Traits

Drawn with conflict rules (nobody is both *Tough* and *Frail*). Traits are permanent, mostly
double-edged, and mostly about *how someone behaves* rather than raw numbers:

| Trait | Effect |
|---|---|
| **Light sleeper** | Wakes on noise — good sentry, poor [rest](04-survival-needs.md) recovery |
| **Squeamish** | Mood penalty for corpse handling and treating wounds |
| **Steady hands** | Better treatment and item modification outcomes |
| **Loud** | Higher personal [noise](03-attention.md) floor — permanently |
| **Hoarder** | Refuses to give up items; mood penalty when stores are low |
| **Optimist** | Slower mood decay, less grief transmission |
| **Grudge-holder** | Relationship damage is permanent |
| **Iron stomach** | No penalty for raw or spoiled food |
| **Night blind** | Severe accuracy penalty in the dark — and lights are dangerous |
| **Fast healer** | Faster [injury](05-health-injury.md) recovery, no infection benefit |

Rule: no trait may be strictly good or strictly bad. Even *Fast healer* means they're back on the
walls sooner, which is not always where you want them.

## Unique survivors

Rare, hand-authored, static — **the people equivalent of [named items](10-items.md)**, and balanced
the same way: a build-defining strength with a real drawback.

- Fixed name, appearance, backstory, and trait set.
- One capability nobody else can have, or a head start worth many weeks.
- A genuine liability that shapes how you use them.

Sketches: the army medic who will not touch a firearm under any circumstances. The radio engineer who
can contact [factions](18-factions.md) but is physically frail and terrified of the dark. The
ex-poacher who moves near-silently and cannot work with others without conflict.

They appear only through [director](17-director.md) beats and faction events — never in the generic
recruitment pool. Meeting one should feel like finding a named weapon.

## Recruitment: rare, gated, and a net loss at first

Recruitment is **not** a steady drip. It happens through director-paced events: a scavenging
encounter, a faction referral, someone at the gate during a bad night.

A new recruit is a **net negative for days**:

- Eats and drinks immediately, from day one
- Contributes almost nothing until they've built any skill
- Takes a bed, floor space, and warmth
- Adds a permanent [scent](03-attention.md) emission to the base
- Arrives with no relationships, so they're a mood-neutral stranger in a stressed group
- May be sick, injured, or — this is the good part — **already bitten and not saying so**

So opening the gate is a real decision. You are trading certain present cost for possible future
value, during a week when you might not be able to feed the people you already have.

## Population is capped economically, not numerically

There is no maximum. There is an equation:

```
food + water + beds + warmth + space + tolerable mood
        ────── versus ──────
   labor + defenders + more scent, noise, and light
```

Every additional survivor makes the colony louder, hungrier, and more crowded — and better at
everything. The right size isn't a number the game tells you; it's whatever you can feed while staying
hidden. See [attention](03-attention.md).

## Work: the priority grid

RimWorld-style. Jobs in columns, survivors in rows, priorities 1–4 or disabled.

Job categories: **Firefight · Patient · Doctor · Rest · Cook · Hunt · Construct · Repair · Haul · Farm
· Water · Craft · Modify · Butcher · Clean · Guard · Bury**

Rules:
- You set priorities. You do not issue individual tasks. NPCs choose work by priority, proximity, and
  capability.
- Critical [needs](04-survival-needs.md) interrupt work, and traits govern how readily.
- Injuries disable jobs the body can't do — which is how a one-armed survivor finds a new role.
- **You control exactly one survivor directly.** Everyone else is a person with priorities, not a unit
  with orders.

## Focus and auto-allocation: the anti-micromanagement rule

Unlimited survivors × [affixed gear](10-items.md) × a [skill web](08-skill-web.md) is where this
design most plausibly collapses into spreadsheet management. So this is a **hard UX constraint**, not
a nice-to-have:

Each survivor gets a **Focus**: `Fighter · Worker · Medic · Scout · (Manual)`.

With a Focus set, they:
- **Auto-allocate skill web points** along a sensible path for that focus
- **Auto-maintain their loadout** from colony stores — picking up better gear, replacing broken items,
  restocking ammo and bandages
- Never touch anything you've manually locked

Setting Focus to Manual gives full control of that one survivor's web and inventory.

**The rule:** the game must be fully playable with every NPC on auto. Manual control is for the three
people you care about, never a tax on the twelve you don't.

## Relationships

Survivors form opinions through proximity, shared work, shared danger, mood, and traits. Relationships
are tracked pairwise and produce:

- Mood modifiers from being near people they like or loathe
- **Grief when someone dies** — scaled by closeness, and this is what gives
  [response #5](06-infection.md#5-put-them-down) its price
- Work friction and arguments between people who don't get along
- Occasional refusals — someone won't be the one to put down a person they were close to

Relationships are not a romance sim. They exist to convert deaths into consequences.

## Cut list

- **Romance, marriage, children.** Real time cost, tone mismatch, no support for the pillars.
- **Character creation.** You start with a generated survivor like everyone else. Rerolling the start
  is allowed; designing one is not.
- **Deep social simulation** (rumors, factions inside the colony). Post-slice.
- **Skill decay from disuse.** Considered; adds bookkeeping, punishes specialization, cut.
- **Survivors leaving with a group / colony splits.** Post-slice, tied to [factions](18-factions.md).

---

**Previous:** [06 — Infection & Turning](06-infection.md) ·
**Next:** [08 — The Skill Web](08-skill-web.md) · [Doc index](../README.md#documentation)
