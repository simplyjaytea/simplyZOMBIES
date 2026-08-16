# Jobs Clean/Bury/Water + succession handoff

Ticket [13](../../.scratch/simplyzombies/issues/13-stub-jobs-and-succession.md) grilled: both Jobs and succession lift. ADR 0010’s “no succession / no Bury Job” is superseded for those two points; corpse scent aging and leave-with-gear still stand.

**Status:** accepted

## Jobs

Add **Water**, **Clean**, and **Bury** to `CONSUMERS`. Auto Focus enables each at priority **3** (with Haul/Construct/Cook/Doctor/Rest). Worker also gets Water 2, Clean 3, Bury 2.

| Job | Work |
|---|---|
| Water | Empty bottle in pockets or Stockpile → walk to `water_source` station → channel → become `item.water.bottle`. Seek still drinks filled bottles only. |
| Clean | Hygiene not `clean` → walk to `water_source` → channel → hygiene `clean` (no bottle consumed at the source). |
| Bury | Corpse with `position` → haul to outdoor dump (south of gate) → channel → despawn corpse (scent gone). Haul no longer picks corpses when Bury is enabled on anyone; if every survivor has Bury off, Haul-to-dump remains as overflow. |

Stations: `boot.place_stations` adds one `water_source` on outdoor Floor near the gate (like Campfire/beds). Dump tile is outdoor Floor south of the gate, not indoors.

## Succession

On death of `world.player` / `controlled`:

1. If another living survivor exists (`needs` or `identity`, not `corpse`/`shambler`): form a corpse (gear stays), remove `controlled`, pick successor — **prefer Mara** (`survivor.unique.mara`), else nearest by position.
2. Set `world.player`, attach `controlled` + daylight `observer`, clear any job on them, publish `player.succeeded`.
3. Do **not** set `runOver`.
4. If no living successor: `runOver` as today (transmitted → turn with kit; else despawn).

Save: snapshot stores `player` id; restore rebinds `world.player` (and `controlled` if missing). No save version bump.

## Annex constants

`SimDirector.ANNEX` and `SimFortify.GATE_A`/`GATE_B` match the authored alpha patch door (south gap), so Guard/dump/harness exclusion stay coherent after the larger house.

## Gates

Extend `godot:m2:jobs`: Water fill, Clean at source, Bury despawn, succession handoff (Mara preferred). Update `godot:m2:recruits` death case: player death with Mara alive → no `runOver`, Mara controlled; solo player → still `runOver`.

## Deferred

Farm/Hunt/Butcher/Craft/Modify/Repair/Firefight · succession chooser · grief/morale · weather · empty-bottle crafting beyond fill.
