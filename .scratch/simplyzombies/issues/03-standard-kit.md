# 03 — Standard kit of gear for early alpha

Type: grilling
Status: resolved
Blocked by: 01, 02

## Question

Q1 wants a "standard kit of gear" that works with alpha roster and stats on shipped grid + affix inventory. Must prove melee vs ranged parity (doc 09) at hour 2.

- Melee bases: which 3–4 ship (e.g., knife, axe, spear for reach, blunt for stagger)? How do reach/stagger/kill-quality vs stamina/weight trade?
- Ranged bases: which 1–2 ship for alpha (bow for quiet branch vs pistol/shotgun for ammo+noise cost)? How does this pair with zombie choice (Screamer demands silent kill)?
- Armor: which coverage pieces ship and how does armor coverage reduce bite transmission (85% roll, 30% scratch presentation)?
- Affixes + condition/wear: which affix pools active in alpha? Does `Condition` decay via `attack.connected` subscriber now or stay read-only?
- Grid/attachments: which bases declare slots (`head`, `haft`, `wrap` …) and which attachments actually move between compatibles in alpha?
- Loot: ~15 resource types / 3 tables → what is alpha subset, and where in district?

Decision is named kit list + per-item role in parity + what explicitly doesn't degrade/attach yet.

## Answer

**Kit: 4 melee + 2 ranged + 2 armor + 6 affixes + read-only condition + slots declared, no attachments.** Proves parity (doc 09) at hour 2 without bloat.

**Melee — ship 4 of 7, defer 3:**
- `item.knife.kitchen` — 0.9 m / 0.6 wt / 9 dmg / 4 stagger, 1×2, 0.2 kg — *speed.* 3-tick windup, ~4 stamina. Lowest risk when you land headshots, worst when you don't (no stagger). Teaches "fast ≠ safe."
- `item.bat.aluminium` — 1.4 m / 1.2 / 11 / 16, 1×4, 1.0 kg — *stagger.* Best stagger/weight ratio. Anti-grab, anti-crowd. Quiet (8 noise) crowd control.
- `item.spear.improvised` — 2.4 m / 1.0 / 10 / 8, 1×5, 1.4 kg — *reach.* Zero bite risk at max range, lowest DPS. Kill takes 3–4 hits (zombie body 25/60/40). Teaches "spear is safe until you're surrounded."
- `item.axe.fire` — 1.6 m / 1.5 / 14 / 10, 2×4, 3.2 kg — *damage.* Hardest hit, heaviest, slowest (9-tick windup, 12-tick recover, ~9 stamina). Teaches weight/stamina tax.
- Deferred: `item.machete.rusted`, `item.pipe.steel`, `item.sledge.demolition` stay in `godot/content/items/melee.json` but excluded from alpha loot tables — no delete.

**Ranged — ship bow + pistol (quiet + loud parity pair):**
- `item.bow.hunting` *(new)* — `weapon.ranged`, 1×4, 1.1 kg, `primary`, slots `[sight, limb, string]`, `ranged {damage 12, noise 4, ammo arrow, recoverable 0.7, reload 24 ticks (1.2s), accuracy wide while moving}`. *Screamer answer.* Silent clearing, field-memory safe. Fails vs Bloater cloud (must enter 6 m to loot arrows) and vs armored later.
- `item.pistol.service` *(new)* — `weapon.ranged`, 1×2, 0.9 kg, `secondary` (so melee primary + pistol secondary is legal loadout), slots `[barrel, magazine]`, `ranged {damage 18, noise 180, flash 60 at night, ammo 9mm, mag 8, reload 40 ticks (2s), jam curve via conditionFactor}`. *Parity cost.* Kills Screamer at 15 m in one headshot but pays doc 09's second currency: 180 noise → district flood-fill (~250 m street-reach) + scent + tonight's horde. Starter stock 20 rounds in whole district; no crafting, no loot respawn.
- Schema: `item.schema.json` already allows `class: weapon.ranged` + `slots`; add optional `ranged: {damage, noise, flash?, magSize?, reloadTicks?}` block (all optional, backward-compat). No new stat.

**Armor — ship both:**
- `item.wrap.cloth` — torso 0.3 / arms 0.2, 2×2, 0.2 kg, `torso` — light, low encumbrance/move_speed cost.
- `item.vest.scrap` — torso 0.6 / arms 0.3, 3×3, 2.1 kg, `vest` — heavy, real stamina/move penalty. Both `armor: {part: 0..1}`. Transmission at wound time: `roll < 0.85 * (1 - coverage_of_hit_part)` (max coverage if vest+wrap overlap, else 0). Scratch presentation 30% unchanged. Armor does not reduce raw damage in alpha.

**Affixes + condition:**
- Active pools: all 6 melee prefixes (`serrated, weighted, balanced, reinforced, barbed, lengthened`) + 4 suffixes (`quiet_hand 0.85/0.75/0.6, long_nights, salvage, ruin`) — Quiet Hand is parity-critical (screamer/bloater). `Reinforced` rolls on ranged/armor too. `Deep Pockets` excluded for alpha (container balance out of scope). Tier weights scavenged 100 / modified 35 / field_tested 6 unchanged.
- Condition: **read-only in alpha.** `conditionFactor` (0.55 floor) already scales damage/stagger; no `attack.connected` → decay. `ponytail: wire one subscriber in godot/sim/modules/items.gd on attack.connected — loss = 0.004 * condition_loss stat per connect; upgrade when tuning harness measures miss vs degrade rate.`
- Crafting consumables: none ships. Duct Tape/Scrap Kit deferred per doc 11.

**Grid/attachments:**
- All 4 melee + 2 ranged keep `slots` (`head/haft/wrap` etc.) declared for schema, but **no reader, no movable attachments in alpha.** Mechanic proven by grid rotation/nesting alone. `ponytail: add SimItems.attachment_move() + compatibility table when first attachment base lands; no save change.`

**Loot — alpha subset of 15 / 3 tables:**
- Keep 2 tables, not 3: `residential` (low danger, scavenged 90%/modified 10%) and `military_cache` (single crate, field_tested pistol).
- Residential pool (6 types): `canned.food` 1×1×3, `bandage.cloth` 1×1×5, `painkillers` 1×1×4, `water.bottle` 1×2, `scrap.metal` 1×1×10, `tape.duct` 1×1×3 — scattered, ~40 placements in district. No fuel/antibiotics/medkit/jerrycan in alpha (deferred to survival slice).
- Military cache: 1× pistol.service + 20× 9mm in one locked interior — risk-gated, requires crossing screamer sightline.
- Placement pairs with roster: spear near chokepoint (teaches reach), bat near dense shambler cluster (teaches stagger), knife in start building (default), axe behind bloater contamination flag.

**Explicitly not in alpha:** condition decay, attachments moving, ranged-specific prefixes (Trued/Ported/Chambered etc.), full 15-resource economy, repair, modification consumables, suppressors/bows as upgrades.

Status: resolved — wayfinder decisions so far points here.

## Notes

- Docs: 10-items.md, 09-combat.md, 11-crafting.md (Duct Tape / Scrap Kit), 12-resources.md, 20-ecs-and-content.md, godot/content/ schemas.
- Blocks on roster (ranged need depends on Screamer-like pressure) and stats (DEX/STR affect handling, conditionFactor).
- HITL — kit feel + "one of each role without bloat" is taste.
