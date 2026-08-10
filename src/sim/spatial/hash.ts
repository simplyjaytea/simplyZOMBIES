// The uniform spatial index: "what is near this point?"
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
//
// **A dense grid with a counting sort, not a map of buckets.** The first draft was the
// literal reading of "hash" -- a `Map` from packed cell coordinate to an array of occupants.
// It measured at 344 ns per body per tick, which nearly doubled the cost of a tick for an
// index nothing had queried yet. The reason is visible the moment you count: 2,000 bodies in
// a 256 m district at this cell size land in about 1,900 distinct cells, so the structure was
// one tiny array per body -- a `Map` probe, a growth check and three pushes into three
// separate heap objects, all to store a single entry. The same information as three flat
// typed arrays plus a prefix-sum table costs a fill, two linear walks, and no allocation at
// all.

import { Position } from "../kernel/components";
import { entityIndex, type EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import { TILE_METRES, type TileMap } from "../map/tilemap";

/**
 * Cell width in metres.
 *
 * The rule for a uniform grid is that the cell should be a little larger than the typical
 * query radius: smaller and one query touches many cells, larger and every query drags in
 * bodies it will only reject. Two metres is just above the longest melee reach a weapon has,
 * so a swing touches four cells at worst and usually fewer.
 *
 * It is a single constant rather than a per-world parameter on purpose. A grid tuned per
 * caller is a grid with two answers to "which cell is this in", and the second consumer to
 * arrive is the one that finds out.
 */
export const CELL_METRES = 2;

/**
 * Every entity with a `Position`, bucketed by cell.
 *
 * **Derived state, and deliberately not in the snapshot** -- the same call the visibility
 * index makes, for the same reason. It is a pure function of positions, which the snapshot
 * already holds, so storing it would create a second copy of a fact and a way for a save to
 * disagree with itself. It is rebuilt whole every tick, after movement has integrated and
 * before anything asks it a question.
 */
export class SpatialHash {
  readonly cols: number;
  readonly rows: number;

  /**
   * Where each cell's run begins in {@link ids}, with one extra entry on the end so cell `i`
   * is exactly `[starts[i], starts[i + 1])` and the last cell needs no special case.
   */
  private readonly starts: Int32Array;
  /** Working copy of {@link starts}, advanced as the second pass places each body. */
  private readonly cursor: Int32Array;

  private ids: Uint32Array;
  private xs: Float64Array;
  private ys: Float64Array;

  private indexed = 0;

  private constructor(cols: number, rows: number) {
    this.cols = Math.max(1, cols);
    this.rows = Math.max(1, rows);
    const cells = this.cols * this.rows;
    this.starts = new Int32Array(cells + 1);
    this.cursor = new Int32Array(cells);
    // Grown on demand by `rebuild`. Starting at zero keeps an empty world free.
    this.ids = new Uint32Array(0);
    this.xs = new Float64Array(0);
    this.ys = new Float64Array(0);
  }

  /** Sized to a district, the way the attention field is. */
  static forMap(map: TileMap): SpatialHash {
    return new SpatialHash(
      Math.ceil((map.w * TILE_METRES) / CELL_METRES),
      Math.ceil((map.h * TILE_METRES) / CELL_METRES),
    );
  }

  /** Sized to a plain extent in metres. For tests and for callers without a map. */
  static forExtent(widthMetres: number, heightMetres: number): SpatialHash {
    return new SpatialHash(
      Math.ceil(widthMetres / CELL_METRES),
      Math.ceil(heightMetres / CELL_METRES),
    );
  }

  /**
   * A single-cell index, so a world built before anything sized one still has a usable
   * kernel rather than a null to check. Every query degrades to a linear scan, which is
   * correct -- the distance test is exact either way -- and only ever holds for a world that
   * was booted without a map.
   */
  static empty(): SpatialHash {
    return new SpatialHash(1, 1);
  }

  /**
   * Cell index for a point, clamped to the grid.
   *
   * Clamping rather than rejecting is safe **because the distance test is exact**: a body
   * outside the district lands in an edge cell, and a query reaching that cell still has to
   * pass the real distance check before the body is returned. Queries clamp identically, so
   * the two agree. The alternative -- an overflow list every query has to scan -- would cost
   * every caller something to handle a case the district generator cannot produce.
   */
  private cellOf(x: number, y: number): number {
    const cx = this.clampCol(Math.floor(x / CELL_METRES));
    const cy = this.clampRow(Math.floor(y / CELL_METRES));
    return cy * this.cols + cx;
  }

  private clampCol(cx: number): number {
    return cx < 0 ? 0 : cx > this.cols - 1 ? this.cols - 1 : cx;
  }

  private clampRow(cy: number): number {
    return cy < 0 ? 0 : cy > this.rows - 1 ? this.rows - 1 : cy;
  }

  /**
   * Rebuild from scratch, as a counting sort.
   *
   * Whole-rebuild rather than incremental maintenance, and that is a considered choice rather
   * than a stub. Incremental means every writer of `Position` has to remember to tell the
   * index, which is exactly the kind of obligation that gets forgotten in the one code path
   * nobody tested; the bug it produces is a swing that passes through a zombie.
   *
   * Two linear walks of the component store rather than one walk into a scratch buffer: the
   * walk itself measured at 23 ns per body, so doing it twice is cheaper than allocating and
   * maintaining a parallel copy of every position in the world.
   *
   * The fixed cost is the prefix sum, which is proportional to the *grid* rather than to the
   * crowd -- about 16k cells for a 256 m district, or 20 microseconds a tick. That is the
   * price of the structure being allocation-free, and it is the right trade at district
   * scale. If the world ever streams chunks large enough for it to matter, the grid becomes
   * per-chunk rather than per-world, which is the same change streaming needs anyway.
   */
  rebuild(world: World): void {
    const cells = this.cols * this.rows;
    const starts = this.starts;
    starts.fill(0);

    // Pass one: how many bodies land in each cell. Counted one slot to the right, so the
    // prefix sum below turns the array into offsets in place.
    let indexed = 0;
    world.components.forEachWith(Position, (_entity, position) => {
      const slot = this.cellOf(position.x, position.y) + 1;
      starts[slot] = (starts[slot] as number) + 1;
      indexed++;
    });
    this.indexed = indexed;

    if (indexed > this.ids.length) {
      // Growth is amortised: doubling, so a district that fills up reallocates a handful of
      // times across a run rather than on every spawn.
      const capacity = Math.max(64, 1 << (32 - Math.clz32(indexed - 1)));
      this.ids = new Uint32Array(capacity);
      this.xs = new Float64Array(capacity);
      this.ys = new Float64Array(capacity);
    }

    for (let i = 0; i < cells; i++)
      starts[i + 1] = (starts[i + 1] as number) + (starts[i] as number);
    this.cursor.set(starts.subarray(0, cells));

    // Pass two: place each body in its cell's run. Unordered iteration is permitted here
    // only because `queryRadius` sorts every result before returning it -- see the note
    // there, and the contract on `ComponentStore.forEachWith`.
    const { cursor, ids, xs, ys } = this;
    world.components.forEachWith(Position, (entity, position) => {
      const cell = this.cellOf(position.x, position.y);
      const at = cursor[cell] as number;
      cursor[cell] = at + 1;
      ids[at] = entity;
      xs[at] = position.x;
      ys[at] = position.y;
    });
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

    // Both ends clamp into the grid, and clamping the *lower* bound up is as load-bearing as
    // clamping the upper bound down. A body outside the district is stored in an edge cell by
    // `cellOf`; a query that only clamped its upper bound would compute an empty cell range
    // for a point outside the grid and never look in that edge cell, so the body would be
    // unfindable from the very place it sits. The two have to agree, and this is them
    // agreeing. Exactness is still the distance test's job, not the cell range's.
    const minX = this.clampCol(Math.floor((x - radiusMetres) / CELL_METRES));
    const maxX = this.clampCol(Math.floor((x + radiusMetres) / CELL_METRES));
    const minY = this.clampRow(Math.floor((y - radiusMetres) / CELL_METRES));
    const maxY = this.clampRow(Math.floor((y + radiusMetres) / CELL_METRES));
    const limit = radiusMetres * radiusMetres;
    const { starts, ids, xs, ys } = this;

    for (let cy = minY; cy <= maxY; cy++) {
      const row = cy * this.cols;
      for (let cx = minX; cx <= maxX; cx++) {
        const cell = row + cx;
        const end = starts[cell + 1] as number;
        for (let i = starts[cell] as number; i < end; i++) {
          const dx = (xs[i] as number) - x;
          const dy = (ys[i] as number) - y;
          if (dx * dx + dy * dy <= limit) out.push(ids[i] as EntityId);
        }
      }
    }

    // Ordering is a determinism requirement, not a convenience -- the same rule
    // `ComponentStore.query` documents at length. A run is in whatever order the component
    // store was walked in, and a query spanning four cells concatenates four such runs, so a
    // caller that broke a tie by "first found" would depend on insertion history. Sorting by
    // slot index makes the answer a function of state alone.
    out.sort((a, b) => entityIndex(a) - entityIndex(b));
    return out;
  }

  /** How many entities the last rebuild indexed. For tests and the HUD, not for logic. */
  get size(): number {
    return this.indexed;
  }

  /** Cells in the grid. Diagnostics only. */
  get cellCount(): number {
    return this.cols * this.rows;
  }
}
