// Booting a world.
//
// One function, used by the game, the tests, the benchmarks and the module-isolation
// check -- so all four exercise the same startup path. If the benchmark booted differently
// from the game it would be measuring something the game never does.

import { Position, Velocity } from "./kernel/components";
import type { EntityId } from "./kernel/entities";
import { registerAttentionSystems } from "./kernel/attention";
import { World } from "./kernel/world";
import { DISTRICT_TILES, findOpenTile, generateDistrict, type TileMap } from "./map/tilemap";
import { ModuleRegistry, type Module } from "./modules";
import { movementModule } from "./modules/movement";
import { makeZombie, zombieModule } from "./modules/zombies";
import { Controlled, playerModule } from "./modules/player";
import { makeWanderer, wanderModule } from "./modules/wander";

/** Every non-kernel module in the build. The isolation test walks this list. */
export const ALL_MODULES: readonly Module[] = [
  movementModule,
  playerModule,
  wanderModule,
  zombieModule,
];

export type BootOptions = {
  seed: number;
  /** Module ids to leave switched off. Used by the isolation test and sandbox presets. */
  disabled?: readonly string[];
  /** How many wanderers to place. */
  wanderers?: number;
  /** How many shamblers to place. They read the attention field; wanderers do not. */
  zombies?: number;
  /**
   * Whether milling shamblers leave scent residue.
   *
   * The Milestone 1 acceptance check on field memory (docs/03#field-memory-is-a-scent-mechanic)
   * turns this off and asserts something observable changes.
   */
  residue?: boolean;
  mapSize?: number;
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
    zombies = 0,
    residue = true,
    mapSize = DISTRICT_TILES,
  } = options;

  const map = generateDistrict(seed, mapSize);
  const world = new World(seed, map);

  // Kernel systems first: the attention field is not a module and cannot be switched off
  // (docs/19), so it must be registered before anything that might read it.
  registerAttentionSystems(world);

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

  const placeRng = world.rng.stream("placement");
  for (let i = 0; i < wanderers; i++) {
    const tile = findOpenTile(map, placeRng.int(1, mapSize - 2), placeRng.int(1, mapSize - 2));
    const entity = world.spawn();
    world.components.set(entity, Position, { x: tile.x, y: tile.y });
    world.components.set(entity, Velocity, { dx: 0, dy: 0 });
    makeWanderer(world, entity, placeRng);
  }

  for (let i = 0; i < zombies; i++) {
    const tile = findOpenTile(map, placeRng.int(1, mapSize - 2), placeRng.int(1, mapSize - 2));
    const entity = world.spawn();
    world.components.set(entity, Position, { x: tile.x, y: tile.y });
    world.components.set(entity, Velocity, { dx: 0, dy: 0 });
    makeZombie(world, entity, placeRng, { residue });
  }

  return { world, map, modules, player };
}
