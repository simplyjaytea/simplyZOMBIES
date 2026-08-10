// The world: everything the simulation is, in plain serializable form.
//
// docs/20-ecs-and-content.md#what-ecs-is-not-used-for: singletons -- the attention field,
// weather, the director, the clock -- are plain state on the world object rather than
// entities. "Forcing them into ECS would be dogma without benefit."

import { ContentRegistry } from "../content/registry";
import { AttentionField, type AttentionFieldSave } from "../field/attention";
import { ModifierStore, type ModifierStoreSave } from "../modifiers/modifiers";
import { defineCoreStats, StatRegistry } from "../modifiers/stats";
import { RngRegistry, type RngState } from "../rng";
import { SpatialHash } from "../spatial/hash";
import { VisibilityIndex } from "../vision/visibility";
import { CommandQueue } from "./commands";
import { ComponentStore } from "./components";
import { EntityStore, type EntityId, type EntityStoreSave } from "./entities";
import { EventBus } from "./events";
import { canonicalize, SAVE_VERSION } from "./serialize";
import { SystemRegistry } from "./systems";

// Re-exported so that every existing `from "kernel/world"` import keeps working. They live
// in a leaf module because the clock needs them and the clock cannot import this file --
// see tick.ts.
export { TICK_HZ, TICK_SECONDS } from "./tick";

export type WorldSnapshot = {
  version: number;
  tick: number;
  seed: number;
  rng: Record<string, RngState>;
  entities: EntityStoreSave;
  components: Record<string, [EntityId, unknown][]>;
  modifiers: ModifierStoreSave;
  field: AttentionFieldSave;
};

/**
 * Parts a world can be built with rather than building for itself.
 *
 * Both need something the `World` constructor cannot produce on its own: the attention field
 * is sized to a map, and content has to be read by `platform/`. `boot` supplies them.
 */
export type WorldParts = {
  readonly field?: AttentionField;
  readonly content?: ContentRegistry;
  readonly spatial?: SpatialHash;
};

export class World {
  /**
   * The tick counter, and the only notion of time `sim/` has.
   *
   * **Not "ticks since the run began" any more, and the difference matters.** Time of day is
   * a pure function of this number (sim/time/clock.ts), so `boot` starts it in the morning
   * rather than at zero -- tick 0 is the start of dawn, the darkest moment of the cycle.
   * There is no separate clock state to disagree with the save as a result, which is the
   * whole point, but code that wants *elapsed* time must subtract a start tick rather than
   * read this directly. Two tests were quietly measuring the wrong interval within minutes
   * of the clock landing.
   */
  tick = 0;

  readonly seed: number;
  readonly rng: RngRegistry;
  readonly entities = new EntityStore();
  readonly components = new ComponentStore();
  readonly events = new EventBus();
  readonly systems = new SystemRegistry();
  readonly commands = new CommandQueue();

  /** Stat definitions. Code, not state -- the same every boot, so it isn't in the snapshot. */
  readonly stats = new StatRegistry();
  /** Live modifiers. State, and in the snapshot. */
  readonly modifiers: ModifierStore;
  /** Loaded content. Also code-adjacent: reloaded from disk at boot, never serialized. */
  readonly content: ContentRegistry;

  /**
   * The attention field. Kernel, per docs/19-architecture.md#one-spine-many-optional-limbs,
   * so it exists even in a world booted with every module disabled -- what the modules
   * supply is anything that emits into it.
   */
  readonly field: AttentionField;

  /**
   * Who can see what (docs/28-visibility-and-sightlines.md).
   *
   * Kernel for the same reason the field is, and one more besides: the renderer, the light
   * channel and the multiplayer view filter are three consumers of one answer, and a module
   * that can be switched off must not be what decides whether the game draws through walls.
   *
   * **Derived, and deliberately not in the snapshot.** It is a pure function of positions,
   * facings and the tile map -- all three of which the snapshot already holds -- so storing it
   * would create a second copy of a fact and a way for a save to disagree with itself. It
   * rebuilds on the first tick after a load, exactly as the map regenerates from the seed.
   */
  readonly vision = new VisibilityIndex();

  /**
   * What is near what (docs/22-performance.md#spatial-partitioning).
   *
   * Kernel for the reason the field and the visibility index are: docs/22 lists four
   * consumers -- combat, emitter lookups, tier assignment and render culling -- none of which
   * owns the others, and a module that can be switched off must not be what makes neighbour
   * queries work.
   *
   * **Derived, and not in the snapshot**, exactly like `vision`. It is a pure function of
   * positions, which the snapshot already holds. It is rebuilt whole each tick by a kernel
   * system in the movement phase, so it is empty until the first tick after a load -- the
   * same way the tile map regenerates from the seed.
   *
   * Sized to a map by `boot`, and inert until then, so nothing has to null-check the kernel.
   */
  readonly spatial: SpatialHash;

  constructor(seed: number, parts: WorldParts = {}) {
    this.seed = seed >>> 0;
    this.rng = new RngRegistry(this.seed);
    defineCoreStats(this.stats);
    this.modifiers = new ModifierStore(this.stats);
    this.content = parts.content ?? new ContentRegistry();
    // Inert until `boot` sizes one to a map, so nothing has to null-check the kernel.
    this.field = parts.field ?? AttentionField.empty();
    this.spatial = parts.spatial ?? SpatialHash.empty();
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
  }

  /** Canonical string form. Two worlds are identical iff these strings are equal. */
  serialize(): string {
    return canonicalize(this.snapshot());
  }
}
