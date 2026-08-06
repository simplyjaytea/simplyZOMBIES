// Booting a world.
//
// One function, used by the game, the tests, the benchmarks and the module-isolation
// check -- so all four exercise the same startup path. If the benchmark booted differently
// from the game it would be measuring something the game never does.

import type { ContentRegistry } from "./content/registry";
import { AttentionField, DEFAULT_CALIBRATION, type Calibration } from "./field/attention";
import { Position, Velocity } from "./kernel/components";
import type { EntityId } from "./kernel/entities";
import { TICK_HZ, World } from "./kernel/world";
import { DISTRICT_TILES, findOpenTile, generateDistrict, type TileMap } from "./map/tilemap";
import { ModuleRegistry, type Module } from "./modules";
import { attentionModule, makeEmitter } from "./modules/attention";
import { movementModule } from "./modules/movement";
import { Controlled, playerModule } from "./modules/player";
import { makeShambler, shamblerModule } from "./modules/shambler";

/** Every non-kernel module in the build. The isolation test walks this list. */
export const ALL_MODULES: readonly Module[] = [
  attentionModule,
  movementModule,
  playerModule,
  shamblerModule,
];

export type BootOptions = {
  seed: number;
  /** Module ids to leave switched off. Used by the isolation test and sandbox presets. */
  disabled?: readonly string[];
  /** How many shamblers to place. */
  wanderers?: number;
  mapSize?: number;
  /**
   * Pre-loaded content. `platform/` reads it, so a caller that has it hands it over;
   * everything headless boots without any and the registry stays empty.
   */
  content?: ContentRegistry;
  /**
   * Field calibration. Defaults to the shipped constants; a caller with content loaded
   * should pass `calibrationFromContent(content)` so the JSON is what actually governs.
   */
  calibration?: Calibration;
};

export type Boot = {
  world: World;
  map: TileMap;
  modules: ModuleRegistry;
  /** The controlled entity, if the player module is enabled. */
  player: EntityId | null;
};

/**
 * Build a world.
 *
 * Entity creation happens *after* module registration and in a fixed order, so the ids a
 * run hands out do not depend on which modules are enabled. Otherwise disabling a module
 * would shift every subsequent id and two runs of the same seed would stop matching.
 */
export function boot(options: BootOptions): Boot {
  const {
    seed,
    disabled = [],
    wanderers = 200,
    mapSize = DISTRICT_TILES,
    content,
    calibration = DEFAULT_CALIBRATION,
  } = options;

  const map = generateDistrict(seed, mapSize);
  const field = AttentionField.forMap(map, calibration, TICK_HZ);
  const world = new World(seed, { field, ...(content === undefined ? {} : { content }) });

  // Decay and propagation are kernel, not module. The field is kernel state, and a module
  // that could be switched off must not be what stops noise from fading -- that would turn
  // "disable the attention module" into "the district stays permanently loud". It is also
  // what lets any publisher of `noise.emitted` reach the field without a dependency on the
  // module that happens to own the loudest emitter.
  world.systems.register({
    id: "kernel.attention-decay",
    phase: "attention-propagate",
    run: (w) => w.field.decay(),
  });

  world.events.subscribe({
    id: "kernel.attention-noise",
    type: "noise.emitted",
    handler: (event) => world.field.emitNoise(event.x, event.y, event.magnitude),
  });

  const modules = new ModuleRegistry();
  for (const module of ALL_MODULES) modules.add(module);
  for (const id of disabled) modules.disable(id);
  modules.registerAll({ world, map });

  const centre = Math.floor(mapSize / 2);
  const spot = findOpenTile(map, centre, centre);

  const player = world.spawn();
  world.components.set(player, Position, { x: spot.x, y: spot.y });
  world.components.set(player, Velocity, { dx: 0, dy: 0 });
  world.components.set(player, Controlled, { sprinting: false });
  makeEmitter(world, player);

  const placeRng = world.rng.stream("placement");
  for (let i = 0; i < wanderers; i++) {
    const tile = findOpenTile(map, placeRng.int(1, mapSize - 2), placeRng.int(1, mapSize - 2));
    const entity = world.spawn();
    world.components.set(entity, Position, { x: tile.x, y: tile.y });
    world.components.set(entity, Velocity, { dx: 0, dy: 0 });
    makeShambler(world, entity, placeRng);
  }

  return { world, map, modules, player };
}
