// Booting a world.
//
// One function, used by the game, the tests, the benchmarks and the module-isolation
// check -- so all four exercise the same startup path. If the benchmark booted differently
// from the game it would be measuring something the game never does.

import { WEAPONS } from "./combat";
import type { ContentRegistry } from "./content/registry";
import { AttentionField, DEFAULT_CALIBRATION, type Calibration } from "./field/attention";
import { Facing, Position, Velocity } from "./kernel/components";
import type { EntityId } from "./kernel/entities";
import { TICK_HZ, World } from "./kernel/world";
import { DISTRICT_TILES, findOpenTile, generateDistrict, type TileMap } from "./map/tilemap";
import { ModuleRegistry, type Module } from "./modules";
import { SpatialHash } from "./spatial/hash";
import { attentionModule, makeEmitter } from "./modules/attention";
import { fieldMemoryModule } from "./modules/field-memory";
import { healthModule, makeBody, makeStamina } from "./modules/health";
import { inventoryModule, makeInventory, stow, equip } from "./modules/inventory";
import { itemModule, spawnItem } from "./modules/items";
import { makeMeleeArmed, meleeModule } from "./modules/melee";
import { movementModule } from "./modules/movement";
import { Controlled, playerModule } from "./modules/player";
import { makeShambler, shamblerModule } from "./modules/shambler";
import { DAY_BEGINS, publishPhaseChanges, tickAtTimeOfDay } from "./time/clock";
import { DAYLIGHT_EYES, Observer, SHAMBLER_EYES } from "./vision/visibility";

/** Every non-kernel module in the build. The isolation test walks this list. */
export const ALL_MODULES: readonly Module[] = [
  attentionModule,
  fieldMemoryModule,
  healthModule,
  inventoryModule,
  itemModule,
  meleeModule,
  movementModule,
  playerModule,
  shamblerModule,
];

/**
 * Bases that can be found lying in the street, with relative weights.
 *
 * A stand-in for docs/12-resources.md's per-location loot tables, which want the world model
 * -- houses, shops, medical sites -- that Milestone 2 brings. Weighted so bandages and scrap
 * are common and a fire axe is a find, which is the only property the grid needs today: that
 * what you carry home is a decision rather than a formality.
 */
const STREET_LOOT: readonly { baseId: string; weight: number }[] = [
  { baseId: "item.scrap.metal", weight: 100 },
  { baseId: "item.bandage.cloth", weight: 70 },
  { baseId: "item.food.canned", weight: 55 },
  { baseId: "item.water.bottle", weight: 40 },
  { baseId: "item.knife.kitchen", weight: 30 },
  { baseId: "item.pipe.steel", weight: 25 },
  { baseId: "item.pouch.utility", weight: 18 },
  { baseId: "item.bat.aluminium", weight: 14 },
  { baseId: "item.rig.chest", weight: 10 },
  { baseId: "item.spear.improvised", weight: 8 },
  { baseId: "item.pack.hiking", weight: 6 },
  { baseId: "item.axe.fire", weight: 4 },
];

/** How many items to strew across the district at boot. */
const STREET_LOOT_COUNT = 60;

/**
 * Put findable things on the ground.
 *
 * Its own RNG stream, because adding loot must not shift the placement stream every existing
 * test's expectations are pinned against -- stream seeds hash (masterSeed, name), so a new
 * stream costs the old ones nothing.
 */
function scatterLoot(world: World, map: TileMap, mapSize: number): void {
  const rng = world.rng.stream("loot-placement");
  const total = STREET_LOOT.reduce((sum, entry) => sum + entry.weight, 0);

  for (let i = 0; i < STREET_LOOT_COUNT; i++) {
    let roll = rng.float(0, total);
    let baseId = (STREET_LOOT[0] as { baseId: string }).baseId;
    for (const entry of STREET_LOOT) {
      roll -= entry.weight;
      if (roll < 0) {
        baseId = entry.baseId;
        break;
      }
    }

    const tile = findOpenTile(map, rng.int(1, mapSize - 2), rng.int(1, mapSize - 2));
    const item = spawnItem(world, baseId);
    world.components.set(item, Position, { x: tile.x, y: tile.y });
  }
}

export type BootOptions = {
  seed: number;
  /** Module ids to leave switched off. Used by the isolation test and sandbox presets. */
  disabled?: readonly string[];
  /** How many shamblers to place. */
  wanderers?: number;
  mapSize?: number;
  /**
   * How many of the shamblers are given eyes.
   *
   * Zero by default, and that is a statement about cost rather than about zombies. Per-observer
   * visibility is the one thing in this project that does not amortise across the horde
   * (docs/22-performance.md#visibility-is-a-different-cost-shape), so who observes is a
   * *tiering* decision the caller makes, not something spawning implies. The benchmark uses
   * this to measure the shape; the game does not use it yet, because zombies get sight when
   * the light channel does.
   */
  observers?: number;
  /**
   * Where in the day to start, as a fraction: 0 is the start of dawn, 0.75 is nightfall.
   * Defaults to {@link DAY_BEGINS} -- morning, in full light -- because tick 0 is the
   * *darkest* moment of the cycle and opening a fresh run half-blind is not a default.
   *
   * Not stored anywhere, because it does not need to be -- time of day is a pure function of
   * `world.tick`, so starting at dusk *is* starting at a different tick. That keeps a save
   * consistent with the world it was taken in for free: the tick is already in the snapshot,
   * and there is no second copy of the time to disagree with it.
   */
  startTimeOfDay?: number;
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
    observers = 0,
    startTimeOfDay = DAY_BEGINS,
    mapSize = DISTRICT_TILES,
    content,
    calibration = DEFAULT_CALIBRATION,
  } = options;

  const map = generateDistrict(seed, mapSize);
  const field = AttentionField.forMap(map, calibration, TICK_HZ);
  const spatial = SpatialHash.forMap(map);
  const world = new World(seed, {
    field,
    spatial,
    ...(content === undefined ? {} : { content }),
  });

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

  // Scent is kernel for the same reason noise is, and one more besides. Noise stops mattering
  // when nothing emits; scent does not -- a district that has been lived in goes on smelling
  // for the better part of an hour, and the system that fades it must not be something a
  // sandbox preset can switch off. This is also the only propagation that runs when nothing
  // at all has happened, which is precisely what makes it the risk docs/23 names.
  world.systems.register({
    id: "kernel.attention-scent",
    phase: "attention-propagate",
    run: (w) => {
      if (w.tick % w.field.calibration.scentIntervalTicks === 0) w.field.diffuseScent();
    },
  });

  world.events.subscribe({
    id: "kernel.attention-scent-emit",
    type: "scent.accumulated",
    handler: (event) => world.field.addScent(event.x, event.y, event.magnitude),
  });

  // Visibility is kernel, beside the field and for the same reason: the renderer, the light
  // channel and the multiplayer view filter are three consumers of one answer
  // (docs/28-visibility-and-sightlines.md#one-primitive-three-consumers), and a module that
  // can be switched off must not be what decides whether the game draws through walls.
  //
  // In `movement`, after `movement.integrate` (order 0), because a view computed before the
  // bodies moved is a view of where they were -- and it is the one place in the tick where
  // both position and facing are final for everybody.
  // The spatial hash is kernel beside the two above, and rebuilt here rather than lazily on
  // first query: a lazy rebuild would make the answer depend on who asked first, which is a
  // determinism bug that only appears once two systems both want neighbours.
  //
  // Order 50 puts it after `movement.integrate` (order 0) and before `kernel.visibility`
  // (order 100) -- late enough that every body is where it ends the tick, early enough that
  // the combat phase, which runs next, is asking about final positions rather than stale ones.
  world.systems.register({
    id: "kernel.spatial",
    phase: "movement",
    order: 50,
    run: (w) => w.spatial.rebuild(w),
  });

  world.systems.register({
    id: "kernel.visibility",
    phase: "movement",
    order: 100,
    run: (w) => w.vision.refresh(w, map),
  });

  // The clock is kernel, and for a blunter reason than the field was: a module that could be
  // switched off must not be what stops the sun coming up. Registered in `input` ahead of
  // everything, so a system reacting to nightfall does so on the tick it fell rather than the
  // one after.
  world.systems.register({
    id: "kernel.clock",
    phase: "input",
    order: -100,
    run: publishPhaseChanges,
  });

  // Starting at dusk is starting at a different tick -- see BootOptions.startTimeOfDay.
  world.tick = tickAtTimeOfDay(startTimeOfDay);

  const modules = new ModuleRegistry();
  for (const module of ALL_MODULES) modules.add(module);
  for (const id of disabled) modules.disable(id);
  modules.registerAll({ world, map });

  const centre = Math.floor(mapSize / 2);
  const spot = findOpenTile(map, centre, centre);

  const player = world.spawn();
  world.components.set(player, Position, { x: spot.x, y: spot.y });
  world.components.set(player, Velocity, { dx: 0, dy: 0 });
  // Everything that moves is an observer, so facing is handed out here beside position and
  // velocity rather than by a module. Zero -- due east -- is an arbitrary but *fixed*
  // start: drawing it from the RNG would consume from a stream every existing test's
  // expectations are pinned against, which is a large behaviour change wearing the costume
  // of a small one.
  world.components.set(player, Facing, { radians: 0 });
  world.components.set(player, Controlled, { sprinting: false });
  // Eyes. Given here rather than by the player module because being able to see is not a
  // property of being controlled -- NPC survivors will carry exactly this, and the
  // multiplayer host will carry one of these per client survivor.
  world.components.set(player, Observer, { ...DAYLIGHT_EYES });
  makeEmitter(world, player);
  // Something to spend. Handed out here rather than by the health module for the same reason
  // eyes are: being able to tire is a property of being a body, not of being controlled.
  makeStamina(world, player);
  // A bat, because it is the middle of the three and the one that shows the loop best: enough
  // reach to be usable, enough stagger to make a crowd survivable, heavy enough that the
  // windows are visible. Which weapon a survivor holds becomes an inventory question when
  // docs/10's item system lands.
  makeMeleeArmed(world, player, WEAPONS.bat);
  // Pockets, slots, and a starting loadout. docs/10-items.md#what-you-can-carry-is-what-you
  // -chose-to-wear: the satchel is what makes the grid a decision on day one rather than a
  // screen that is empty until you find a bag, and the bandages are there so the stacking
  // rules are exercised by simply playing rather than only by a test.
  makeInventory(world, player);
  // Guarded on content actually being loaded, not just on the module being on. Most tests
  // boot with an empty registry -- a world with no content is a legitimate world, and one
  // that threw here would make "there are no items" a crash instead of an absence.
  if (modules.isEnabled("item") && world.content.count("item") > 0) {
    equip(world, player, spawnItem(world, "item.satchel.canvas", { tier: "scavenged" }));
    stow(world, player, spawnItem(world, "item.bandage.cloth", { tier: "scavenged", count: 3 }));
    scatterLoot(world, map, mapSize);
  }

  const placeRng = world.rng.stream("placement");
  for (let i = 0; i < wanderers; i++) {
    const tile = findOpenTile(map, placeRng.int(1, mapSize - 2), placeRng.int(1, mapSize - 2));
    const entity = world.spawn();
    world.components.set(entity, Position, { x: tile.x, y: tile.y });
    world.components.set(entity, Velocity, { dx: 0, dy: 0 });
    world.components.set(entity, Facing, { radians: 0 });
    makeShambler(world, entity, placeRng);
    makeBody(world, entity);
    if (i < observers) world.components.set(entity, Observer, { ...SHAMBLER_EYES });
  }

  return { world, map, modules, player };
}
