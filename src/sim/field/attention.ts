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
// Two of the three channels are built: **noise** and **scent**. Light (shadowcasting) is
// specified in docs/03 and still deliberately absent rather than stubbed.
//
// Noise and scent were built in that order, separately, because they are not the same
// mechanic with different constants and measuring them together would have confused two
// numbers. Noise is *event-driven* -- it costs what is emitted and nothing at rest, which
// the spike vindicated at six live cells when quiet. Scent is *continuous*: it costs the
// same whether or not anything is happening, which is the one docs/23-roadmap.md#risks
// calls the most likely thing to need rework. Everything below that looks asymmetric between
// the two channels follows from that difference, and is commented where it appears:
//
//   - noise commits with `max`, scent *sums* (a crowd smells more; it is not louder)
//   - noise is blocked by walls, scent is blocked by nothing at all
//   - noise decays in seconds, scent in tens of minutes
//   - noise reaches the field through an event, scent through the same event *and* a
//     continuous diffusion step that runs whether or not anyone emitted

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

  /**
   * Scent half-life, in **minutes**.
   *
   * The unit differs from noise's on purpose. docs/03's channel table puts noise at "seconds
   * to a minute" and scent at "hours", and the two being expressed in the same unit is how
   * you end up reasoning about them as one thing. They are not one thing: noise is spiky and
   * event-driven, scent is cumulative and continuous, and every difference below follows from
   * that.
   */
  readonly scentHalfLifeMinutes: number;
  /** Fraction of a cell's scent that leaves it per diffusion step. */
  readonly scentDiffusionRate: number;
  /**
   * Below this, a cell has no scent left.
   *
   * **Separate from {@link Calibration.floor}, and the separation was measured rather than
   * assumed.** The noise floor sits near zero so that docs/03's `reach = magnitude /
   * attenuation` identity holds exactly -- an identity a diffusive channel does not have at
   * all. Sharing the constant made the *floor*, not the half-life, govern how long a smell
   * lasted: diffusion dilutes a plume until every cell crosses the threshold at roughly the
   * same moment, so a deposit evaporated in about two minutes while the calibration claimed
   * ninety. Scent needs its own, lower, threshold or its stated half-life is decoration.
   */
  readonly scentFloor: number;
  /** Ticks between diffusion steps. 5 at 20 Hz is docs/03's "a diffusion step at a few Hz". */
  readonly scentIntervalTicks: number;
  /**
   * Maximum scent in one cell.
   *
   * Noise takes a maximum and is therefore bounded by its loudest emitter; scent *sums*,
   * because a crowd smells more than one body does. A permanent emitter against an unbounded
   * sum is a Float32 walking somewhere `canonicalize` cannot follow it.
   */
  readonly scentCeiling: number;
  /**
   * Global wind, x. Vector length is strength; `0,0` is dead calm and diffusion is isotropic.
   *
   * Constant, and deliberately not save state: it derives from calibration, which is fixed at
   * boot exactly like the cell geometry. [Weather](../../../docs/16-weather.md) owns wind from
   * Milestone 3 -- it shifts over days, and at that point wind becomes state and moves into
   * the snapshot. This is the seam it takes over, not a placeholder to be surprised by.
   */
  readonly windX: number;
  /** Global wind, y. See {@link Calibration.windX}. */
  readonly windY: number;
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
  scentHalfLifeMinutes: 90,
  scentDiffusionRate: 0.02,
  scentFloor: 0.005,
  scentIntervalTicks: 5,
  scentCeiling: 5000,
  windX: 0.6,
  windY: -0.2,
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
    scentHalfLifeMinutes: read("scentHalfLifeMinutes"),
    scentDiffusionRate: read("scentDiffusionRate"),
    scentFloor: read("scentFloor"),
    scentIntervalTicks: read("scentIntervalTicks"),
    scentCeiling: read("scentCeiling"),
    windX: read("windX"),
    windY: read("windY"),
  };
}

/** Sparse: `[cellIndex, value]` for the live cells only, ascending by index. */
export type AttentionFieldSave = {
  readonly cols: number;
  readonly rows: number;
  readonly noise: readonly [number, number][];
  readonly scent: readonly [number, number][];
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

  /** Scent magnitude per cell. Public for the overlay on the same terms as {@link noise}. */
  readonly scent: Float32Array;

  private readonly solid: Uint8Array;

  // Scratch, reused so a propagation allocates nothing.
  private readonly staged: Float32Array;
  private readonly queue: Int32Array;
  private readonly queued: Uint8Array;
  private readonly touched: Int32Array;

  /** Diffusion destination. Copied back rather than swapped -- see {@link diffuseScent}. */
  private readonly scentNext: Float32Array;

  /** Cells written by the last propagation. The cost measure docs/22 actually cares about. */
  lastEmitCells = 0;

  private readonly stepCost: number;
  private readonly diagonalCost: number;
  private readonly wallCost: number;
  private readonly decayPerTick: number;

  /**
   * Outflow share for each of the four neighbours, in the order [+x, -x, +y, -y].
   *
   * Derived once, because wind is constant. All of the wind bias lives here: nothing in the
   * diffusion loop knows which way the wind blows, it only reads four numbers that sum to 1.
   */
  private readonly windWeights: Float32Array;
  private readonly scentDecayPerStep: number;

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
    this.scent = new Float32Array(n);
    this.scentNext = new Float32Array(n);
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

    // Scent decays per *diffusion step*, not per tick, because that is when it runs. Its
    // half-life is in minutes, so at 4 Hz this is a number very close to 1 -- which is the
    // point. A shout is gone in half a minute; a smell is still there an hour later.
    const scentInterval = Math.max(1, Math.round(calibration.scentIntervalTicks));
    const stepsPerHalfLife = (calibration.scentHalfLifeMinutes * 60 * tickHz) / scentInterval;
    this.scentDecayPerStep = 0.5 ** (1 / stepsPerHalfLife);

    // Wind bias, resolved once into four outflow shares.
    //
    // A neighbour's share is `1 + dot(direction, wind)`, floored at zero: dead calm gives
    // four equal 0.25s and diffusion is isotropic, while a strong wind starves the upwind
    // neighbour entirely. Normalising to sum 1 is what makes diffusion conservative -- scent
    // moves, and only decay destroys it.
    const raw = [
      Math.max(0, 1 + calibration.windX),
      Math.max(0, 1 - calibration.windX),
      Math.max(0, 1 + calibration.windY),
      Math.max(0, 1 - calibration.windY),
    ];
    const total = raw[0]! + raw[1]! + raw[2]! + raw[3]!;
    this.windWeights = new Float32Array(4);
    for (let i = 0; i < 4; i++) this.windWeights[i] = raw[i]! / total;
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
   * Add scent to a cell.
   *
   * **Accumulates, where noise takes a maximum**, and the difference is the design rather
   * than an oversight. Two people shouting together are not twice as loud, so noise commits
   * with `max`; two people standing together *do* smell more than one, and docs/03 calls
   * population "a permanent, unavoidable scent floor". Summing is what makes that true.
   *
   * The ceiling is what summing costs: a permanent emitter against an unbounded sum walks a
   * Float32 somewhere `canonicalize` cannot follow it.
   */
  addScent(x: number, y: number, magnitude: number): void {
    const cell = this.cellAt(x, y);
    if (cell === -1 || magnitude <= 0) return;
    const total = (this.scent[cell] as number) + magnitude;
    const { scentCeiling } = this.calibration;
    this.scent[cell] = total > scentCeiling ? scentCeiling : total;
  }

  /**
   * One diffusion-and-decay step. Called every `scentIntervalTicks`, not every tick.
   *
   * **Gather, not scatter.** Each cell computes its new value by *pulling* a share from each
   * of its four neighbours, rather than pushing its own outward. Both express the same
   * physics; only one is deterministic for free. A scatter accumulates into each cell from
   * several sources in whatever order the loop reaches them, and float addition is not
   * associative -- so the result would depend on iteration order, which is exactly the class
   * of bug the kernel's sort-everything rules exist to prevent. A gather visits each cell
   * once and sums a fixed number of terms in a fixed order, so determinism falls out of the
   * shape of the loop and needs no sorting at all.
   *
   * **Walls do not block scent.** docs/03's channel table lists scent as blocked by
   * *nothing* -- only wind and time disperse it -- so unlike noise there is no wall cost and
   * no solid-cell skip here. That asymmetry is deliberate; it is not a missing check.
   */
  diffuseScent(): void {
    const { cols, rows, scent, scentNext, windWeights, scentDecayPerStep } = this;
    const { scentFloor, scentDiffusionRate } = this.calibration;
    const keep = 1 - scentDiffusionRate;

    // Each neighbour sends us the share it would send in our direction: the cell to our +x
    // sends along -x, so we read weight[1] from it, and so on. Pairing each offset with the
    // opposite weight is what keeps the gather equivalent to the scatter it replaces.
    const wPlusX = windWeights[0] as number;
    const wMinusX = windWeights[1] as number;
    const wPlusY = windWeights[2] as number;
    const wMinusY = windWeights[3] as number;

    for (let cy = 0; cy < rows; cy++) {
      for (let cx = 0; cx < cols; cx++) {
        const here = cy * cols + cx;
        let value = (scent[here] as number) * keep;

        if (cx + 1 < cols) value += (scent[here + 1] as number) * scentDiffusionRate * wMinusX;
        if (cx - 1 >= 0) value += (scent[here - 1] as number) * scentDiffusionRate * wPlusX;
        if (cy + 1 < rows) value += (scent[here + cols] as number) * scentDiffusionRate * wMinusY;
        if (cy - 1 >= 0) value += (scent[here - cols] as number) * scentDiffusionRate * wPlusY;

        const decayed = value * scentDecayPerStep;
        scentNext[here] = decayed < scentFloor ? 0 : decayed;
      }
    }

    // Copied back rather than swapped: `scent` is a readonly reference the renderer holds, and
    // swapping would leave the overlay drawing last step's buffer. 4,096 floats is nothing.
    scent.set(scentNext);
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
    return this.uphill(this.noise, x, y);
  }

  /**
   * The shared 8-way scan behind {@link uphillNoise} and {@link uphillScent}.
   *
   * Solid cells are skipped for both channels. Scent *propagates* through walls -- docs/03
   * says nothing blocks it -- but a zombie still cannot walk into one, and this is a question
   * about where to step, not about where the smell got to.
   */
  private uphill(
    layer: Float32Array,
    x: number,
    y: number,
  ): { dx: number; dy: number; value: number } | null {
    const here = this.cellAt(x, y);
    if (here === -1) return null;

    const { cols, rows, solid } = this;
    const cx = here % cols;
    const cy = (here - cx) / cols;

    let best = layer[here] as number;
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
        if ((layer[next] as number) > best) {
          best = layer[next] as number;
          bestDx = dx;
          bestDy = dy;
        }
      }
    }

    if (bestDx === 0 && bestDy === 0) return null;
    return { dx: bestDx, dy: bestDy, value: best };
  }

  /** Scent magnitude at a world position. */
  scentAt(x: number, y: number): number {
    const cell = this.cellAt(x, y);
    return cell === -1 ? 0 : (this.scent[cell] as number);
  }

  /**
   * The strongest-smelling open neighbour, if it beats standing still.
   *
   * The scent twin of {@link uphillNoise}, and it returns a cell step for the same reason.
   * What the caller does with it differs: docs/03 wants noise applied as an *impulse* and
   * scent as a *bias*, so a shambler turns to face a noise and merely leans toward a smell.
   */
  uphillScent(x: number, y: number): { dx: number; dy: number; value: number } | null {
    return this.uphill(this.scent, x, y);
  }

  /** Cells carrying any scent at all. The scent twin of {@link liveCells}. */
  liveScentCells(): number {
    let n = 0;
    for (let i = 0; i < this.scent.length; i++) if (this.scent[i] !== 0) n++;
    return n;
  }

  peakScent(): number {
    let peak = 0;
    for (let i = 0; i < this.scent.length; i++) {
      const value = this.scent[i] as number;
      if (value > peak) peak = value;
    }
    return peak;
  }

  /**
   * Cells carrying any noise at all. The "quiet costs nothing" measurement.
   *
   * Noise only, and it stays that way. Three assertions in the Milestone 1 exit criterion
   * read `liveCells() === 0` as "the district is silent", and folding a channel that decays
   * over hours into that number would break the noise criterion for no reason.
   * {@link liveScentCells} is the scent one.
   */
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
    this.scent.fill(0);
    this.scentNext.fill(0);
  }

  /** Live cells only, ascending by index so the output is canonical. */
  save(): AttentionFieldSave {
    return {
      cols: this.cols,
      rows: this.rows,
      noise: sparse(this.noise),
      scent: sparse(this.scent),
    };
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
    this.clear();
    fill(this.noise, saved.noise);
    fill(this.scent, saved.scent);
  }
}

/** Live cells only, ascending by index so the output is canonical. */
function sparse(layer: Float32Array): [number, number][] {
  const live: [number, number][] = [];
  for (let i = 0; i < layer.length; i++) {
    const value = layer[i] as number;
    if (value !== 0) live.push([i, value]);
  }
  return live;
}

function fill(layer: Float32Array, saved: readonly [number, number][]): void {
  for (const [cell, value] of saved) {
    if (cell < 0 || cell >= layer.length) {
      throw new Error(`Attention field save has cell ${cell} outside 0..${layer.length - 1}`);
    }
    layer[cell] = value;
  }
}
