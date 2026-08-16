# Loadout upkeep — wear + Repair

Ticket [14](../../.scratch/simplyzombies/issues/14-loadout-upkeep.md). Closes the M2 roadmap “loadout upkeep” gap: condition already multiplies damage/speed, but nothing wore items down and Repair was a stub.

**Status:** accepted

## Wear

Subscribe in `SimItems.register_module` to `attack.connected`. Resolve the attacker’s equipped `primary` (else `secondary`) weapon item; subtract a fixed wear step from `condition.current` (clamped at 0). When crossing to 0, publish `item.broke` and unequip. Otherwise refresh `meleeWeapon` / `rangedWeapon` from the live profile so the next swing/shot feels the wear.

Bare hands, misses, and armor wear are out of scope.

## Repair

Add **Repair** to `CONSUMERS`. Auto Focus = 3; Worker = 2.

Work: owned or Stockpile item with `current < ceiling` + `item.scrap.metal` available + campfire station → A* → channel → consume one scrap → `current = min(ceiling, current + gain)` → `ceiling = max(floor, ceiling - drop)`. Never restores past the (lowered) ceiling.

Campfire stands in for a workbench this slice (`ponytail:` dedicated bench later).

## Gates

`godot:m2:upkeep` asserts wear, broke unequip, and repair ceiling drop.

## Deferred

Modify · attachment readers · firearm jam bands · wear on miss / every shot · workbench entity.
