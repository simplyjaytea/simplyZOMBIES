# R6 Parity Ledger — every test file disposition.
# R6 exit: no unexplained difference. "Not ported" not a category.
# Categories: exact-port | paired-fixture | replacement | obsolete(rationale)

| file | category | disposition | notes |
|---|---|---|---|
| test/integration/attention.test.ts | paired-fixture | godot/check_r2_full.gd + r4 field parity | noise/scent budgets; TS bench scenario twins stay TS |
| test/integration/content-loads.test.ts | exact-port | godot/check_content.gd | schema + duplicate + extends |
| test/integration/content-reload.test.ts | exact-port | godot/platform/content_reload.gd + main.gd poll | valid reload / invalid no-reload + HUD |
| test/integration/day-night.test.ts | paired-fixture | godot/sim/time/clock.gd + presentation night wash | ambient_light + phase |
| test/integration/determinism.test.ts | paired-fixture | godot/test/r1_parity.gd (per-tick) + r6 tick harness | same seed+commands → byte-identical canonical |
| test/integration/exit-criterion.test.ts | paired-fixture | godot/test/r1_parity.gd | M0 parity fixture |
| test/integration/godot-parity.test.ts | replacement | godot/test/r1_parity.gd | TS oracle harness has no Godot twin; replaced by Godot-side parity |
| test/integration/grabs.test.ts | paired-fixture | godot/check_r3_full.gd | grab/bite/stamina located wound |
| test/integration/inventory.test.ts | paired-fixture | godot/check_r3_full.gd (grid/items/inventory/save) | grid fits/find/occupancy + stack/equip |
| test/integration/light.test.ts | paired-fixture | godot/sim/vision/light.gd + shadowcast.gd | light/shadowcast + emitter table |
| test/integration/melee.test.ts | paired-fixture | godot/sim/combat.gd | swing windup/recovery/commit + stagger |
| test/integration/module-isolation.test.ts | exact-port | godot/check_r3_full.gd (isolation run) | each module disabled boot |
| test/integration/pursue.test.ts | paired-fixture | godot/check_r2_full.gd | shambler gradient + contact pursuit |
| test/integration/save-load.test.ts | exact-port | godot/sim/save.gd + platform/storage.gd | round-trip + corrupt/stale guards |
| test/integration/stances.test.ts | paired-fixture | godot/sim/stances.gd + locomotion.gd | 5-rung ladder speed/noise/price |
| test/integration/terrain.test.ts | exact-port | godot/sim/map/tilemap.gd + surface.gd | Tile / surfaceAt / is_solid |
| test/integration/visibility.test.ts | paired-fixture | godot/sim/vision/visibility.gd + shadowcast | shadowcast + cache per-observer |
| test/integration/zombies-see-light.test.ts | paired-fixture | godot/sim/vision/visibility.gd | light channel vs shambler sight |
| test/unit/components.test.ts | exact-port | godot/sim/component_store.gd | store + ordered query |
| test/unit/content-registry.test.ts | exact-port | godot/platform/content_validator.gd | registry + schema issues |
| test/unit/entities.test.ts | exact-port | godot/sim/entity_store.gd | alloc/recycle + generation |
| test/unit/events.test.ts | exact-port | godot/sim/event_bus.gd | publish + per-tick drain order |
| test/unit/facing.test.ts | exact-port | godot/sim/spatial/hash.gd | facing / octant |
| test/unit/grid.test.ts | exact-port | godot/sim/inventory/grid.gd | footprint/bounds/fits/find/occupancy |
| test/unit/handoff.test.ts | retired | — | checked HANDOFF.md grouping; removed with HANDOFF.md itself (status folded into docs/23) |
| test/unit/health.test.ts | exact-port | godot/sim/modules/health.gd | 6-part body + condition view boundary |
| test/unit/humanoid.test.ts | exact-port | godot/bench/bench.gd (headless cost) | atlas/pose headless — canvas raster obsolete in Godot (presentation draws) |
| test/unit/input.test.ts | exact-port | godot/presentation/main.gd MOVE_KEYS + _pump_input | screen-relative diagonal + stance keys Z/X/C/V |
| test/unit/inventory-screen.test.ts | exact-port | godot/ui/inventory_panel.gd | grid Controls + drag/rotate |
| test/unit/inventory.test.ts | exact-port | godot/sim/modules/inventory.gd + items.gd | stack/equip/nesting + mass |
| test/unit/light.test.ts | exact-port | godot/sim/vision/light.gd | LIGHT_TABLE vs content pin |
| test/unit/model-atlas.test.ts | obsolete | — | TS procedural raster into sheet per archetype; Godot presentation draws diamonds/circles ponytail (no atlas yet). Ledger: obsolete — presentation draws, not atlas. |
| test/unit/modifiers.test.ts | exact-port | godot/sim/modifiers/modifiers.gd | add/mul/min/max/set + source seq |
| test/unit/paperdoll.test.ts | exact-port | godot/ui/paperdoll.gd | tint per region, no numbers cross, posture prose |
| test/unit/pose.test.ts | exact-port | godot/ui/paperdoll.gd + presentation projection | pose selection + advancePhase by distance |
| test/unit/projection.test.ts | exact-port | godot/presentation/projection.gd | world_to_screen / screen_to_world / depth / visible_bounds |
| test/unit/rng.test.ts | exact-port | godot/sim/rng_stream.gd + rng_registry.gd | named streams + (master, name) hash |
| test/unit/serialize.test.ts | exact-port | godot/sim/kernel/serialize.gd | canonicalize (sorted keys, int/float norm) + fingerprint |
| test/unit/shadowcast.test.ts | exact-port | godot/sim/vision/shadowcast.gd | FOV primitive + wall stop |
| test/unit/spatial.test.ts | exact-port | godot/sim/spatial/hash.gd | spatial hash + rebuild |
| test/unit/stagger.test.ts | exact-port | godot/sim/combat.gd | staggerTicks + recover |
| test/unit/stances.test.ts (2) | exact-port | godot/sim/stances.gd (single file) | TS had unit + integration; Godot single stances.gd covers both |
| test/unit/stats.test.ts | exact-port | godot/sim/modifiers/stats.gd | stat registry + define_core_stats |
| test/unit/swing.test.ts | exact-port | godot/sim/combat.gd | windup/recovery/half-angle |
| test/unit/systems.test.ts | exact-port | godot/sim/system_registry.gd | declared insertion order |
| test/unit/tile-range.test.ts | exact-port | godot/sim/map/tilemap.gd | range + bounds |
