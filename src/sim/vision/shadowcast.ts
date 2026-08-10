// Recursive shadowcasting: the geometry half of the visibility primitive.
//
// docs/28-visibility-and-sightlines.md is the specification, and the reason this is one
// function rather than three is the first thing it says: the light channel, the renderer and
// the multiplayer view filter all ask the same question, and "answered three times, it is
// three subtly different bugs, and one of them is a cheat."
//
// Two properties matter more than the algorithm choice, and both are structural here:
//
//   **Symmetry.** If A can see B, B can see A. The variant implemented is Albert Ford's
//   symmetric shadowcasting: a floor tile is revealed only when its *centre* lies inside the
//   scanned wedge, which is the condition that makes the relation symmetric. The cheaper
//   permissive variants reveal a tile when any part of it is touched, and they are
//   asymmetric -- defensible in a game where the other party is a monster, indefensible in
//   one where it might be [a person with a rifle](../../../docs/27-multiplayer.md).
//
//   **Determinism.** Every comparison below is integer. Slopes are kept as rational
//   `{ n, d }` pairs and compared by cross-multiplication rather than divided into floats,
//   so there is no accumulation to drift between two runs of the same seed and no platform
//   left free to round the boundary its own way. Ranges are compared squared for the same
//   reason. docs/19-architecture.md#determinism asks for this; here it costs nothing, so
//   there is no reason to spend a float.
//
// What is *not* here: arcs, facing, or any notion of who is looking. This answers "is there
// an unbroken sightline between these two tiles", and nothing else -- an observer's focal and
// peripheral cones are applied by the caller (see visibility.ts), because they are a property
// of the eye and not of the geometry. Keeping them out is also what keeps the symmetry claim
// true: two survivors back to back have a sightline and are not looking at each other, and
// those are different facts.

import { blocksSight, Eye, type TileMap } from "../map/tilemap";

/**
 * A slope, as a rational number. `d` is always positive, so cross-multiplied comparisons
 * never have to think about which way the inequality faces.
 */
type Slope = { readonly n: number; readonly d: number };

const START: Slope = { n: -1, d: 1 };
const END: Slope = { n: 1, d: 1 };

/** Integer floor division. `Math.floor(a / b)` without the float in the middle. */
function floorDiv(a: number, b: number): number {
  const q = Math.trunc(a / b);
  return q * b > a ? q - 1 : q;
}

/** Integer ceiling division. */
function ceilDiv(a: number, b: number): number {
  const q = Math.trunc(a / b);
  return q * b < a ? q + 1 : q;
}

/**
 * The set of tiles one observer can see, as a square window centred on it.
 *
 * A dense `Uint8Array` rather than a `Set` of packed coordinates: at the ranges involved
 * (a 48 m daylight view is 9,409 cells) the array is 9 KB and answers a query with one
 * index, while the set costs a hash per lookup and the renderer does one lookup per entity
 * per frame. It is also reusable in place, which is what keeps a recompute from allocating.
 */
export class VisibleTiles {
  /** Observer tile. */
  originX = 0;
  originY = 0;
  /** Radius in tiles. The window is `2 * range + 1` on a side. */
  range = 0;
  /** Row stride of {@link cells}. */
  size = 0;
  /** 1 where there is a sightline from the origin, 0 elsewhere. */
  cells: Uint8Array = new Uint8Array(0);
  /** Tiles revealed by the last computation, for the benchmark and the HUD. */
  count = 0;

  /** Resize for a new range, reusing the buffer when the range has not changed. */
  reset(originX: number, originY: number, range: number): void {
    const size = range * 2 + 1;
    if (this.size !== size) {
      this.size = size;
      this.cells = new Uint8Array(size * size);
    } else {
      this.cells.fill(0);
    }
    this.originX = originX;
    this.originY = originY;
    this.range = range;
    this.count = 0;
  }

  /** Is there a sightline from the origin to this tile? Outside the window is always no. */
  has(tx: number, ty: number): boolean {
    const dx = tx - this.originX + this.range;
    const dy = ty - this.originY + this.range;
    if (dx < 0 || dy < 0 || dx >= this.size || dy >= this.size) return false;
    return this.cells[dy * this.size + dx] === 1;
  }

  /** @internal */
  mark(tx: number, ty: number): void {
    const dx = tx - this.originX + this.range;
    const dy = ty - this.originY + this.range;
    if (dx < 0 || dy < 0 || dx >= this.size || dy >= this.size) return;
    const i = dy * this.size + dx;
    if (this.cells[i] === 1) return;
    this.cells[i] = 1;
    this.count++;
  }
}

/** Which way a quadrant scan walks. Depth runs away from the observer, column across it. */
const enum Quadrant {
  North = 0,
  East = 1,
  South = 2,
  West = 3,
}

/**
 * Compute every tile with a sightline from (originX, originY), out to `range` tiles.
 *
 * The observer's own tile always counts, walls included -- a survivor standing in a doorway
 * can see the doorway. Results are written into `out`, which is reused across recomputes.
 */
export function shadowcast(
  map: TileMap,
  originX: number,
  originY: number,
  range: number,
  out: VisibleTiles,
  eye: Eye = Eye.Standing,
): VisibleTiles {
  out.reset(originX, originY, range);
  out.mark(originX, originY);

  const rangeSquared = range * range;

  // A tile's world coordinates from its (depth, column) in a quadrant. Four cases here is
  // what keeps the scan below written once instead of four times with the signs shuffled,
  // which is where the classic implementations of this grow their asymmetries.
  const tileX = (quadrant: Quadrant, depth: number, column: number): number =>
    quadrant === Quadrant.North || quadrant === Quadrant.South
      ? originX + column
      : quadrant === Quadrant.East
        ? originX + depth
        : originX - depth;
  const tileY = (quadrant: Quadrant, depth: number, column: number): number =>
    quadrant === Quadrant.East || quadrant === Quadrant.West
      ? originY + column
      : quadrant === Quadrant.South
        ? originY + depth
        : originY - depth;

  for (let q = Quadrant.North; q <= Quadrant.West; q++) {
    const quadrant = q as Quadrant;

    // The scan is a stack rather than recursion. Depth is bounded by `range`, so recursion
    // would not overflow -- but a shadowcast runs inside the tick and an explicit stack is
    // one fewer thing between a profile and what it measures.
    const stack: { depth: number; start: Slope; end: Slope }[] = [
      { depth: 1, start: START, end: END },
    ];

    while (stack.length > 0) {
      const frame = stack.pop() as { depth: number; start: Slope; end: Slope };
      const depth = frame.depth;
      if (depth > range) continue;

      let start = frame.start;
      const end = frame.end;

      // The columns this wedge covers at this depth. Ties round *outward* at the start and
      // *inward* at the end, which is what makes a wedge and its mirror image agree about
      // the tile on the boundary between them.
      const minColumn = floorDiv(2 * depth * start.n + start.d, 2 * start.d);
      const maxColumn = ceilDiv(2 * depth * end.n - end.d, 2 * end.d);

      let previousBlocking: boolean | null = null;

      for (let column = minColumn; column <= maxColumn; column++) {
        const tx = tileX(quadrant, depth, column);
        const ty = tileY(quadrant, depth, column);
        const blocking = blocksSight(map, tx, ty, eye);

        // A blocking tile is revealed whenever the scan reaches it -- you can see the wall
        // that stops you seeing past it. A floor tile is revealed only when its centre is
        // inside the wedge, and *that* is the symmetry condition: the test is the same one
        // the mirrored scan from the other end applies to this tile.
        const centreInside = column * start.d >= depth * start.n && column * end.d <= depth * end.n;
        if (blocking || centreInside) {
          if (depth * depth + column * column <= rangeSquared) out.mark(tx, ty);
        }

        if (previousBlocking === true && !blocking) {
          // Leaving a wall: the wedge resumes from this tile's near edge.
          start = { n: 2 * column - 1, d: 2 * depth };
        }
        if (previousBlocking === false && blocking) {
          // Entering a wall: everything the wedge held up to here continues one row deeper.
          stack.push({ depth: depth + 1, start, end: { n: 2 * column - 1, d: 2 * depth } });
        }
        previousBlocking = blocking;
      }

      // The row ended in open ground, so the remainder of the wedge continues.
      if (previousBlocking === false) stack.push({ depth: depth + 1, start, end });
    }
  }

  return out;
}
