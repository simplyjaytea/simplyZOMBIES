// The world: everything the simulation is, in plain serializable form.
//
// docs/20-ecs-and-content.md#what-ecs-is-not-used-for: singletons -- the attention field,
// weather, the director, the clock -- are plain state on the world object rather than
// entities. "Forcing them into ECS would be dogma without benefit."

import { ContentRegistry } from "../content/registry";
import { ModifierStore, type ModifierStoreSave } from "../modifiers/modifiers";
import { defineCoreStats, StatRegistry } from "../modifiers/stats";
import { RngRegistry, type RngState } from "../rng";
import { CommandQueue } from "./commands";
import { ComponentStore } from "./components";
import { TILE_METRES, type TileMap } from "../map/tilemap";
import { EntityStore, type EntityId, type EntityStoreSave } from "./entities";
import { EventBus } from "./events";
import { AttentionField, type FieldSave } from "./field";
import { SpatialHash } from "./spatial";
import { canonicalize, SAVE_VERSION } from "./serialize";
import { SystemRegistry } from "./systems";

/** Fixed simulation rate (docs/22-performance.md#targets). */
export const TICK_HZ = 20;
export const TICK_SECONDS = 1 / TICK_HZ;

export type WorldSnapshot = {
  version: number;
  tick: number;
  seed: number;
  rng: Record<string, RngState>;
  entities: EntityStoreSave;
  components: Record<string, [EntityId, unknown][]>;
  modifiers: ModifierStoreSave;
  field: FieldSave;
};

export class World {
  /** Ticks since the run began. sim/ has no other notion of time -- there is no clock here. */
  tick = 0;

  readonly seed: number;
  readonly rng: RngRegistry;
  readonly entities = new EntityStore();
  readonly components = new ComponentStore();
  readonly events = new EventBus();
  readonly systems = new SystemRegistry();
  readonly commands = new CommandQueue();

  /**
   * The attention field (docs/03-attention.md).
   *
   * Kernel state, not a module: docs/19 lists it beside the tick loop and the entity store,
   * and every module that reads stimulus depends on it existing. A plain property on the
   * world rather than an entity, per docs/20's rule for singletons.
   */
  readonly field: AttentionField;

  /**
   * Neighbour lookups (docs/22-performance.md#spatial-partitioning).
   *
   * Derived, not state: rebuilt from positions, so it is absent from the snapshot. A save
   * that carried it could disagree with the positions it was built from, which is the class
   * of bug that only appears after a load.
   */
  readonly spatial: SpatialHash;

  /** Stat definitions. Code, not state -- the same every boot, so it isn't in the snapshot. */
  readonly stats = new StatRegistry();
  /** Live modifiers. State, and in the snapshot. */
  readonly modifiers: ModifierStore;
  /** Loaded content. Also code-adjacent: reloaded from disk at boot, never serialized. */
  readonly content = new ContentRegistry();

  /**
   * The map is required because the attention field is sized and shaped by it -- noise
   * routes around buildings, so the field cannot be built before the terrain exists. The
   * map itself stays out of the snapshot: it regenerates from the seed (docs/24#generation).
   */
  constructor(
    seed: number,
    readonly map: TileMap,
  ) {
    this.seed = seed >>> 0;
    this.rng = new RngRegistry(this.seed);
    defineCoreStats(this.stats);
    this.modifiers = new ModifierStore(this.stats);
    this.field = new AttentionField(map);
    this.spatial = new SpatialHash(map.w * TILE_METRES, map.h * TILE_METRES);
  }

  spawn(): EntityId {
    return this.entities.create();
  }

  /** Destroy an entity and strip its components and modifiers. */
  despawn(entity: EntityId): boolean {
    if (!this.entities.destroy(entity)) return false;
    this.components.removeAll(entity);
    // Otherwise a recycled id would inherit the previous occupant's injuries.
    this.modifiers.removeScope(entity);
    return true;
  }

  /**
   * The full simulation state, in the form both saves and the determinism test consume.
   *
   * Deliberately excludes systems and subscriptions: those are code, re-registered at boot.
   * Including them would make a save depend on which modules were enabled when it was
   * written, which is the coupling docs/19's module-isolation rule exists to prevent.
   */
  snapshot(): WorldSnapshot {
    return {
      version: SAVE_VERSION,
      tick: this.tick,
      seed: this.seed,
      rng: this.rng.save(),
      entities: this.entities.save(),
      components: this.components.save(),
      modifiers: this.modifiers.save(),
      field: this.field.save(),
    };
  }

  restore(snapshot: WorldSnapshot): void {
    if (snapshot.version !== SAVE_VERSION) {
      // docs/19-architecture.md#save-model: detect and reject cleanly. No migrations
      // pre-1.0, and above all no silent corruption.
      throw new Error(
        `Save version ${snapshot.version} is not supported (expected ${SAVE_VERSION}). ` +
          `Saves may break pre-1.0 and are not migrated.`,
      );
    }
    if (snapshot.seed !== this.seed) {
      throw new Error(`Save seed ${snapshot.seed} does not match world seed ${this.seed}`);
    }
    this.tick = snapshot.tick;
    this.rng.restore(snapshot.rng);
    this.entities.restore(snapshot.entities);
    this.components.restore(snapshot.components);
    this.modifiers.restore(snapshot.modifiers);
    this.field.restore(snapshot.field);

    // The command queue is not part of the snapshot, so it would otherwise survive a
    // restore untouched -- carrying the discarded timeline's input into the resumed one.
    // Invisible to any test that restores into a freshly booted world, which is every test
    // here; main.ts's load() is the only caller that restores into a live one.
    this.commands.reset();
  }

  /** Canonical string form. Two worlds are identical iff these strings are equal. */
  serialize(): string {
    return canonicalize(this.snapshot());
  }
}
