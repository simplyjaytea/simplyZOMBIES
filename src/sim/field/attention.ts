// The attention field.
//
// docs/03-attention.md is the specification, and it opens with "if you only read one system
// document, read this one." Survival, colony sim, tower defense and RPG blend because they
// all write to and read from this one structure.
//
// Kernel, not a module. docs/19-architecture.md#one-spine-many-optional-limbs draws the line
// at "the tick loop, the entity store, the event bus, and the attention field" -- everything
// else is optional. So the field exists in every world, including one booted with every
// module switched off; what disappears with the modules is anything that *emits* into it.
//
// Milestone 1 phase 1 builds the **noise** channel only. Light (shadowcasting) and scent
// (diffusion with a wind vector) are specified in docs/03 and are deliberately absent here
// rather than stubbed: the spike proved event-driven noise is nearly free, and scent is the
// continuous channel docs/23-roadmap.md#risks calls the most likely thing to need rework.
// Building it in the same breath as noise would confuse two measurements.

import type { ContentRegistry } from "../content/registry";
import { isWall, type TileMap } from "../map/tilemap";

/**
 * The four constants docs/03-attention.md#scale-and-calibration supplies, plus the floor.
 *
 * The spike got this wrong in the expensive way (docs/23-roadmap.md#problem-2): it picked an
 * attenuation constant arbitrarily, ~3x too steep, and one shout flooded a district. The
 * magnitude table was never the problem -- the *unit* had never been written down.
 */
export type Calibration = {
  /** Metres per field cell. The field is deliberately coarser than the tile grid. */
  readonly cellMetres: number;
  /** Magnitude lost per metre of open-ground travel. */
  readonly attenuationPerMetre: number;
  /** A solid cell costs this much extra travel, in metres. */
  readonly wallPenaltyMetres: number;
  /** Noise half-life, in seconds. */
  readonly noiseHalfLifeSeconds: number;
  /**
   * Below this, a cell is silent and propagation stops.
   *
   * Small on purpose. docs/03 states reach as `magnitude / attenuation` metres -- walking at
   * magnitude 1 carries 1.4 m -- and that identity only holds if the floor is near zero. It
   * is not a hearing threshold; a sensory profile applies that per zombie.
   */
  readonly floor: number;
};

/**
 * The shipped calibration.
 *
 * `content/calibration/attention.json` is the authority a designer edits, and
 * `test/integration/attention.test.ts` asserts the two agree -- so drift fails the build
 * rather than producing a game that disagrees with its own documentation. This copy exists
 * because content loads after `boot` builds the world, and the field's cell geometry has to
 * be known before the first tick.
 */
export const DEFAULT_CALIBRATION: Calibration = {
  cellMetres: 4,
  attenuationPerMetre: 0.7,
  wallPenaltyMetres: 18,
  noiseHalfLifeSeconds: 3,
  floor: 0.05,
};

/** The single calibration entry every emitter is measured against. */
export const CALIBRATION_ID = "calibration.attention";

/**
 * Read the calibration out of loaded content.
 *
 * Throws when the entry is missing, rather than falling back. A silent fallback is how a
 * deleted content file becomes "the horde behaves oddly at hour thirty" instead of a message
 * at boot -- the failure mode docs/20-ecs-and-content.md#validation exists to prevent.
 */
export function calibrationFromContent(content: ContentRegistry): Calibration {
  const entry = content.getOrThrow("calibration", CALIBRATION_ID);
  const read = (field: keyof Calibration): number => {
    const value = entry[field];
    if (typeof value !== "number") {
      throw new Error(`${CALIBRATION_ID}: "${field}" must be a number`);
    }
    return value;
  };
  return {
    cellMetres: read("cellMetres"),
    attenuationPerMetre: read("attenuationPerMetre"),
    wallPenaltyMetres: read("wallPenaltyMetres"),
    noiseHalfLifeSeconds: read("noiseHalfLifeSeconds"),
    floor: read("floor"),
  };
}

/** Sparse: `[cellIndex, value]` for the live cells only, ascending by index. */
export type AttentionFieldSave = {
  readonly cols: number;
  readonly rows: number;
  readonly noise: readonly [number, number][];
};

/**
 * Noise, on a coarse grid.
 *
 * Storage is dense (a 256 m district is 64x64 = 4,096 cells, which is nothing) but *saves*
 * are sparse, because the spike measured six live cells at rest against 1,112 after a shout.
 * A dense save would make every quiet moment pay for the loudest one.
 */
export class AttentionField {
  readonly cols: number;
  readonly rows: number;
  readonly cellMetres: number;
  readonly calibration: Calibration;

  /** Noise magnitude per cell. Public for the renderer's debug overlay, which only reads. */
  readonly noise: Float32Array;

  private readonly solid: Uint8Array;

  // Scratch, reused so a propagation allocates nothing.
  private readonly staged: Float32Array;
  private readonly queue: Int32Array;
  private readonly queued: Uint8Array;
  private readonly touched: Int32Array;

  /** Cells written by the last propagation. The cost measure docs/22 actually cares about. */
  lastEmitCells = 0;

  private readonly stepCost: number;
  private readonly diagonalCost: number;
  private readonly wallCost: number;
  private readonly decayPerTick: number;

  private constructor(
    cols: number,
    rows: number,
    solid: Uint8Array,
    calibration: Calibration,
    tickHz: number,
  ) {
    this.cols = cols;
    this.rows = rows;
    this.cellMetres = calibration.cellMetres;
    this.calibration = calibration;
    this.solid = solid;

    const n = cols * rows;
    this.noise = new Float32Array(n);
    this.staged = new Float32Array(n);
    this.queue = new Int32Array(n + 1);
    this.queued = new Uint8Array(n);
    this.touched = new Int32Array(n);

    // Travel cost is distance in metres times attenuation per metre, so the cell size can
    // change without re-authoring a single magnitude. That decoupling is the whole lesson of
    // the spike's problem 2.
    this.stepCost = calibration.cellMetres * calibration.attenuationPerMetre;
    this.diagonalCost = this.stepCost * Math.SQRT2;
    this.wallCost = calibration.wallPenaltyMetres * calibration.attenuationPerMetre;
    this.decayPerTick = 0.5 ** (1 / (calibration.noiseHalfLifeSeconds * tickHz));
  }

  /**
   * Build a field sized to a map.
   *
   * A cell is solid only when *every* tile under it is a wall. Half-covered cells stay open,
   * which is what makes docs/03's "noise routes around obstructions" true: streets conduct,
   * and a building casts a smaller shadow than its footprint suggests.
   */
  static forMap(
    map: TileMap,
    calibration: Calibration = DEFAULT_CALIBRATION,
    tickHz = 20,
  ): AttentionField {
    const per = Math.max(1, Math.round(calibration.cellMetres));
    const cols = Math.ceil(map.w / per);
    const rows = Math.ceil(map.h / per);
    const solid = new Uint8Array(cols * rows);

    for (let cy = 0; cy < rows; cy++) {
      for (let cx = 0; cx < cols; cx++) {
        let all = true;
        for (let ty = 0; ty < per && all; ty++) {
          for (let tx = 0; tx < per; tx++) {
            if (!isWall(map, cx * per + tx, cy * per + ty)) {
              all = false;
              break;
            }
          }
        }
        solid[cy * cols + cx] = all ? 1 : 0;
      }
    }

    return new AttentionField(cols, rows, solid, calibration, tickHz);
  }

  /**
   * A field with nowhere to propagate.
   *
   * `new World(seed)` has no map -- the map is built by `boot` -- so a world starts with an
   * inert field and `boot` replaces it. Inert rather than absent, so nothing has to null-check
   * the kernel.
   */
  static empty(calibration: Calibration = DEFAULT_CALIBRATION, tickHz = 20): AttentionField {
    return new AttentionField(0, 0, new Uint8Array(0), calibration, tickHz);
  }

  get cellCount(): number {
    return this.cols * this.rows;
  }

  /** Cell index for a world position in metres, or -1 if the field has no cells. */
  cellAt(x: number, y: number): number {
    if (this.cellCount === 0) return -1;
    const cx = Math.min(this.cols - 1, Math.max(0, Math.floor(x / this.cellMetres)));
    const cy = Math.min(this.rows - 1, Math.max(0, Math.floor(y / this.cellMetres)));
    return cy * this.cols + cx;
  }

  isSolid(cell: number): boolean {
    return this.solid[cell] === 1;
  }

  /** Noise at a world position, in magnitude. */
  noiseAt(x: number, y: number): number {
    const cell = this.cellAt(x, y);
    return cell === -1 ? 0 : (this.noise[cell] as number);
  }

  /**
   * Propagate a noise event outward from a world position.
   *
   * Relaxation over cells rather than a ray cast: a cell's value is the source magnitude
   * minus accumulated travel, walls costing extra, and propagation stops the moment the
   * remaining value drops under the floor. That bound is what makes cost proportional to
   * magnitude -- a footstep touches one cell, and only a gunshot pays for a district.
   *
   * Committed as a maximum rather than a sum, so two emitters in the same place cannot run
   * the field away to infinity.
   */
  emitNoise(x: number, y: number, magnitude: number): void {
    this.lastEmitCells = 0;
    const start = this.cellAt(x, y);
    if (start === -1 || magnitude < this.calibration.floor) return;

    const { cols, rows, noise, staged, solid, queue, queued, touched } = this;
    const { floor } = this.calibration;
    const capacity = queue.length;

    let head = 0;
    let tail = 0;
    let nTouched = 0;

    staged[start] = magnitude;
    touched[nTouched++] = start;
    queue[tail] = start;
    tail = (tail + 1) % capacity;
    queued[start] = 1;

    while (head !== tail) {
      const cell = queue[head] as number;
      head = (head + 1) % capacity;
      queued[cell] = 0;

      const value = staged[cell] as number;
      if (value < floor) continue;

      const cx = cell % cols;
      const cy = (cell - cx) / cols;

      for (let dy = -1; dy <= 1; dy++) {
        const ny = cy + dy;
        if (ny < 0 || ny >= rows) continue;

        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = cx + dx;
          if (nx < 0 || nx >= cols) continue;

          const next = ny * cols + nx;
          let cost = dx !== 0 && dy !== 0 ? this.diagonalCost : this.stepCost;
          if (solid[next] === 1) cost += this.wallCost;

          const arriving = value - cost;
          if (arriving < floor) continue;
          if (arriving <= (staged[next] as number)) continue;

          if (staged[next] === 0) touched[nTouched++] = next;
          staged[next] = arriving;

          // SPFA: a cell already waiting does not need queueing twice, which is what keeps
          // the ring buffer from ever overflowing and losing work silently.
          if (queued[next] === 0) {
            queued[next] = 1;
            queue[tail] = next;
            tail = (tail + 1) % capacity;
          }
        }
      }
    }

    for (let i = 0; i < nTouched; i++) {
      const cell = touched[i] as number;
      if ((staged[cell] as number) > (noise[cell] as number)) noise[cell] = staged[cell] as number;
      staged[cell] = 0;
    }
    this.lastEmitCells = nTouched;
  }

  /**
   * Multiplicative decay, one tick's worth.
   *
   * Anything falling under the floor is snapped to a hard zero rather than left as a
   * denormal crumb. Two reasons, and the second is the one that bites: a cell that never
   * quite reaches zero stays "live" forever and quiet stops being free, and `canonicalize`
   * rejects negative zero outright, which a decaying float can otherwise produce.
   */
  decay(): void {
    const { noise, decayPerTick } = this;
    const { floor } = this.calibration;
    for (let i = 0; i < noise.length; i++) {
      const value = noise[i] as number;
      if (value === 0) continue;
      const decayed = value * decayPerTick;
      noise[i] = decayed < floor ? 0 : decayed;
    }
  }

  /**
   * The loudest open neighbour of a world position, if it beats standing still.
   *
   * Eight-way, and returning a cell step rather than an angle -- the caller turns it into a
   * heading and applies its own persistent bias, because without that every zombie in a cell
   * picks the same neighbour and they form
   * [conga lines, not a horde](docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own).
   */
  uphillNoise(x: number, y: number): { dx: number; dy: number; value: number } | null {
    const here = this.cellAt(x, y);
    if (here === -1) return null;

    const { cols, rows, noise, solid } = this;
    const cx = here % cols;
    const cy = (here - cx) / cols;

    let best = noise[here] as number;
    let bestDx = 0;
    let bestDy = 0;

    for (let dy = -1; dy <= 1; dy++) {
      const ny = cy + dy;
      if (ny < 0 || ny >= rows) continue;

      for (let dx = -1; dx <= 1; dx++) {
        if (dx === 0 && dy === 0) continue;
        const nx = cx + dx;
        if (nx < 0 || nx >= cols) continue;

        const next = ny * cols + nx;
        if (solid[next] === 1) continue;
        if ((noise[next] as number) > best) {
          best = noise[next] as number;
          bestDx = dx;
          bestDy = dy;
        }
      }
    }

    if (bestDx === 0 && bestDy === 0) return null;
    return { dx: bestDx, dy: bestDy, value: best };
  }

  /** Cells carrying any noise at all. The "quiet costs nothing" measurement. */
  liveCells(): number {
    let n = 0;
    for (let i = 0; i < this.noise.length; i++) if (this.noise[i] !== 0) n++;
    return n;
  }

  peakNoise(): number {
    let peak = 0;
    for (let i = 0; i < this.noise.length; i++) {
      const value = this.noise[i] as number;
      if (value > peak) peak = value;
    }
    return peak;
  }

  clear(): void {
    this.noise.fill(0);
  }

  /** Live cells only, ascending by index so the output is canonical. */
  save(): AttentionFieldSave {
    const live: [number, number][] = [];
    for (let i = 0; i < this.noise.length; i++) {
      const value = this.noise[i] as number;
      if (value !== 0) live.push([i, value]);
    }
    return { cols: this.cols, rows: this.rows, noise: live };
  }

  restore(saved: AttentionFieldSave): void {
    if (saved.cols !== this.cols || saved.rows !== this.rows) {
      // Geometry comes from the map, which regenerates from the seed. A mismatch means the
      // save was taken in a differently-shaped world, which is not something to paper over.
      throw new Error(
        `Attention field is ${this.cols}x${this.rows} but the save is ` +
          `${saved.cols}x${saved.rows}`,
      );
    }
    this.noise.fill(0);
    for (const [cell, value] of saved.noise) {
      if (cell < 0 || cell >= this.noise.length) {
        throw new Error(
          `Attention field save has cell ${cell} outside 0..${this.noise.length - 1}`,
        );
      }
      this.noise[cell] = value;
    }
  }
}
