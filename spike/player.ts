import { blockedAt, TILE, type TileMap } from "./map";
import type { NoiseField } from "./field";

// Magnitudes lifted from docs/03-attention.md, scaled to this map's size.
export const NOISE_WALK = 1;
export const NOISE_SPRINT = 6;
export const NOISE_SHOUT = 120;

const WALK_SPEED = 46;   // px/sec
const SPRINT_SPEED = 92;

export type Player = {
  x: number;
  y: number;
  sprinting: boolean;
  /** Ticks until the next footstep emission. */
  stepCooldown: number;
  shoutFlash: number;
};

export function createPlayer(x: number, y: number): Player {
  return { x, y, sprinting: false, stepCooldown: 0, shoutFlash: 0 };
}

/** Axis-separated so sliding along a wall feels right rather than sticking. */
function move(map: TileMap, p: Player, dx: number, dy: number): void {
  const r = 3.5;
  if (dx !== 0) {
    const nx = p.x + dx;
    const edge = nx + Math.sign(dx) * r;
    if (!blockedAt(map, edge, p.y - r) && !blockedAt(map, edge, p.y + r)) p.x = nx;
  }
  if (dy !== 0) {
    const ny = p.y + dy;
    const edge = ny + Math.sign(dy) * r;
    if (!blockedAt(map, p.x - r, edge) && !blockedAt(map, p.x + r, edge)) p.y = ny;
  }
}

export function updatePlayer(
  p: Player,
  map: TileMap,
  field: NoiseField,
  input: { up: boolean; down: boolean; left: boolean; right: boolean; sprint: boolean },
  dt: number,
): void {
  let dx = (input.right ? 1 : 0) - (input.left ? 1 : 0);
  let dy = (input.down ? 1 : 0) - (input.up ? 1 : 0);

  if (p.shoutFlash > 0) p.shoutFlash--;

  const moving = dx !== 0 || dy !== 0;
  p.sprinting = input.sprint && moving;

  if (moving) {
    const len = Math.hypot(dx, dy);
    dx /= len;
    dy /= len;
    const speed = (p.sprinting ? SPRINT_SPEED : WALK_SPEED) * dt;
    move(map, p, dx * speed, dy * speed);

    if (p.stepCooldown <= 0) {
      field.emit(p.x, p.y, p.sprinting ? NOISE_SPRINT : NOISE_WALK);
      p.stepCooldown = p.sprinting ? 4 : 8;
    } else {
      p.stepCooldown--;
    }
  } else {
    p.stepCooldown = 0;
  }
}

export function shout(p: Player, field: NoiseField): void {
  field.emit(p.x, p.y, NOISE_SHOUT);
  p.shoutFlash = 12;
}

export function tileOf(p: Player): { tx: number; ty: number } {
  return { tx: Math.floor(p.x / TILE), ty: Math.floor(p.y / TILE) };
}
