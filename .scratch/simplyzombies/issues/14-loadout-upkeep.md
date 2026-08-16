# 14 — Loadout upkeep (wear + Repair)

Type: grilling
Status: resolved
Blocked by:

## Question

Early-alpha tickets 01–13 are shipped. Roadmap M2 build-order step 4 still names **loadout upkeep** after the shallow web. Condition already scales damage/speed, but nothing lowers it; Repair/Modify columns are stubs. What ships now?

## Answer (solo decider — recommended)

### Q1:A — Active wear on `attack.connected`

Equipped primary/secondary weapon loses condition per connected hit. At 0 → `item.broke`, unequip. Refresh live `meleeWeapon`/`rangedWeapon` profiles so wear is felt without re-equip. Misses / barehanded deferred.

### Q2:A — Repair Job consumer (not Modify)

Find owned/stockpile item with `current < ceiling`, scrap metal + campfire station, channel → restore some `current`, lower `ceiling`. Auto Focus priority 3; Worker 2. Modify + attachment readers stay deferred.

### Q3:A — Gate `godot:m2:upkeep`

Wear + broke + repair ceiling drop; hook on `godot:m2`.

### Deferred

Modify job · attachment slot readers · jam-from-condition · wear on miss/fire · dedicated workbench entity.

Status: resolved.

## Notes

- Docs: 10-items condition, 11-crafting Repair, roadmap M2 §4, HANDOFF wear leftover.
- ADR: `docs/adr/0014-loadout-upkeep.md`.
