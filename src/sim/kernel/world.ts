// The world: everything the simulation is, in plain serializable form.
//
// docs/20-ecs-and-content.md#what-ecs-is-not-used-for: singletons -- the attention field,
// weather, the director, the clock -- are plain state on the world object rather than
// entities. "Forcing them into ECS would be dogma without benefit."

import { RngRegistry, type RngState } from "../rng";
import { CommandQueue } from "./commands";
import { ComponentStore } from "./components";
import { EntityStore, type EntityId, type EntityStoreSave } from "./entities";
import { EventBus } from "./events";
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

  constructor(seed: number) {
    this.seed = seed >>> 0;
    this.rng = new RngRegistry(this.seed);
  }

  spawn(): EntityId {
    return this.entities.create();
  }

  /** Destroy an entity and strip its components. */
  despawn(entity: EntityId): boolean {
    if (!this.entities.destroy(entity)) return false;
    this.components.removeAll(entity);
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
  }

  /** Canonical string form. Two worlds are identical iff these strings are equal. */
  serialize(): string {
    return canonicalize(this.snapshot());
  }
}
