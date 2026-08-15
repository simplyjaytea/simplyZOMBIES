# 10 — Save/load + determinism for alpha systems

Type: grilling
Blocked by: 02, 05, 07, 08, 09

## Question

Alpha now has shipped sim that round-trips under `SAVE_VERSION` 10 (aptitudes, roster types, Mara, district overlay as content) plus **specified-not-built** state that cannot be re-derived on load: window-board overlays and five prose stages, one scrap choke tile, alarm line cells/armed, noisemaker position/wind ticks, director `{grace, lullUntilTick, lastMigrationTick, nightsSinceQuiet}`.

- What is **content** (patch, unique JSON, roster mix constants) vs **state** (must snapshot)?
- Bump `SAVE_VERSION` and reject old saves, or migrate missing keys with defaults (infection Task 3 preferred migrate)?
- RNG: which named streams do fortify verbs and dusk packets consume, so a replay from a mid-lull save does not shift `infection` / `placement`?
- Replay contract: `canonicalize(snapshot())` identical after save/load with boards + packet + Mara dead — what is in the fingerprint vs left as presentation?

Decision is the alpha serialize list + version policy + stream names, so a builder does not dump new keys onto the player entity and break R6.
