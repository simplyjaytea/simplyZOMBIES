// The one thing this spike exists to test: a noise field the horde walks up.
//
// Single channel. Light and scent are deliberately absent — scent is the expensive
// continuous one, and it is only worth paying for if noise reads as fun first.

import { TILE, isWall, type TileMap } from "./map";

/** Tiles per field cell. The field is deliberately coarser than the tile grid. */
export const FIELD_SCALE = 2;

/** Below this, a cell is silent. Also the zombie hearing floor. */
export const EPSILON = 1.5;

/** Attenuation per field cell of travel. */
const FALLOFF = 4;

/** Extra attenuation for propagating through a wall cell. */
const WALL_PENALTY = 26;

/** Multiplicative decay per tick. At 20Hz this is a ~3s half-life. */
const DECAY = 0.988;

export class NoiseField {
  readonly w: number;
  readonly h: number;
  readonly values: Float32Array;
  private readonly solid: Uint8Array;

  // Reused scratch so emit() allocates nothing per call.
  private readonly open: Int32Array;
  private readonly staged: Float32Array;
  private readonly dirty: Int32Array;

  /** Field cells touched by the last emit — the cost measure that matters. */
  lastEmitCells = 0;

  constructor(map: TileMap) {
    this.w = Math.ceil(map.w / FIELD_SCALE);
    this.h = Math.ceil(map.h / FIELD_SCALE);
    const n = this.w * this.h;
    this.values = new Float32Array(n);
    this.staged = new Float32Array(n);
    this.solid = new Uint8Array(n);
    this.open = new Int32Array(n);
    this.dirty = new Int32Array(n);

    // A field cell is solid if every tile under it is a wall.
    for (let fy = 0; fy < this.h; fy++) {
      for (let fx = 0; fx < this.w; fx++) {
        let all = true;
        for (let dy = 0; dy < FIELD_SCALE && all; dy++) {
          for (let dx = 0; dx < FIELD_SCALE; dx++) {
            if (!isWall(map, fx * FIELD_SCALE + dx, fy * FIELD_SCALE + dy)) { all = false; break; }
          }
        }
        this.solid[fy * this.w + fx] = all ? 1 : 0;
      }
    }
  }

  idxAtWorld(wx: number, wy: number): number {
    const fx = Math.min(this.w - 1, Math.max(0, Math.floor(wx / (TILE * FIELD_SCALE))));
    const fy = Math.min(this.h - 1, Math.max(0, Math.floor(wy / (TILE * FIELD_SCALE))));
    return fy * this.w + fx;
  }

  valueAtWorld(wx: number, wy: number): number {
    return this.values[this.idxAtWorld(wx, wy)];
  }

  /**
   * Propagate a noise event outward from a world position.
   *
   * Relaxation over field cells (SPFA-style): a cell's value is the source magnitude
   * minus accumulated travel cost, walls costing extra. Bounded because propagation
   * stops as soon as the remaining value falls under EPSILON, so a quiet footstep is
   * nearly free and only a gunshot pays for a wide flood.
   */
  emit(wx: number, wy: number, magnitude: number): void {
    this.lastEmitCells = 0;
    if (magnitude < EPSILON) return;

    const { w, h, values, staged, solid, open, dirty } = this;
    const start = this.idxAtWorld(wx, wy);

    let head = 0;
    let tail = 0;
    let nDirty = 0;

    staged[start] = magnitude;
    dirty[nDirty++] = start;
    open[tail++] = start;

    while (head < tail) {
      const cur = open[head++];
      const v = staged[cur];
      if (v < EPSILON) continue;

      const cx = cur % w;
      const cy = (cur - cx) / w;

      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = cx + dx;
          const ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;

          const ni = ny * w + nx;
          const diag = dx !== 0 && dy !== 0;
          let cost = diag ? FALLOFF * 1.414 : FALLOFF;
          if (solid[ni]) cost += WALL_PENALTY;

          const nv = v - cost;
          if (nv < EPSILON) continue;
          if (nv <= staged[ni]) continue;

          if (staged[ni] === 0) dirty[nDirty++] = ni;
          staged[ni] = nv;
          if (tail < open.length) open[tail++] = ni;
        }
      }
    }

    // Commit: noise takes the loudest contribution rather than summing, so
    // repeated emitters can't run the field away to infinity.
    for (let i = 0; i < nDirty; i++) {
      const ci = dirty[i];
      if (staged[ci] > values[ci]) values[ci] = staged[ci];
      staged[ci] = 0;
    }
    this.lastEmitCells = nDirty;
  }

  decay(): void {
    const v = this.values;
    for (let i = 0; i < v.length; i++) {
      const x = v[i];
      if (x === 0) continue;
      const d = x * DECAY;
      v[i] = d < EPSILON ? 0 : d;
    }
  }

  /** Loudest 8-neighbour of a world position, if it beats where we already are. */
  uphill(wx: number, wy: number): { dx: number; dy: number; value: number } | null {
    const { w, h, values, solid } = this;
    const here = this.idxAtWorld(wx, wy);
    const cx = here % w;
    const cy = (here - cx) / w;

    let best = values[here];
    let bdx = 0;
    let bdy = 0;

    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        if (dx === 0 && dy === 0) continue;
        const nx = cx + dx;
        const ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const ni = ny * w + nx;
        if (solid[ni]) continue;
        if (values[ni] > best) { best = values[ni]; bdx = dx; bdy = dy; }
      }
    }

    if (bdx === 0 && bdy === 0) return null;
    return { dx: bdx, dy: bdy, value: best };
  }

  /** True if this position is loud enough to be worth investigating. */
  audible(wx: number, wy: number): boolean {
    return this.values[this.idxAtWorld(wx, wy)] >= EPSILON;
  }

  maxValue(): number {
    let m = 0;
    for (let i = 0; i < this.values.length; i++) if (this.values[i] > m) m = this.values[i];
    return m;
  }

  activeCells(): number {
    let n = 0;
    for (let i = 0; i < this.values.length; i++) if (this.values[i] > 0) n++;
    return n;
  }
}
