// The uniform spatial hash: "what is near this point?"
//
// docs/22-performance.md#spatial-partitioning names it, names the shape -- "uniform hashing
// beats a quadtree here because entity distribution is clustered and dynamic, and the
// constant factors are better at these counts" -- and lists the four consumers: neighbour
// queries for combat, attention emitter/receiver lookups, tier assignment, and render
// culling.
//
// It was deliberately not built until now. TODO.md's spatial section says why: gradient
// ascent needs no neighbour queries, render culling already had one, and "building it before
// combat needs it would be optimising an absence." The melee swing is the first thing that
// genuinely asks the question -- once per swing, against whatever is inside a weapon's reach.
//
// Kernel rather than module-owned, beside the attention field and the visibility index, for
// the reason those two are: several systems that do not own each other will read it, and a
// module that can be switched off must not be what makes neighbour queries work.

import { Position } from "../kernel/components";
import { entityIndex, type EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";

/**
 * Cell width in metres.
 *
 * The rule for a uniform hash is that the cell should be a little larger than the typical
 * query radius: smaller and one query touches many cells, larger and every query drags in
 * bodies it will only reject. Two metres is just above the longest melee reach a weapon has,
 * so a swing touches four cells at worst and usually fewer.
 *
 * It is a single constant rather than a per-world parameter on purpose. A hash tuned per
 * caller is a hash with two answers to "which cell is this in", and the second consumer to
 * arrive is the one that finds out.
 */
export const CELL_METRES = 2;

/**
 * Cell coordinates are packed into one number so the map can be keyed by primitive rather
 * than by string. The offset lets a coordinate go negative -- positions are inside the map
 * today, but a hash that quietly corrupts on a negative coordinate is a trap for whoever
 * first places something outside it.
 */
const COORD_OFFSET = 1 << 15;
const COORD_SPAN = 1 << 16;

function cellKey(cx: number, cy: number): number {
  // Multiplication rather than bit-shifting: the packed value exceeds 2^31 for the upper
  // half of the range, and `<<` would wrap it into a negative number that collides with a
  // legitimate cell.
  return (cx + COORD_OFFSET) * COORD_SPAN + (cy + COORD_OFFSET);
}

/**
 * Every entity with a `Position`, indexed by cell.
 *
 * **Derived state, and deliberately not in the snapshot** -- the same call the visibility
 * index makes, for the same reason. It is a pure function of positions, which the snapshot
 * already holds, so storing it would create a second copy of a fact and a way for a save to
 * disagree with itself. It is rebuilt whole every tick, after movement has integrated and
 * before anything asks it a question.
 */
/**
 * One cell's contents, as parallel arrays.
 *
 * Positions are copied in at rebuild rather than looked up per candidate. The query then
 * needs nothing but this bucket -- no component store, no world -- which is what lets the
 * exact distance test happen here instead of being left to every caller to remember.
 */
type Bucket = {
  ids: EntityId[];
  xs: number[];
  ys: number[];
};

export class SpatialHash {
  private readonly cells = new Map<number, Bucket>();

  /**
   * Entities indexed as of the last rebuild. Not the same as the number of live entities:
   * anything without a `Position` is not in here, and has no business being.
   */
  private indexed = 0;

  /**
   * Rebuild from scratch.
   *
   * Whole-rebuild rather than incremental maintenance, and that is a considered choice
   * rather than a stub. Incremental means every writer of `Position` has to remember to tell
   * the hash, which is exactly the kind of obligation that gets forgotten in the one code
   * path nobody tested; the bug it produces is a swing that passes through a zombie. At the
   * ~3,000 entities docs/22 targets a full rebuild is a linear pass over a component store
   * that is already being iterated several times a tick.
   *
   * Cell arrays are emptied rather than dropped, so a settled world stops allocating
   * entirely. The number of cells is bounded by the map area, not by entity churn.
   */
  rebuild(world: World): void {
    for (const bucket of this.cells.values()) {
      bucket.ids.length = 0;
      bucket.xs.length = 0;
      bucket.ys.length = 0;
    }

    let indexed = 0;
    // `query` returns ascending entity order, which makes every bucket sorted by
    // construction -- see the note in `queryRadius` about why that matters.
    for (const entity of world.components.query(Position)) {
      const position = world.components.getOrThrow(entity, Position);
      const key = cellKey(
        Math.floor(position.x / CELL_METRES),
        Math.floor(position.y / CELL_METRES),
      );
      const bucket = this.cells.get(key);
      if (bucket === undefined) {
        this.cells.set(key, { ids: [entity], xs: [position.x], ys: [position.y] });
      } else {
        bucket.ids.push(entity);
        bucket.xs.push(position.x);
        bucket.ys.push(position.y);
      }
      indexed++;
    }
    this.indexed = indexed;
  }

  /**
   * Entities whose position is within `radiusMetres` of the point, **inclusive of the
   * boundary**, in ascending entity order.
   *
   * The distance test is exact rather than cell-approximate. A caller handed the cell
   * candidates would have to re-filter them, and the second caller to forget is the one that
   * ships a weapon with a square reach.
   *
   * `out` is supplied by the caller and reused, because this runs once per swing and
   * allocating a result array per call is how a combat system acquires a GC spike. It is
   * cleared on entry and returned for convenience.
   */
  queryRadius(x: number, y: number, radiusMetres: number, out: EntityId[] = []): EntityId[] {
    out.length = 0;
    if (!(radiusMetres > 0)) return out;

    const minX = Math.floor((x - radiusMetres) / CELL_METRES);
    const maxX = Math.floor((x + radiusMetres) / CELL_METRES);
    const minY = Math.floor((y - radiusMetres) / CELL_METRES);
    const maxY = Math.floor((y + radiusMetres) / CELL_METRES);
    const limit = radiusMetres * radiusMetres;

    for (let cx = minX; cx <= maxX; cx++) {
      for (let cy = minY; cy <= maxY; cy++) {
        const bucket = this.cells.get(cellKey(cx, cy));
        if (bucket === undefined) continue;
        for (let i = 0; i < bucket.ids.length; i++) {
          const dx = (bucket.xs[i] as number) - x;
          const dy = (bucket.ys[i] as number) - y;
          if (dx * dx + dy * dy <= limit) out.push(bucket.ids[i] as EntityId);
        }
      }
    }

    // Ordering is a determinism requirement, not a convenience -- the same rule
    // `ComponentStore.query` documents at length. Each bucket is sorted, but a query that
    // spans four of them interleaves them, and a caller that breaks a tie by "first found"
    // would then depend on cell geometry. Sorting by slot index makes the answer a function
    // of state alone.
    out.sort((a, b) => entityIndex(a) - entityIndex(b));
    return out;
  }

  /** How many entities the last rebuild indexed. For tests and the HUD, not for logic. */
  get size(): number {
    return this.indexed;
  }

  /** Cells currently held, including emptied ones. Bounded by map area. Diagnostics only. */
  get cellCount(): number {
    return this.cells.size;
  }
}
