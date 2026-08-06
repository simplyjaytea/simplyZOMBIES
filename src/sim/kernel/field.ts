// The attention field.
//
// docs/03-attention.md is the specifying document and calls this "the kernel mechanic":
// zombies don't hunt, they drift toward stimulus, and everything the player does to live
// better writes into this field. It lives in the kernel rather than in a module because
// docs/19-architecture.md#one-spine-many-optional-limbs lists it alongside the tick loop and
// the entity store -- a module may be switched off, and this may not.
//
// Three channels, kept separate because each propagates, decays and is blocked differently
// (docs/03#three-channels). The temptation to merge them into one "threat" scalar is the
// thing that would collapse the design into a tower-defense heatmap.

import { isWall, TILE_METRES, type TileMap } from "../map/tilemap";

// ---- calibration -----------------------------------------------------------
//
// Every constant here is from docs/03-attention.md#scale-and-calibration, which exists
// because the spike picked an attenuation constant arbitrarily and one shout flooded an
// entire district. The magnitudes in docs/03's emitter tables were never wrong; the *unit*
// was never written down. Changing any of these changes what six documents mean.

/** Metres per field cell. The field is deliberately coarser than the tile grid. */
export const FIELD_CELL_METRES = 4;

/**
 * Noise lost per metre of open ground, linear.
 *
 * "Magnitude is reach": a source carries `magnitude / 0.7` metres before falling under the
 * audible floor. An unsuppressed firearm at 180 reaches 257 m, which is one 256 m district,
 * exactly -- that correspondence is the point, and it is why the falloff stays linear
 * rather than becoming an inverse square.
 */
export const ATTENUATION_PER_METRE = 0.7;

/**
 * Extra travel cost, in metres-equivalent, for crossing a fully solid field cell.
 *
 * Being indoors is worth real distance: a gunshot carrying 257 m outdoors reaches ~180 m
 * through one wall. Applied in proportion to how much of the cell is wall, so a cell that
 * is half building costs half of it -- the alternative is a hard threshold that makes noise
 * propagation jump discontinuously as a building's footprint shifts by one tile.
 */
export const WALL_EXTRA_METRES = 18;

/** Below this, a stimulus is inaudible and the cell is cleared. Keeps the live set small. */
export const AUDIBLE_FLOOR = 0.5;

/** Noise decays multiplicatively with a ~3 s half-life (docs/03). */
export const NOISE_HALF_LIFE_SECONDS = 3;

/**
 * Scent diffuses at a few Hz rather than every tick.
 *
 * It is the continuous channel, and the one docs/23-roadmap.md's risk 5 is actually about.
 * Running it at the full tick rate would be the most expensive thing in the simulation for
 * no gain: it moves over hours.
 */
export const SCENT_DIFFUSE_EVERY_TICKS = 4;

/** Fraction of a cell's scent that spreads to its neighbours per diffusion step. */
export const SCENT_SPREAD = 0.12;

/**
 * Scent half-life: **two hours**, expressed as time rather than as a per-step rate.
 *
 * docs/03 puts noise at "seconds to a minute" and scent at "hours", and that gap is the
 * whole reason the channels are not interchangeable -- it is what lets a place you made a
 * mistake stay a bad neighbourhood, and what makes corpse piles a problem you cannot
 * outrun by being quiet for a minute. A per-step constant hides that: an innocent-looking
 * 0.0004 per step is 11% a minute, which is a noise channel wearing scent's name.
 */
export const SCENT_HALF_LIFE_SECONDS = 2 * 60 * 60;

export const CHANNELS = ["noise", "light", "scent"] as const;
export type Channel = (typeof CHANNELS)[number];

/** Sorted [cellIndex, value] pairs per channel. Only non-zero cells are carried. */
export type FieldSave = Record<Channel, [number, number][]>;

/** A global wind vector, in cells per diffusion step (docs/16-weather.md supplies it later). */
export type Wind = { readonly dx: number; readonly dy: number };

export const STILL_AIR: Wind = { dx: 0, dy: 0 };

// ---- the field -------------------------------------------------------------

export class AttentionField {
  /** Grid size in cells. */
  readonly w: number;
  readonly h: number;

  private readonly noise: Float32Array;
  private readonly light: Float32Array;
  private readonly scent: Float32Array;

  /**
   * Per-cell extra travel cost from walls, in metres-equivalent. Derived from the map,
   * which is itself derived from the seed -- so this is not in the save.
   */
  private readonly obstruction: Float32Array;

  /** Scratch buffers, reused so propagation doesn't allocate per event. */
  private readonly cost: Float32Array;
  private readonly visited: Int32Array;
  /** Bumped per flood so `visited` doesn't need clearing between events. */
  private visitStamp = 0;

  constructor(readonly map: TileMap) {
    this.w = Math.ceil((map.w * TILE_METRES) / FIELD_CELL_METRES);
    this.h = Math.ceil((map.h * TILE_METRES) / FIELD_CELL_METRES);

    const cells = this.w * this.h;
    this.noise = new Float32Array(cells);
    this.light = new Float32Array(cells);
    this.scent = new Float32Array(cells);
    this.obstruction = new Float32Array(cells);
    this.cost = new Float32Array(cells);
    this.visited = new Int32Array(cells);

    this.buildObstruction();
  }

  /** How much of each field cell is wall, as an extra travel cost in metres. */
  private buildObstruction(): void {
    const tilesPerCell = FIELD_CELL_METRES / TILE_METRES;
    for (let cy = 0; cy < this.h; cy++) {
      for (let cx = 0; cx < this.w; cx++) {
        let walls = 0;
        let total = 0;
        for (let ty = cy * tilesPerCell; ty < (cy + 1) * tilesPerCell; ty++) {
          for (let tx = cx * tilesPerCell; tx < (cx + 1) * tilesPerCell; tx++) {
            if (tx >= this.map.w || ty >= this.map.h) continue;
            total++;
            if (isWall(this.map, tx, ty)) walls++;
          }
        }
        this.obstruction[cy * this.w + cx] =
          total === 0 ? WALL_EXTRA_METRES : (walls / total) * WALL_EXTRA_METRES;
      }
    }
  }

  private layer(channel: Channel): Float32Array {
    switch (channel) {
      case "noise":
        return this.noise;
      case "light":
        return this.light;
      default:
        return this.scent;
    }
  }

  get cellCount(): number {
    return this.w * this.h;
  }

  /** Field-cell coordinates for a world position in metres. */
  cellAt(x: number, y: number): number {
    const cx = Math.min(this.w - 1, Math.max(0, Math.floor(x / FIELD_CELL_METRES)));
    const cy = Math.min(this.h - 1, Math.max(0, Math.floor(y / FIELD_CELL_METRES)));
    return cy * this.w + cx;
  }

  /** Read a channel at a world position. */
  sample(channel: Channel, x: number, y: number): number {
    return this.layer(channel)[this.cellAt(x, y)] as number;
  }

  /** Read a channel at a cell index. */
  at(channel: Channel, cell: number): number {
    if (cell < 0 || cell >= this.cellCount) return 0;
    return this.layer(channel)[cell] as number;
  }

  /** Cells currently carrying anything, per channel. The spike's "6 live cells when quiet". */
  liveCells(channel: Channel): number {
    const layer = this.layer(channel);
    let n = 0;
    for (let i = 0; i < layer.length; i++) if (layer[i] !== 0) n++;
    return n;
  }

  /**
   * Add to a channel at a position without propagating.
   *
   * Scent uses this: it accumulates where it is emitted and spreads by diffusion, unlike
   * noise which resolves its whole reach in the instant it happens.
   */
  deposit(channel: Channel, x: number, y: number, magnitude: number): void {
    if (magnitude <= 0) return;
    const layer = this.layer(channel);
    const cell = this.cellAt(x, y);
    layer[cell] = (layer[cell] as number) + magnitude;
  }

  /**
   * Resolve a noise event across the field: an attenuated flood-fill, bounded by reach.
   *
   * A flood and not a ray. docs/03: noise "routes around obstructions", so in a built-up
   * district the streets are noise highways and a building casts a much smaller shadow than
   * its footprint suggests. Modelling this as line-of-sight would make buildings into
   * insulation, which is the opposite of what the design says they are -- they are detours.
   *
   * Uniform-cost search rather than a simple radius, because the cost of entering a cell
   * depends on how much of it is wall. Ties break on cell index so the result is a function
   * of state alone.
   */
  emitNoise(x: number, y: number, magnitude: number): void {
    if (magnitude <= AUDIBLE_FLOOR) return;

    const maxCost = (magnitude - AUDIBLE_FLOOR) / ATTENUATION_PER_METRE;
    const start = this.cellAt(x, y);
    const stamp = ++this.visitStamp;

    const heap = new CellHeap();
    this.cost[start] = 0;
    this.visited[start] = stamp;
    heap.push(0, start);

    const diagonal = FIELD_CELL_METRES * Math.SQRT2;

    while (heap.size > 0) {
      const cell = heap.pop();
      const spent = this.cost[cell] as number;

      const value = magnitude - spent * ATTENUATION_PER_METRE;
      if (value <= AUDIBLE_FLOOR) continue;
      // Loudest wins. A second, quieter source must not overwrite a nearer loud one.
      if (value > (this.noise[cell] as number)) this.noise[cell] = value;

      const cx = cell % this.w;
      const cy = (cell - cx) / this.w;

      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = cx + dx;
          const ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= this.w || ny >= this.h) continue;

          const next = ny * this.w + nx;
          const step =
            (dx !== 0 && dy !== 0 ? diagonal : FIELD_CELL_METRES) +
            (this.obstruction[next] as number);
          const total = spent + step;
          if (total > maxCost) continue;

          if (this.visited[next] !== stamp || total < (this.cost[next] as number)) {
            this.visited[next] = stamp;
            this.cost[next] = total;
            heap.push(total, next);
          }
        }
      }
    }
  }

  /**
   * Cast light from a point: line-of-sight only, unlike noise.
   *
   * docs/03 makes light "binary and directional" and blocked by "any opaque obstruction".
   * A wall really does stop it dead, which is what makes shutters a complete answer to a
   * lamp and never a complete answer to a generator.
   */
  emitLight(x: number, y: number, magnitude: number): void {
    if (magnitude <= AUDIBLE_FLOOR) return;

    const reachCells = Math.ceil(magnitude / ATTENUATION_PER_METRE / FIELD_CELL_METRES);
    const origin = this.cellAt(x, y);
    const ox = origin % this.w;
    const oy = (origin - ox) / this.w;

    for (let cy = Math.max(0, oy - reachCells); cy <= Math.min(this.h - 1, oy + reachCells); cy++) {
      for (
        let cx = Math.max(0, ox - reachCells);
        cx <= Math.min(this.w - 1, ox + reachCells);
        cx++
      ) {
        const metres = Math.hypot(cx - ox, cy - oy) * FIELD_CELL_METRES;
        const value = magnitude - metres * ATTENUATION_PER_METRE;
        if (value <= AUDIBLE_FLOOR) continue;
        if (!this.visible(ox, oy, cx, cy)) continue;

        const cell = cy * this.w + cx;
        if (value > (this.light[cell] as number)) this.light[cell] = value;
      }
    }
  }

  /**
   * Bresenham line of sight between two cells, tested at **tile** resolution.
   *
   * Deliberately finer than the field it writes into. docs/03 has light "blocked by any
   * opaque obstruction", and a single-tile wall is exactly that -- but it is only a quarter
   * of a 4 m field cell, so a coarse test would let a lamp shine straight through a
   * building's outside wall. Storage can be coarse; occlusion has to see the real geometry.
   *
   * Noise deliberately does the opposite and works on the coarse obstruction, because it
   * floods around rather than being occluded. The two channels disagreeing here is the
   * design, not an inconsistency.
   */
  private visible(acx: number, acy: number, bcx: number, bcy: number): boolean {
    const tilesPerCell = FIELD_CELL_METRES / TILE_METRES;
    const half = tilesPerCell / 2;

    let x = Math.floor(acx * tilesPerCell + half);
    let y = Math.floor(acy * tilesPerCell + half);
    const tx = Math.floor(bcx * tilesPerCell + half);
    const ty = Math.floor(bcy * tilesPerCell + half);

    const dx = Math.abs(tx - x);
    const dy = Math.abs(ty - y);
    const sx = x < tx ? 1 : -1;
    const sy = y < ty ? 1 : -1;
    let err = dx - dy;

    for (;;) {
      const e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x += sx;
      }
      if (e2 < dx) {
        err += dx;
        y += sy;
      }
      if (x === tx && y === ty) return true;
      if (isWall(this.map, x, y)) return false;
    }
  }

  /** Clear the light layer. Light is recomputed from emitters, never decayed. */
  clearLight(): void {
    this.light.fill(0);
  }

  /** Multiplicative noise decay for one tick. */
  decayNoise(tickSeconds: number): void {
    const factor = Math.pow(0.5, tickSeconds / NOISE_HALF_LIFE_SECONDS);
    for (let i = 0; i < this.noise.length; i++) {
      const v = (this.noise[i] as number) * factor;
      this.noise[i] = v < AUDIBLE_FLOOR ? 0 : v;
    }
  }

  /**
   * One scent diffusion step, with a global wind vector.
   *
   * Scent is the only channel that moves *after* it is emitted, and the only one that
   * pools: docs/03 has it drifting downwind and dispersing slowly, which is why a base can
   * become untenable over weeks without any single mistake.
   */
  diffuseScent(wind: Wind, stepSeconds: number): void {
    const next = new Float32Array(this.scent.length);
    const spread = SCENT_SPREAD;
    // Derived from the half-life rather than tuned directly, so the rate stays correct if
    // the diffusion interval or the tick rate ever changes.
    const keep = Math.pow(0.5, stepSeconds / SCENT_HALF_LIFE_SECONDS);

    for (let cy = 0; cy < this.h; cy++) {
      for (let cx = 0; cx < this.w; cx++) {
        const cell = cy * this.w + cx;
        const value = this.scent[cell] as number;
        if (value === 0) continue;

        const remaining = value * keep;
        next[cell] = (next[cell] as number) + remaining * (1 - spread);

        // The moving share goes downwind; with no wind it spreads evenly.
        const moving = remaining * spread;
        const wx = Math.max(-1, Math.min(1, Math.round(wind.dx)));
        const wy = Math.max(-1, Math.min(1, Math.round(wind.dy)));

        if (wx === 0 && wy === 0) {
          const share = moving / 8;
          for (let dy = -1; dy <= 1; dy++) {
            for (let dx = -1; dx <= 1; dx++) {
              if (dx === 0 && dy === 0) continue;
              this.give(next, cx + dx, cy + dy, share, cell);
            }
          }
        } else {
          // Two thirds downwind, the rest spread sideways, so a plume has a shape.
          this.give(next, cx + wx, cy + wy, moving * (2 / 3), cell);
          const share = (moving * (1 / 3)) / 8;
          for (let dy = -1; dy <= 1; dy++) {
            for (let dx = -1; dx <= 1; dx++) {
              if (dx === 0 && dy === 0) continue;
              this.give(next, cx + dx, cy + dy, share, cell);
            }
          }
        }
      }
    }

    for (let i = 0; i < next.length; i++) {
      const v = next[i] as number;
      this.scent[i] = v < AUDIBLE_FLOOR * 0.01 ? 0 : v;
    }
  }

  /**
   * Move scent into a neighbour, or back into the source if that neighbour is solid.
   *
   * Returning it rather than dropping it matters: scent that vanished into walls would make
   * an interior slowly self-cleaning, and "a base becomes untenable over weeks" depends on
   * it accumulating instead.
   */
  private give(next: Float32Array, cx: number, cy: number, amount: number, from: number): void {
    if (cx < 0 || cy < 0 || cx >= this.w || cy >= this.h) {
      next[from] = (next[from] as number) + amount;
      return;
    }
    const cell = cy * this.w + cx;
    if ((this.obstruction[cell] as number) >= WALL_EXTRA_METRES * 0.5) {
      next[from] = (next[from] as number) + amount;
      return;
    }
    next[cell] = (next[cell] as number) + amount;
  }

  // ---- serialization -------------------------------------------------------

  /**
   * Sparse, sorted, non-zero cells only.
   *
   * The field is 64x64 cells per district but almost entirely empty almost all the time --
   * the spike measured 6 live cells on a quiet night. Storing the dense arrays would put a
   * fixed 12,288 numbers into every save to describe nothing.
   */
  save(): FieldSave {
    const out = {} as FieldSave;
    for (const channel of CHANNELS) {
      const layer = this.layer(channel);
      const pairs: [number, number][] = [];
      for (let i = 0; i < layer.length; i++) {
        const v = layer[i] as number;
        // Object.is guards -0, which canonicalize() rejects outright.
        if (v !== 0 && !Object.is(v, -0)) pairs.push([i, v]);
      }
      out[channel] = pairs;
    }
    return out;
  }

  restore(saved: FieldSave): void {
    for (const channel of CHANNELS) {
      const layer = this.layer(channel);
      layer.fill(0);
      for (const [cell, value] of saved[channel] ?? []) {
        if (cell >= 0 && cell < layer.length) layer[cell] = value;
      }
    }
  }
}

// ---- a deterministic min-heap ----------------------------------------------

/**
 * Binary min-heap over (cost, cell), breaking ties on cell index.
 *
 * The tie-break is not cosmetic. Two cells reached at exactly equal cost are common on an
 * open street, and without a total order the pop order would depend on insertion order --
 * which depends on the direction the flood happened to arrive from. That is precisely the
 * kind of "same seed diverged, once" bug docs/19 rates as severe as a crash.
 */
class CellHeap {
  private readonly costs: number[] = [];
  private readonly cells: number[] = [];

  get size(): number {
    return this.cells.length;
  }

  private less(a: number, b: number): boolean {
    const ca = this.costs[a] as number;
    const cb = this.costs[b] as number;
    if (ca !== cb) return ca < cb;
    return (this.cells[a] as number) < (this.cells[b] as number);
  }

  private swap(a: number, b: number): void {
    const c = this.costs[a] as number;
    this.costs[a] = this.costs[b] as number;
    this.costs[b] = c;
    const e = this.cells[a] as number;
    this.cells[a] = this.cells[b] as number;
    this.cells[b] = e;
  }

  push(cost: number, cell: number): void {
    this.costs.push(cost);
    this.cells.push(cell);
    let i = this.cells.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (!this.less(i, parent)) break;
      this.swap(i, parent);
      i = parent;
    }
  }

  pop(): number {
    const top = this.cells[0] as number;
    const lastCost = this.costs.pop() as number;
    const lastCell = this.cells.pop() as number;

    if (this.cells.length > 0) {
      this.costs[0] = lastCost;
      this.cells[0] = lastCell;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let smallest = i;
        if (l < this.cells.length && this.less(l, smallest)) smallest = l;
        if (r < this.cells.length && this.less(r, smallest)) smallest = r;
        if (smallest === i) break;
        this.swap(i, smallest);
        i = smallest;
      }
    }

    return top;
  }
}
