# 04 — Survival Needs

*Why this exists: needs are the engine that forces the player out of safety. Without them a colony
could simply hide forever, and the [attention field](03-attention.md) would have nothing to push
against.*

---

## Design intent

Needs are not a chore list. Each one exists to create a specific pressure:

| Need | The pressure it creates |
|---|---|
| **Hunger** | Forces scavenging and farming — the reason to leave the walls |
| **Thirst** | A daily grind that can't be stockpiled easily; ties to [weather](16-weather.md) and grid failure |
| **Rest** | Makes night dangerous even when nothing attacks; punishes the tense-quiet nights |
| **Temperature** | Forces heat and light, which are the loudest emitters you own |
| **Hygiene** | Ties directly to wound infection and to scent |
| **Mood** | The counterweight to hiding — living safely makes people miserable |

Every survivor has all six, including your controlled character. There is no "player is exempt"
shortcut.

## The six needs

### Hunger

- Depletes on a daily cycle, faster with hard labor, cold, and injury recovery.
- **Injured and sick people eat without producing** — this is the compounding tax from the
  [hardcore contract](01-hardcore-contract.md#3-mistakes-compound).
- Quality matters, not just quantity: raw and spoiled food fills the bar but damages mood and carries
  illness risk; cooked meals restore more and give a mood bonus.
- **Cooking emits scent (15) and usually light and smoke.** Feeding your colony well is one of the
  loudest routine things you do.
- Starvation is slow and visible: weight loss, weakness, then collapse. Never sudden.

### Thirst

- Faster than hunger, harder to stockpile in volume.
- Sources: mains water (until the [grid fails](13-world-decay.md)), rain collection, wells, rivers and
  ponds.
- **Untreated water carries illness.** Purification needs fuel (boiling → heat, light, smoke) or
  filters or chemicals. Another comfort-for-noise trade.
- Rain is a genuine relief event, and it *also* masks scent. Rainy days are the best days to be alive.

### Rest

- Depletes over waking hours; recovers by sleeping, and recovery quality depends on bed quality,
  warmth, darkness, quiet, and safety.
- **This is why "pressure" nights hurt without killing anyone** — a night spent with things scratching
  at the wall means nobody rests, and tomorrow the whole colony works badly and fights worse.
- Exhaustion degrades melee accuracy, ranged accuracy, work speed, and mood simultaneously, and raises
  the chance of the mistakes that get people killed.
- No caffeine-style hard reset. Stimulants exist as rare loot with a real crash afterward.

### Temperature

- Per-survivor, from ambient [weather](16-weather.md), clothing insulation, wetness, shelter, and heat
  sources.
- Cold: mood damage, then temporary movement and fine-motor penalties, then hypothermia as a real
  [injury](05-health-injury.md). These consequences modify derived actions; they do not rewrite the
  survivor's permanent DEX aptitude.
- Heat: faster thirst, mood damage, heatstroke; also accelerates food spoilage and corpse rot.
- **Being wet is a multiplier on cold** — rain is a relief for thirst and a threat for temperature at
  the same time, which is exactly the kind of two-sidedness the design wants.
- The fix is fire and shelter. Fire is light, heat, and smoke — the loudest single comfort in the
  game.

### Hygiene

Not a comfort stat. It has two teeth:

1. **Wound infection risk.** Dirty survivors treating wounds with dirty hands get bacterial
   infections, which are distinct from zombie infection and consume the same finite antibiotics. See
   [health & injury](05-health-injury.md).
2. **Scent.** Unwashed survivors emit double the baseline scent. A dirty colony is a smelly colony is
   a visited colony.

Washing needs water — competing directly with drinking — and soap, which is scavenged or crafted.

### Mood

The counterweight that makes hiding unsustainable. Mood is a running total of modifiers with named
sources (via the [modifier pipeline](21-extensibility.md)), and it's where the design's central
tension gets enforced on the player:

**Negative:** hunger, thirst, exhaustion, cold, pain, filth, darkness, cramped quarters, sleeping
rough, eating raw or spoiled food, grief, witnessing a death, fear after a bad night, being made to
work while injured.

**Positive:** cooked meals, warmth, a proper bed, light, personal space, alcohol, a quiet night,
recreation, relationships with people they like, an ordered and defended base.

Look at those two lists: **almost every positive is an attention emitter, and almost every negative is
free.** That's deliberate. The cheapest way to keep people happy is the loudest.

### Mood consequences

Low mood does not produce a rage meltdown. It produces:

- Slower work, more mistakes, more injuries
- Refusing assigned jobs
- Arguments — which damage other survivors' mood, so misery spreads
- Wandering off, breaking into food stores, or drinking the alcohol reserves
- At the extreme: **leaving**, taking their gear with them

Nobody snaps and murders the colony. The failure mode is a slow, sour decline where the colony stops
functioning — which is more frightening and more recoverable than a dramatic break.

## Needs and the job queue

Needs interact with [survivor priorities](07-survivors.md): a survivor whose needs are critical will
break off assigned work to address them, and *which* need they prioritize is influenced by traits. A
disciplined survivor works through hunger; a soft one doesn't.

This is how the colony fails gracefully rather than all at once. You'll notice the water hauler
started ignoring the water because he hasn't slept.

## Needs are a module

Per the [kernel-vs-module rule](19-architecture.md), needs are not kernel. Each need is registered
independently, so a sandbox preset can disable hygiene or temperature entirely and the game still
runs. New needs (morale sub-types, addiction, chronic pain) can be added without touching existing
ones — see the [cookbook](21-extensibility.md).

## Cut list

- **Bladder/bathroom needs.** Latrines exist as a *scent emitter* and a hygiene facility, but
  individual survivors do not track a bladder meter.
- **Individual food preferences and cuisine variety bonuses.** Post-slice flavor; the raw/cooked/
  spoiled axis carries enough weight for now.
- **Addiction systems.** Alcohol and stimulants have crashes but no dependency modeling yet.
- **Social need as a separate bar.** Folded into mood as relationship-driven modifiers.

---

**Previous:** [28 — Visibility & Sightlines](28-visibility-and-sightlines.md) ·
**Next:** [05 — Health & Injury](05-health-injury.md) · [Doc index](../README.md#documentation)
