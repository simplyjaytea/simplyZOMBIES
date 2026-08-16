# Needs-era save is version 12

Alpha save is already `SAVE_VERSION` 11 (director + fortify entities). Needs, beds, Campfire, spoilage, Job rows, and generated recruits cannot be re-derived. Same rules as [Save/load + determinism for alpha systems](../../.scratch/simplyzombies/issues/10-save-load-determinism.md): reject old files, no migrator, F9 is restore not re-boot.

**Status:** accepted

Bump Godot `SAVE_VERSION` **11 → 12**. Reject v11. TypeScript oracle stays archived.

## Content / state / derived

| Thing | Class |
|---|---|
| Generator tables, unique JSON, district patch, authored bed/Campfire templates | Content |
| `needs` on each survivor | State |
| Campfire lit + `light_source` | State (entity) |
| Constructed beds (`position` + `bed`) | State (entity) |
| Spoilage clock on food items | State |
| Job priorities | State |
| Generated recruits as survivor entities | State |
| `recruits` RNG stream once opened | State |
| Stockpile | Derived (items whose position is indoor exam floor) |
| Need muls, HUD prose, Vision/Light, `indoors` | Derived / presentation |

No third snapshot blob. Restore must not re-run `SimBoot.playable` or `spawn_unique`.

## RNG

Packets stay on `director`. Recruits (who they are, 15% `transmitted`) use **`recruits`**, opened on the first gate beat. Do not open `recruits` at module register. Missing stream on restore = zero samples.

## Gate

Extend `godot:m2:save`: hungry Mara, lit Campfire, one Construct bed, one raw with spoil ticks, one recruit entity, decode v11 → stale reject. `canonicalize` matches after restore.

## Considered options

- Keep 11 and default-fill missing Need keys — rejected; silent corruption (ticket 10).
- A `needsWorld` blob beside `director` — rejected; entities already carry this.

## Consequences

- Recruits: [0009](0009-gate-recruits-and-inspect.md).
- Corpses, turned shamblers, leave-with-gear: [0010](0010-death-corpse-and-leave.md) — those entities also round-trip.
