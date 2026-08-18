# 10 — Save/load + determinism for alpha systems

Type: grilling
Status: resolved
Blocked by: 02, 05, 07, 08, 09

## Question

Alpha now has shipped sim that round-trips under `SAVE_VERSION` 10 (aptitudes, roster types, Mara, district overlay as content) plus **specified-not-built** state that cannot be re-derived on load: window-board overlays and five prose stages, one scrap choke tile, alarm line cells/armed, noisemaker position/wind ticks, director `{grace, lullUntilTick, lastMigrationTick, nightsSinceQuiet}`.

- What is **content** (patch, unique JSON, roster mix constants) vs **state** (must snapshot)?
- Bump `SAVE_VERSION` and reject old saves, or migrate missing keys with defaults (infection Task 3 preferred migrate)?
- RNG: which named streams do fortify verbs and dusk packets consume, so a replay from a mid-lull save does not shift `infection` / `placement`?
- Replay contract: `canonicalize(snapshot())` identical after save/load with boards + packet + Mara dead — what is in the fingerprint vs left as presentation?

Decision is the alpha serialize list + version policy + stream names, so a builder does not dump new keys onto the player entity and break R6.

Grill UI: `grill-10-save-load.html` (a throwaway pick-one-per-card page, since deleted from the repo).

## Answer

**Grilled 2026-08-15 — picks: Q1:A · Q2:A · Q3:A · Q4:A — all recommended. Replay contract follows from Q1/Q2 (not a second fork). Resolved.**

Alpha save stays the kernel snapshot. New sim is either **content** (re-derived from seed + JSON), **state** (must round-trip), or **derived** (rebuild on restore). v10 files are rejected. Fortify and director do not share RNG with `infection` / `placement`.

### Q1 — Content / state / derived

| Thing | Class | Why |
|---|---|---|
| District patch, Mara JSON, roster mix constants, packet size/cap JSON | **Content** | Re-derived from seed + files. Ticket 07 already said the patch is not state. |
| Window-board `{x,y,stage}`, scrap choke, alarm `{cells, armed}`, noisemaker position + `expiresAtTick` | **State** | Cannot re-derive. Mid-siege F9 with an empty overlay is an unboarded annex. |
| Director `{lullUntilTick, lastMigrationTick, nightsSinceQuiet}` | **State** | A lull that forgets itself is not a lull. Grace bounds are constants (`3` / `8`), not saved. |
| Clock phase, annex rect, gate tiles | **Derived** | Tick + content. |
| Vision / light / `mapGeneration`, HUD, paperdoll | **Derived / presentation** | Same as Observer: result is not saved; inputs are. |
| Power / strain integers | **Derived** | Recomputed at dusk from the live bits ([Director pressure for early alpha](09-director-pressure.md) Q5). |

Whole tilemap arrays stay out (B). Command-log replay stays out (C) — `snapshot()` does not record commands.

### Q2 — Director on the world object; fortify as entities

Docs/20: the director is plain world state, not an entity. Placed gear already has a pattern (bloater `contamination` entity rides `components.save()`).

`world.snapshot()` gains one key:

```
director: { lullUntilTick, lastMigrationTick, nightsSinceQuiet }
```

`graceCompositionUntilDay` / `gracePressureUntilDay` are constants on the module, not snapshot fields.

Fortify is entities + components, not a second blob:

| Thing | Components |
|---|---|
| Window board | `position` (tile centre) + `windowBoard {stage:0..4}` — `opacity_at` / `blocks_sight` read this, not a parallel tile array |
| Scrap choke | `position` + `scrapBarricade {}` — `is_solid` true; consumes `item.scrap.metal` at place time, not at load |
| Alarm line | `alarmLine {cells:[{x,y}...], armed:bool}` |
| Noisemaker | `position` + `AttentionEmitter {ambient:45}` + `noisemaker {expiresAtTick}` |

`ponytail: no third save format. Overlay Dictionary on the world was the ticket-08 sketch; entities win because contamination already ships.`

Restore calls `invalidateMap()` after components land so Vision+Light rebuild together (doc 30 light rule). Do **not** re-emit noisemaker noise on load — the field snapshot already holds those cells (same reason field joined the snapshot at version 3).

F9 is `restore(snapshot)` on a world that already has the same seed and content registry. It must **not** re-run `SimBoot.playable` placement or `spawn_unique` — that would resurrect Mara and the original 12.

### Q3 — `SAVE_VERSION` 10 → 11, reject v10

Docs/19: old saves rejected, no migration framework pre-1.0. Ticket 08 already asked for the bump. Infection leaving the stamp at 10 while adding keys was a shortcut, not a new policy.

Bump **Godot** `godot/sim/kernel/serialize.gd` only. The TypeScript oracle is archived at `ts-oracle-final`; do not touch `src/sim/kernel/serialize.ts`.

`save.gd` already prints the stale-save line. A v10 file has no answer to “was this window boarded,” so inventing unboarded defaults is silent corruption.

`ponytail: no v10→v11 key filler; 1.0 can grow a migrator if anyone still has a v11 run.`

### Q4 — `director` stream only

Dusk packets (`pick_type` + edge tile) consume `rng.stream("director")`. The oracle already treats that name as independent of `zombies` / `infection` / `placement`. Fortify verbs consume **none** — contact advances board stage, place/reset/wind are commands.

Do not open `director` at module register. Open on first packet (or first roll). A save taken before the first dusk has no `director` key in `rng.save()`; restore already resets missing streams from `derive_seed(master, name)`, which is zero samples — correct.

Reuse of `placement` is forbidden: it couples boot wanderers to night cadence.

### Replay / fingerprint (follows Q1–Q2)

`canonicalize(snapshot())` is the contract. After save → restore → snapshot, the strings match.

**In the fingerprint:** `version` (11), `tick`, `seed`, `rng` (including `director` once opened), `entities`, `components` (boards, scrap, alarm, noisemaker, Mara absent, packet bodies), `modifiers`, `field`, `director`.

**Out:** vision, light, `mapGeneration`, HUD, paperdoll, power/strain, tilemap arrays, content JSON.

Gate `godot:m2:save` (can live next to fortify/director gates):

1. World at dusk day 8: two windows stage 2, scrap placed, alarm armed, noisemaker `expiresAtTick = tick + 6000`, `lullUntilTick` set, Mara despawned, 3 packet bodies on an edge tile ≠ gate. `serialize()` → restore onto a same-seed world that did **not** re-boot placement → `serialize()` identical. `opacity_at` on those windows is Opaque. `peak_noise()` matches. Mara query empty.
2. Decode a hand-stamped `version: 10` snapshot → `StaleSaveError` / existing reject message.
3. Two worlds, same seed, same dusk packet: `director` samples match; `infection` / `placement` sequences unchanged vs a world that never opened `director`.

### Explicitly deferred

Save migrations · snapshotting Vision/Light · command-log replay · TS `SAVE_VERSION` bump · a `fortify` RNG stream · putting director on a singleton entity.

Status: resolved.

## Notes

- Docs: 19-architecture.md (reject, no migrator), 20-ecs-and-content.md (director is world state), serialize.ts changelog (why bumps happen), 08-fortification-slice.md, 09-director-pressure.md, 07-alpha-district.md.
- Code hooks: `world.snapshot` / `restore`; `save.gd` stale message; `rng_registry.save` opened streams only; `invalidateMap`; bloater contamination as the entity template.
- HITL round 1: Q1–Q4 all A. Replay list is the consequence, not a fifth pick.
