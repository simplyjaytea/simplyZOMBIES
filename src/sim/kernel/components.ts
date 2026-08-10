// Component storage and queries.
//
// docs/20-ecs-and-content.md: "Component -- plain serializable data attached to an entity.
// No methods." One map per component type; archetype/SoA storage is explicitly cut there
// as premature until there are real numbers to justify it.

import { entityIndex, type EntityId } from "./entities";

/**
 * A component type handle. The type parameter is phantom -- it exists so `get` and `set`
 * infer the data shape from the key, instead of every call site asserting.
 */
export type ComponentType<T> = {
  readonly id: string;
  /** @internal phantom; never read at runtime */
  readonly __data?: T;
};

export function defineComponent<T>(id: string): ComponentType<T> {
  return { id };
}

export class ComponentStore {
  private readonly stores = new Map<string, Map<EntityId, unknown>>();

  private storeFor<T>(type: ComponentType<T>): Map<EntityId, unknown> {
    let s = this.stores.get(type.id);
    if (s === undefined) {
      s = new Map<EntityId, unknown>();
      this.stores.set(type.id, s);
    }
    return s;
  }

  set<T>(entity: EntityId, type: ComponentType<T>, data: T): void {
    this.storeFor(type).set(entity, data);
  }

  get<T>(entity: EntityId, type: ComponentType<T>): T | undefined {
    return this.stores.get(type.id)?.get(entity) as T | undefined;
  }

  /** Like `get` but throws instead of returning undefined, for "this must exist" reads. */
  getOrThrow<T>(entity: EntityId, type: ComponentType<T>): T {
    const v = this.get(entity, type);
    if (v === undefined) throw new Error(`Entity ${entity} has no component "${type.id}"`);
    return v;
  }

  has<T>(entity: EntityId, type: ComponentType<T>): boolean {
    return this.stores.get(type.id)?.has(entity) ?? false;
  }

  remove<T>(entity: EntityId, type: ComponentType<T>): boolean {
    return this.stores.get(type.id)?.delete(entity) ?? false;
  }

  /** Strip every component from an entity. Called when it is destroyed. */
  removeAll(entity: EntityId): void {
    for (const store of this.stores.values()) store.delete(entity);
  }

  count<T>(type: ComponentType<T>): number {
    return this.stores.get(type.id)?.size ?? 0;
  }

  /**
   * Entities carrying every listed component, **in ascending entity order**.
   *
   * The ordering is a determinism requirement, not a convenience. A Map iterates in
   * insertion order, and insertion order reflects the particular sequence of spawns and
   * despawns that produced it -- which a freshly loaded save does not reproduce, because it
   * rebuilds the maps from a snapshot. Two runs of the same seed would then visit entities
   * in different orders and diverge the moment any system's behaviour depended on that.
   *
   * Sorting makes iteration order a function of state alone. At the ~3,000 entities
   * docs/22-performance.md targets this is negligible. If the perf harness ever disagrees,
   * the fix is a sorted-insert index -- never dropping the guarantee.
   */
  query(...types: readonly ComponentType<unknown>[]): EntityId[] {
    if (types.length === 0) return [];

    // Drive the scan from the smallest store so the intersection costs as little as possible.
    let smallest = this.stores.get((types[0] as ComponentType<unknown>).id);
    if (smallest === undefined) return [];

    for (let i = 1; i < types.length; i++) {
      const s = this.stores.get((types[i] as ComponentType<unknown>).id);
      if (s === undefined) return [];
      if (s.size < smallest.size) smallest = s;
    }

    const out: EntityId[] = [];
    outer: for (const entity of smallest.keys()) {
      for (const type of types) {
        if (this.stores.get(type.id)?.has(entity) !== true) continue outer;
      }
      out.push(entity);
    }

    // By slot index: stable across recycling, and it matches EntityStore.all().
    out.sort((a, b) => entityIndex(a) - entityIndex(b));
    return out;
  }

  /** Serializable snapshot. Component ids and entities both sorted, so output is canonical. */
  save(): Record<string, [EntityId, unknown][]> {
    const out: Record<string, [EntityId, unknown][]> = {};
    for (const typeId of [...this.stores.keys()].sort()) {
      const entries = [...(this.stores.get(typeId) as Map<EntityId, unknown>).entries()];
      entries.sort((a, b) => entityIndex(a[0]) - entityIndex(b[0]));
      out[typeId] = entries;
    }
    return out;
  }

  restore(saved: Record<string, [EntityId, unknown][]>): void {
    this.stores.clear();
    for (const [typeId, entries] of Object.entries(saved)) {
      this.stores.set(typeId, new Map(entries));
    }
  }
}

/**
 * Kernel components -- the only ones every entity may rely on
 * (docs/20-ecs-and-content.md#component-inventory). Everything else belongs to a module,
 * and per that doc only the owning module may write to its own components.
 */
export type Position = { x: number; y: number };
export type Velocity = { dx: number; dy: number };
/**
 * Which way an entity is looking, in radians, measured the way `Math.atan2` measures:
 * 0 is +x, increasing counter-clockwise, normalised to (-pi, pi].
 *
 * Kernel rather than module-owned because two separate systems will read it and neither
 * owns the other: sightlines need it to know what an observer can see, and aiming needs it
 * to know where a weapon points (docs/28-visibility-and-sightlines.md#what-an-observer-is,
 * docs/09-combat.md#aiming). Specified once here so combat does not grow a second heading
 * that drifts out of agreement with the first.
 *
 * **It persists when the body stops.** Facing is not derived from velocity -- it is
 * *updated* from velocity while there is some, and left alone when there isn't. A survivor
 * standing still is still looking somewhere, and zeroing this on every halt would mean an
 * observer snapped east every time they stopped walking.
 *
 * Writers must normalise negative zero away: `Math.atan2(-0, 1)` is `-0`, and
 * `canonicalize` rejects it outright (see serialize.ts), so an unguarded write turns the
 * next save into a thrown error rather than a wrong number.
 */
export type Facing = { radians: number };
export type Tags = { values: string[] };

export const Position = defineComponent<Position>("Position");
export const Velocity = defineComponent<Velocity>("Velocity");
export const Facing = defineComponent<Facing>("Facing");
export const Tags = defineComponent<Tags>("Tags");

/**
 * The heading of a velocity, normalised for storage in `Facing`.
 *
 * Returns `null` for a stationary body rather than a default angle, so callers are forced
 * to decide what "not moving" means instead of silently getting east.
 */
export function headingOf(dx: number, dy: number): number | null {
  if (dx === 0 && dy === 0) return null;
  const radians = Math.atan2(dy, dx);
  // `+ 0` collapses -0 to 0. See the note on Facing: canonicalize rejects negative zero,
  // and atan2 reaches it for any due-east heading with a negative-zero dy.
  return radians + 0;
}
