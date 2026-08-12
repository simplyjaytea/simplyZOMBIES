# 08 — The Skill Web

*Why this exists: the long-horizon progression that runs underneath found gear. It's classless and
earned by doing, so a survivor's position on it is a record of what they survived rather than a plan
they committed to on day one.*

---

## Design rules

1. **No classes and no entry points.** Every survivor — yours, a recruit, a
   [unique](07-survivors.md) — starts at the same center node.
2. **Points come from doing.** Shooting earns points toward the ranged region. Hauling earns labor
   points. You cannot grind a build you aren't living.
3. **It dies with the person.** No inheritance, no respec-on-death, no meta-progression. See
   [succession](01-hardcore-contract.md#succession-what-happens-when-you-die).
4. **The web makes you competent, never invincible.** Bounded by
   [pillar 1](00-vision.md#the-six-pillars). A fully-developed survivor moves the lethality
   thresholds by about one band.
5. **Melee and ranged get equal depth.** Non-negotiable, per the
   [parity contract](09-combat.md).
6. **It's smaller than PoE's.** ~60–100 nodes total. This is a web, not a galaxy.

## Shape

Six regions radiating from a shared center, with cross-links near the rim so hybrids are reachable but
expensive.

```
                    ENDURANCE
                        │
        MEDICINE ───────┼─────── RANGED
                        │
                     (start)
                        │
           CRAFT ───────┼─────── MELEE
                        │
                     SURVIVAL
```

- **Near the center:** cheap, broad, small percentage improvements. Anyone drifts here.
- **Mid-web:** the identity nodes — the things that change *how you play*, not how much you hit for.
- **Rim:** expensive keystones. One or two per survivor, ever.

Cross-links between adjacent regions exist near the rim, so a Melee/Endurance survivor is a real
build, but reaching two rims is realistically a lifetime's work — and lifetimes here are short.

## Points

| Source | Earns |
|---|---|
| Killing zombies in melee | Melee |
| Killing zombies at range | Ranged |
| Treating wounds, diagnosing | Medicine |
| Building, repairing, [modifying items](11-crafting.md) | Craft |
| Hauling, farming, cooking, water | Survival |
| Surviving hard nights, long runs, injury recovery | Endurance |

Points accrue slowly and are region-tagged — you spend Melee points in the Melee region. A survivor
who has only ever hauled water cannot buy a marksmanship keystone, no matter how long they've lived.

**Consequence:** developing a fighter requires exposing them to fighting, which is how they get bitten.
The progression system's cost is paid in [infection](06-infection.md) risk. That's intentional.

## Node types

| Type | Frequency | Example |
|---|---|---|
| **Minor** | Most nodes | +4% melee swing speed; -3% food consumption; +5% bandage effectiveness |
| **Notable** | ~1 in 6 | Changes a behavior — reload while moving; treat a wound without a table |
| **Keystone** | 6–10 total | Rim-only, build-defining, **always with a real drawback** |
| **Aptitude** | Rare, late, and opportunity-costly | A permanent +1 to one planned survivor attribute |

Aptitude nodes are the only web nodes that can permanently raise
[STR, DEX, CON, INT, CHA, or WIS](23-roadmap.md#planned-survivor-attributes). They never grant
retroactive progress. INT-raising nodes cannot accelerate their own acquisition, and no route can
collect enough aptitude nodes to erase the generator's tradeoffs. Item bonuses remain conditional and
disappear with the item.

### Keystone sketches

Every keystone has a downside, in the same spirit as [named items](10-items.md):

| Keystone | Gain | Cost |
|---|---|---|
| **Butcher's Rhythm** | Melee kills chain — each connect speeds the next | Cannot back off mid-chain; you're committed until it breaks |
| **Cold Shot** | Enormous accuracy from a braced, still position | Severe penalty while moving or recently hit |
| **Field Surgeon** | Amputate and suture without a proper facility | Permanent mood penalty; they've seen too much of it |
| **Quiet Ones** | Halves personal [noise](03-attention.md) emission | Cannot use unsuppressed firearms — the reflex is gone |
| **Scavenger's Eye** | Sees exact loot quality at a distance; better [affix](10-items.md) rolls from finds | Compulsive; mood penalty when leaving anything behind |
| **Second Wind** | Recover stamina from near-zero once per day | The crash afterward is severe and lasts hours |
| **Pack Mule** | Large carry capacity increase | Permanently louder and slower to escape |

## The six regions

**Melee** — swing speed, stagger, stamina economy, reach control, blocking, weapon-class
specializations, and critically: **nodes that reduce [bite risk](06-infection.md) on connect**. That's
the region's real currency — melee's cost is exposure, so melee's progression buys exposure back.

**Ranged** — steadiness, reload speed and mobility, sighting, recoil, ammo conservation, and
**noise-reduction nodes** that partially offset ranged's [attention](03-attention.md) cost. Same
symmetry, opposite currency.

**Medicine** — treatment speed and quality, infection risk reduction, surgery, and above all
**diagnostic certainty**. In a game built on [not knowing whether someone is infected](06-infection.md),
this region buys the scarcest resource: knowing.

**Craft** — build speed and material efficiency, structure durability, repair quality,
[trap](15-base-building.md) effectiveness, and [item modification](11-crafting.md) outcomes — better
affix rolls, less material waste, fewer catastrophic failures.

**Survival** — food and water efficiency, foraging and farming yield, cooking quality, spoilage
reduction, [temperature](04-survival-needs.md) tolerance, carrying, and stealth movement.

**Endurance** — stamina pool and recovery, pain tolerance, blood loss resistance, faster
[injury](05-health-injury.md) recovery, mood resilience, sleep quality. The unglamorous region that
quietly keeps veterans alive.

## Auto-allocation

Per the [anti-micromanagement rule](07-survivors.md#focus-and-auto-allocation-the-anti-micromanagement-rule),
NPCs with a Focus auto-spend points along a defined path:

| Focus | Path |
|---|---|
| Fighter | Melee or Ranged (whichever they've earned more in) → Endurance |
| Worker | Craft → Survival |
| Medic | Medicine → Endurance |
| Scout | Survival (stealth) → Ranged |

Auto-allocation is **conservative**: it takes minors and notables, and never spends on a keystone or
permanent aptitude node without asking. Those choices are build-defining, so they remain player
decisions even for NPCs you otherwise ignore.

Manual focus hands you the whole web for that survivor.

## Reading a survivor

Because points are earned by doing, the web doubles as a biography. A survivor deep in
Endurance and Medicine with nothing in Melee has been treating people and not fighting. One with
scattered Melee minors and a lot of Survival has been hauling and occasionally caught out.

The UI leans into this: a survivor's summary describes them in prose derived from their web
("cautious, hard to tire, decent with a needle"), consistent with the
[no-numbers rule](01-hardcore-contract.md#4-information-is-scarce-and-unreliable).

## Content shape

The entire web is data ([content](20-ecs-and-content.md)): nodes with a stable string ID, region,
position, cost, prerequisite links, and a list of [modifiers](21-extensibility.md). Adding a node is a
JSON entry. Re-laying-out the web is a data change with no code impact.

Node effects go through the shared modifier pipeline, so a web node, a
[weather](16-weather.md) state, an [injury](05-health-injury.md), and an
[item affix](10-items.md) all affect a stat by the same mechanism.

## Cut list

- **Respec.** Contradicts the "web is a record" premise and softens permadeath.
- **Skill books / trainers** that grant points without the corresponding activity. Breaks rule 2.
- **A second progression layer** (colony-wide research or tech tree). Considered and rejected —
  [world decay](13-world-decay.md) already occupies the long-horizon slot, and pointing *up* while the
  world points *down* muddles the tone.
- **Node prerequisites across regions near the center.** Keeps early web reading legible.

---

**Previous:** [07 — Survivors](07-survivors.md) · **Next:** [09 — Combat](09-combat.md) ·
[Doc index](../README.md#documentation)
