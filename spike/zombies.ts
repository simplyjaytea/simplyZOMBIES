import { blockedAt, isWall, MAP_H, MAP_W, TILE, type TileMap } from "./map";
import type { NoiseField } from "./field";
import { makeRng } from "./rng";

export const enum ZState {
  Wander = 0,
  Seek = 1,
  Investigate = 2,
}

export type Zombie = {
  x: number;
  y: number;
  state: ZState;
  /** Wander drift direction. */
  wx: number;
  wy: number;
  wanderTicks: number;
  investigateTicks: number;
  residueCooldown: number;
  /** Persistent per-individual angular bias applied to the gradient. See `spreadEnabled`. */
  bias: number;
};

const SPEED_WANDER = 9;   // px/sec
const SPEED_SEEK = 19;

/** How long they mill about after arriving at a noise that turned out to be nothing. */
const INVESTIGATE_TICKS = 90;

/**
 * Milling bodies are themselves a little bit loud, so somewhere you made a mistake
 * stays a mildly attractive neighbourhood after the fact. This is the "field has
 * memory" claim from docs/03-attention.md, and question 5 of the spike.
 */
const RESIDUE_MAGNITUDE = 5;
const RESIDUE_INTERVAL = 25;

/**
 * Naive gradient ascent makes every zombie at a given cell pick the same one of eight
 * directions, so they collapse into single-file conga lines instead of a crowd. A
 * persistent per-individual angular bias fans them out at no per-neighbour cost.
 */
const SPREAD_RADIANS = 0.62;

export class Horde {
  zombies: Zombie[] = [];
  private rng: () => number;
  /** Set false to test whether field memory is actually doing anything. */
  residueEnabled = true;
  /** Set false to see the raw conga-line behaviour of unmodified gradient ascent. */
  spreadEnabled = true;

  constructor(seed = 1337) {
    this.rng = makeRng(seed);
  }

  get count(): number {
    return this.zombies.length;
  }

  spawnScattered(map: TileMap, n: number, avoidX: number, avoidY: number, minDist = 220): void {
    let guard = 0;
    let placed = 0;
    while (placed < n && guard < n * 200) {
      guard++;
      const tx = 1 + Math.floor(this.rng() * (MAP_W - 2));
      const ty = 1 + Math.floor(this.rng() * (MAP_H - 2));
      if (isWall(map, tx, ty)) continue;
      const x = tx * TILE + TILE / 2;
      const y = ty * TILE + TILE / 2;
      if (Math.hypot(x - avoidX, y - avoidY) < minDist) continue;
      this.zombies.push({
        x, y,
        state: ZState.Wander,
        wx: 0, wy: 0,
        wanderTicks: 0,
        investigateTicks: 0,
        residueCooldown: Math.floor(this.rng() * RESIDUE_INTERVAL),
        bias: (this.rng() * 2 - 1) * SPREAD_RADIANS,
      });
      placed++;
    }
  }

  clear(): void {
    this.zombies.length = 0;
  }

  update(map: TileMap, field: NoiseField, dt: number): void {
    const rng = this.rng;

    for (let i = 0; i < this.zombies.length; i++) {
      const z = this.zombies[i];

      switch (z.state) {
        case ZState.Wander: {
          if (field.audible(z.x, z.y)) { z.state = ZState.Seek; break; }
          if (z.wanderTicks <= 0) {
            const a = rng() * Math.PI * 2;
            z.wx = Math.cos(a);
            z.wy = Math.sin(a);
            z.wanderTicks = 40 + Math.floor(rng() * 80);
          }
          z.wanderTicks--;
          this.step(map, z, z.wx * SPEED_WANDER * dt, z.wy * SPEED_WANDER * dt);
          break;
        }

        case ZState.Seek: {
          const up = field.uphill(z.x, z.y);
          if (up) {
            let a = Math.atan2(up.dy, up.dx);
            if (this.spreadEnabled) a += z.bias;
            this.step(map, z, Math.cos(a) * SPEED_SEEK * dt, Math.sin(a) * SPEED_SEEK * dt);
          } else if (field.audible(z.x, z.y)) {
            // At a local maximum, and nothing here. Mill about.
            z.state = ZState.Investigate;
            z.investigateTicks = INVESTIGATE_TICKS;
          } else {
            z.state = ZState.Wander;
            z.wanderTicks = 0;
          }
          break;
        }

        case ZState.Investigate: {
          z.investigateTicks--;
          if (z.investigateTicks <= 0) {
            z.state = ZState.Wander;
            z.wanderTicks = 0;
            break;
          }
          // Shuffle in place.
          if (z.wanderTicks <= 0) {
            const a = rng() * Math.PI * 2;
            z.wx = Math.cos(a);
            z.wy = Math.sin(a);
            z.wanderTicks = 10 + Math.floor(rng() * 15);
          }
          z.wanderTicks--;
          this.step(map, z, z.wx * SPEED_WANDER * 0.5 * dt, z.wy * SPEED_WANDER * 0.5 * dt);

          if (this.residueEnabled) {
            if (z.residueCooldown <= 0) {
              field.emit(z.x, z.y, RESIDUE_MAGNITUDE);
              z.residueCooldown = RESIDUE_INTERVAL;
            } else {
              z.residueCooldown--;
            }
          }
          break;
        }
      }
    }
  }

  private step(map: TileMap, z: Zombie, dx: number, dy: number): void {
    const r = 3;
    if (dx !== 0) {
      const nx = z.x + dx;
      const edge = nx + Math.sign(dx) * r;
      if (!blockedAt(map, edge, z.y - r) && !blockedAt(map, edge, z.y + r)) z.x = nx;
      else z.wanderTicks = 0;
    }
    if (dy !== 0) {
      const ny = z.y + dy;
      const edge = ny + Math.sign(dy) * r;
      if (!blockedAt(map, z.x - r, edge) && !blockedAt(map, z.x + r, edge)) z.y = ny;
      else z.wanderTicks = 0;
    }
  }

  countByState(): [number, number, number] {
    let w = 0, s = 0, inv = 0;
    for (const z of this.zombies) {
      if (z.state === ZState.Wander) w++;
      else if (z.state === ZState.Seek) s++;
      else inv++;
    }
    return [w, s, inv];
  }
}
