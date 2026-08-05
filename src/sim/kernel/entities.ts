// The entity store.
// docs/20-ecs-and-content.md: "Entity -- an integer ID. No data, no behavior."

/**
 * An entity ID: a plain integer, so it serializes and ports without ceremony.
 *
 * The integer packs a generation into its high bits. IDs get recycled, and without a
 * generation a stale reference to a dead entity silently resolves to whichever entity
 * reused its slot. That surfaces as corrupted state hours into a run -- precisely the
 * failure a single-slot, no-save-scumming game (docs/01-hardcore-contract.md) cannot
 * absorb.
 */
export type EntityId = number;

const INDEX_BITS = 20;
const INDEX_MASK = (1 << INDEX_BITS) - 1; // 1,048,575 slots
const GENERATION_MASK = 0xfff; // 4,096 reuses before wraparound

/** ~3,000 entities is the target (docs/22-performance.md). This is headroom, not ambition. */
export const MAX_ENTITIES = INDEX_MASK;

export function entityIndex(id: EntityId): number {
  return id & INDEX_MASK;
}

export function entityGeneration(id: EntityId): number {
  return (id >>> INDEX_BITS) & GENERATION_MASK;
}

function pack(index: number, generation: number): EntityId {
  return ((generation & GENERATION_MASK) << INDEX_BITS) | (index & INDEX_MASK);
}

export type EntityStoreSave = {
  generations: number[];
  alive: boolean[];
  free: number[];
  next: number;
};

export class EntityStore {
  /** generations[i] is the current generation of slot i. */
  private generations: number[] = [];
  /**
   * Whether slot i is currently occupied.
   *
   * Redundant with `free` on paper, and deliberately not. Testing liveness with
   * `free.includes(i)` is O(n), and `all()` calls it once per slot -- so enumerating
   * entities becomes O(n²), roughly 9M operations per call at the target entity count,
   * every tick. `free` still has to stay an ordered array because *which* slot gets reused
   * next is part of the deterministic record; this is just the O(1) membership test.
   */
  private alive: boolean[] = [];
  /** Recycled slot indices, reused LIFO. */
  private free: number[] = [];
  /** Next never-used slot index. */
  private next = 0;

  get count(): number {
    return this.next - this.free.length;
  }

  create(): EntityId {
    const recycled = this.free.pop();
    if (recycled !== undefined) {
      this.alive[recycled] = true;
      return pack(recycled, this.generations[recycled] as number);
    }

    if (this.next >= MAX_ENTITIES) {
      throw new Error(`EntityStore: exhausted ${MAX_ENTITIES} entity slots`);
    }

    const index = this.next++;
    this.generations[index] = 0;
    this.alive[index] = true;
    return pack(index, 0);
  }

  /** True only if this exact id -- index *and* generation -- occupies its slot. */
  isAlive(id: EntityId): boolean {
    const index = entityIndex(id);
    if (index >= this.next) return false;
    if (this.alive[index] !== true) return false;
    return this.generations[index] === entityGeneration(id);
  }

  /**
   * Destroy an entity, bumping its slot's generation so every outstanding reference stops
   * resolving. Destroying an already-dead entity is a no-op rather than an error --
   * cleanup systems shouldn't have to coordinate with each other about who got there first.
   */
  destroy(id: EntityId): boolean {
    if (!this.isAlive(id)) return false;
    const index = entityIndex(id);
    this.generations[index] = ((this.generations[index] as number) + 1) & GENERATION_MASK;
    this.alive[index] = false;
    this.free.push(index);
    return true;
  }

  /** Live entities, ascending by slot. See components.ts on why order is never left to chance. */
  all(): EntityId[] {
    const out: EntityId[] = [];
    for (let index = 0; index < this.next; index++) {
      if (this.alive[index] !== true) continue;
      out.push(pack(index, this.generations[index] as number));
    }
    return out;
  }

  save(): EntityStoreSave {
    return {
      generations: [...this.generations],
      alive: [...this.alive],
      free: [...this.free],
      next: this.next,
    };
  }

  restore(saved: EntityStoreSave): void {
    this.generations = [...saved.generations];
    this.alive = [...saved.alive];
    this.free = [...saved.free];
    this.next = saved.next;
  }
}
