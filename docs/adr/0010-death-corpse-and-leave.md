# Death: no succession, corpse or turn, leave-with-gear

The slice playtest is lose-without-succession. Player death ends the run even if Mara lives. NPC deaths still happen in a living run: uninfected → corpse; `transmitted` → they get up as a shambler wearing their kit.

**Status:** accepted

## Player death

Ends the run. No camera handoff. Single-slot save is closed out; F9 does not continue the colony. Mara’s 2-night lull on *her* death still applies while the player lives ([Director pressure for early alpha](../../.scratch/simplyzombies/issues/09-director-pressure.md)).

## Uninfected death (NPC)

Corpse entity at the tile: `position` + inventory grid as-dropped + scent 8. After 1 day, scent 25. Haul can drag it to an outdoor dump tile (not the Stockpile). No bury Job. No reanimation. Rotting is scent only. Ordinary shambler kills still despawn with no loot bag.

## Death while `transmitted`

Any death with private `transmitted` true — starve, grab, gunshot, asymptomatic included — despawns the survivor and spawns a shambler **on that tile with their grid**. Timeline-turn uses the same path. Mood-leave is not a death (they walked out). Putting **that** shambler down drops the grid onto the tile, then despawns as today. Ordinary shamblers do not grow this loot path.

## Mood −80 leave

`mood.threshold` **fires** for NPCs: walk to the gate over ~2 min, keep pockets, despawn, never return. Player character never leaves this way. HUD already has “They’re going to leave.”

## Considered options

- Camera to nearest living survivor — rejected for this slice; succession waits on web/relationships.
- Instant swap, gear teleports — rejected; deletes the recovery of *their* kit.
- Dump gear on the tile at turn, empty shambler — rejected; gear stays on the body that got up.
- Leave publishes but they stay — rejected; the HUD line would be a lie.

## Consequences

- Corpse, turned-shambler loot grid, and “left” absence must round-trip: [0007](0007-needs-era-save.md).
- Inspect still cannot leak `transmitted`: [0009](0009-gate-recruits-and-inspect.md).
- Docs/01 succession and the recovery-run-of-you stay design canon; they are not this slice.
