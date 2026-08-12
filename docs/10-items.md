# 10 — Items

*Why this exists: with no classes, gear **is** the build. This document defines how a piece of junk
becomes an identity — bases, rolled affixes, tiers, attachments, and the decay that stops any of it
from being permanent.*

---

## Design rules

1. **Gear is the build.** A survivor is defined by what they carry far more than by their
   [web](08-skill-web.md).
2. **Items are found, not chosen.** No shop, no crafting a specific item to spec. You work with what
   the world gives you and [modify it](11-crafting.md).
3. **Nothing is permanent.** Everything degrades. See [world decay](13-world-decay.md).
4. **Melee and ranged get equal item depth** — bases, affixes, attachments, named items. Per the
   [parity contract](09-combat.md).
5. **No item may break [pillar 1](00-vision.md).** The best weapon in the game makes you competent in
   a crowd, not safe in one.
6. **Armor buys coverage, not tankiness.** Its purpose is [bite prevention](06-infection.md).

**[Vehicles](25-vehicles.md) use this same grammar** — found bases, rolled affixes, four tiers,
movable attachments, condition that degrades and repair that lowers the ceiling. Everything in this
document applies to them; that document covers only what's specific to driving one.

## Anatomy of an item

```
  Field-Tested Fire Axe                    ← tier + affix-derived name
  ├── base: axe.fire                       ← determines class, damage, reach, weight, slots
  ├── condition: 62%                       ← degrades with use
  ├── prefixes:  Serrated, Weighted        ← rolled
  ├── suffixes:  of the Quiet Hand         ← rolled
  └── attachments: [ haft_wrap: leather ]  ← found, movable
```

## Tiers

| Tier | Affixes | Frequency | Role |
|---|---|---|---|
| **Scavenged** | 0 | Common | Baseline. What most of the world is made of. |
| **Modified** | 1–2 | Uncommon | The working standard. Most survivors carry these. |
| **Field-Tested** | 3–6 | Rare | A real build piece. Worth going back into a bad place for. |
| **Named** | Fixed, hand-authored | Very rare | Build-defining, **always with a drawback** |

Tier is rolled at generation from the [loot table](12-resources.md) of the location, weighted by
location type and danger. Military and medical sites carry the good rolls, and they are the worst
places to be.

## Affixes

Rolled from a pool gated by base type, with values in tiers. They read as salvage work, not
enchantment — this is a world of duct tape and improvisation, not magic.

### Melee prefixes

| Affix | Effect |
|---|---|
| **Serrated** | Bleed on connect; slower kills, faster attrition |
| **Weighted** | Higher stagger, slower swing, more stamina |
| **Balanced** | Faster swing, lower stagger |
| **Reinforced** | Much slower condition loss |
| **Barbed** | Bonus damage; **snags** — occasional recovery-window penalty |
| **Lengthened** | +reach, -control in tight spaces |

### Ranged prefixes

| Affix | Effect |
|---|---|
| **Trued** | Tighter accuracy cone |
| **Ported** | Less recoil, **more noise** |
| **Chambered** | Faster reload |
| **Blued** | Slower condition loss, resists wet |
| **Heavy-barrelled** | Better sustained accuracy, more weight and steady time |

### Suffixes (both classes)

| Affix | Effect |
|---|---|
| **of the Quiet Hand** | Reduced [noise](03-attention.md) emission |
| **of Long Nights** | Reduced stamina cost |
| **of the Steady Grip** | Reduced accuracy/control loss while injured |
| **of Salvage** | Cheaper and faster to repair |
| **of the Butcher** | Bonus damage to already-wounded targets |
| **of Ruin** | High damage, **accelerated condition loss** |

**Rule:** every affix pool contains double-edged entries. An item with six affixes is not strictly
better than one with three — it's *more specialized*, and specialization has edges.

## Named items

Hand-authored, fixed rolls, very rare. Same balance philosophy as
[unique survivors](07-survivors.md): a capability nobody else gets, and a cost you have to build
around.

| Item | Gain | Drawback |
|---|---|---|
| **Siren's Bell** (sledge) | Devastating damage and stagger | Enormous noise on every connect — audible across the map |
| **The Long Argument** (spear) | Exceptional reach; near-zero bite risk | Very low damage; kills take forever |
| **Grandfather's Deer Rifle** | Superb accuracy and stopping power | Single shot, agonizing reload, cannot take a suppressor |
| **The Tetanus Special** (pipe) | Heavy bleed; free to repair from scrap | Any damage you take while holding it risks a serious infection |
| **Quietkeeper** (bow) | Silent, arrows never break | Very slow; useless against armored types |
| **Butcher's Apron** (armor) | Excellent torso coverage | Permanent, powerful [scent](03-attention.md) emission |

Note how many drawbacks are *attention* costs. Named items are where the item system most directly
plugs into the spine.

## Attachment slots

The mechanism that lets a build survive an upgrade — PoE's "your gems come with you."

| Base class | Slots |
|---|---|
| Firearm | optic · barrel · magazine · furniture |
| Bow / crossbow | sight · limb · string |
| Melee | head/edge · haft · wrap |
| Body armor | plate · lining · pocket |
| Headgear | face · light mount |
| [Vehicle](25-vehicles.md) | engine · exhaust · tires · plating · storage · lights · winch · hitch |

Attachments are **found, not crafted**, and **move freely between compatible bases**. Finding a better
rifle upgrades your numbers without discarding the suppressor, optic, and extended magazine you spent
two months assembling.

Attachments have their own costs: suppressors wear out fast and cost accuracy; optics are useless in
the dark without a light, and a weapon light is an attention emitter aimed at whatever you're looking
at; extended magazines add weight and steady time; armor plates add heat and stamina drain.

## Armor and coverage

Armor is modeled as **coverage per body part**, not as a damage number.

Each piece covers specific parts at a material-derived protection value. What that value does:

1. Reduces the chance a zombie attack breaks skin at all
2. **Sharply reduces [infection transmission](06-infection.md) if it does**
3. Modestly reduces physical damage

And what it costs: weight (stamina, movement), heat retention (a real problem in summer,
a benefit in winter), noise for rigid materials, and encumbrance on fine work.

**Design consequence:** you cannot armor your way out of danger. You can armor your way out of losing
someone permanently, some of the time, at a real cost — which is the correct role for armor in a game
where [bodies are cheap and people are expensive](07-survivors.md).

## Condition and degradation

Everything wears. Condition affects performance continuously — a degraded blade is dull and slow, a
degraded firearm jams.

| Condition | Effect |
|---|---|
| 100–80% | Nominal |
| 79–50% | Noticeable performance loss |
| 49–20% | Serious; firearms jam regularly |
| 19–1% | Barely functional |
| 0% | **Broken.** Repairable at a heavy material cost, or stripped for parts. |

Repair needs materials, a workbench, and Craft skill, and **never restores full condition** — each
repair lowers the ceiling. Every item in the game is on a slow trip toward scrap, which is what makes
a supply of new bases a permanent need and keeps scavenging relevant forever.

## Inventory: space and weight

Two constraints, deliberately independent.

**Space decides what fits.** A container is a rectangle of cells and every item has a footprint, so
a sleeping bag and a scalpel are different problems even when they weigh the same. Items rotate 90°
to fit, and containers nest — a pack holds a toolbox holds a rig — to a depth of three.

One cell is about a fist, which puts the scale roughly where Tarkov's is:

| | Footprint | |
|---|---|---|
| Bandage, painkillers, energy drink, tin, scrap | 1×1 | the filler that makes a bag feel lived-in |
| Kitchen knife, water bottle | 1×2 | |
| Machete, steel pipe | 1×3 | |
| Aluminium bat | 1×4 | |
| Lashed spear | 1×5 | long enough that most bags refuse it upright |
| Field medkit, utility pouch | 2×2 | |
| Fuel can | 2×3 | |
| Fire axe | 2×4 | wide *and* long — the item that teaches you rotation |
| Demolition sledge | 2×5 | a third of a hiking pack, and worth it |
| Canvas satchel, steel toolbox | 3×2 | |
| Chest rig | 3×3 | |
| Hiking pack | 4×4 | opens into 6×8 |

**Footprints have to disagree with each other**, and that is a design constraint rather than
flavour. If every item is one cell wide, rotation does nothing and packing a bag is sorting a list.
The 2-wide items are what make the puzzle a puzzle, and the mix of long-and-thin against
short-and-fat is what makes leaving something behind an actual choice.

**Weight decides what it costs to move.** Mass counts everything nested inside a container, so a pack
full of tins weighs what the tins weigh. Over capacity costs movement speed and stamina recovery,
and movement speed is [the thing that keeps you alive](05-health-injury.md). Capacity comes from
strength, [web nodes](08-skill-web.md), and what you are wearing.

### Why a grid rather than a weight bar

Because [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) prohibits "any UI
that would collapse this uncertainty into a number", and a capacity bar is exactly that. **A grid is
the same information rendered as shape.** You do not read that the pack is 78% full; you see that the
axe no longer fits.

Inventory and the [condition view](05-health-injury.md#the-condition-view) now share one survivor
panel with **Equipment / Injuries** tabs. Both satisfy clause 4 by being layouts rather than
measurements: equipment slots surround the same body whose regions carry injury tint and prose.
Weight survives as the second, invisible pressure: it is never printed, and you learn you are
overloaded because you are walking slower.

The one number on the screen is a stack count. Knowing you have three bandages is not uncertainty
being collapsed; it is counting discrete objects.

### What you can carry is what you chose to wear

Pockets are innate and small — enough to carry a find home after losing a bag, not enough to make
bags optional. Everything beyond that is worn: a pack on the back, a rig on the chest, a satchel on
the belt. **Equipping a container is what grants its grid**, so a scavenging run begins with choosing
what to bring to put things in, and losing your pack is losing your capacity rather than losing a
number.

The recurring scavenging decision: you found more than you can carry, it's getting dark, and coming
back tomorrow means the trip again. Greed is a mechanic — and the grid is what makes it a *decision*
rather than an arithmetic check, because leaving the axe behind and taking three tins is a shape you
can see.

## Content shape

Every base, affix, attachment, named item, and armor piece is a JSON entry with a stable string ID
([content](20-ecs-and-content.md)). Effects are expressed as [modifiers](21-extensibility.md), the same
pipeline used by web nodes, weather, and injuries.

Adding a weapon is a data edit. Adding a new *affix* is a data edit. Adding a new attachment slot type
is a data edit plus a line in the slot-compatibility table.

## Cut list

- **Item rarity beyond four tiers.** Four is legible; PoE's full ladder isn't needed at this scale.
- **Sockets/gems as literal linked skill granters.** The attachment system covers the "build travels
  with you" need without importing PoE's socket-colour lottery.
- **Set bonuses.** Encourages wearing worse items for a completion bonus; contradicts scavenging.
- **Enchanting-style affix crafting with full determinism.** See [crafting](11-crafting.md) — the
  gambling is the point.

---

**Previous:** [29 — Movement & Stances](29-movement-and-stances.md) · **Next:** [11 — Crafting & Modification](11-crafting.md) ·
[Doc index](../README.md#documentation)
