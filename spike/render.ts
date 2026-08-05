import { FIELD_SCALE, type NoiseField } from "./field";
import { isWall, MAP_H, MAP_W, TILE, type TileMap } from "./map";
import type { Player } from "./player";
import { ZState, type Horde } from "./zombies";

export type Camera = { x: number; y: number; w: number; h: number };

export function updateCamera(cam: Camera, p: Player, viewW: number, viewH: number): void {
  cam.w = viewW;
  cam.h = viewH;
  const worldW = MAP_W * TILE;
  const worldH = MAP_H * TILE;
  cam.x = Math.min(Math.max(p.x - viewW / 2, 0), Math.max(0, worldW - viewW));
  cam.y = Math.min(Math.max(p.y - viewH / 2, 0), Math.max(0, worldH - viewH));
}

export function drawWorld(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  map: TileMap,
  field: NoiseField,
  horde: Horde,
  player: Player,
  showOverlay: boolean,
): void {
  ctx.fillStyle = "#0a0a0c";
  ctx.fillRect(0, 0, cam.w, cam.h);

  ctx.save();
  ctx.translate(-Math.round(cam.x), -Math.round(cam.y));

  const t0x = Math.max(0, Math.floor(cam.x / TILE));
  const t0y = Math.max(0, Math.floor(cam.y / TILE));
  const t1x = Math.min(MAP_W - 1, Math.ceil((cam.x + cam.w) / TILE));
  const t1y = Math.min(MAP_H - 1, Math.ceil((cam.y + cam.h) / TILE));

  // Tiles
  for (let ty = t0y; ty <= t1y; ty++) {
    for (let tx = t0x; tx <= t1x; tx++) {
      const wall = isWall(map, tx, ty);
      ctx.fillStyle = wall ? "#2b2b34" : "#141419";
      ctx.fillRect(tx * TILE, ty * TILE, TILE, TILE);
      if (!wall && ((tx + ty) & 7) === 0) {
        ctx.fillStyle = "#191920";
        ctx.fillRect(tx * TILE, ty * TILE, TILE, TILE);
      }
    }
  }

  // Noise field heat map. The whole point of the spike is that this is
  // normally invisible — question 1 is whether the game reads without it.
  if (showOverlay) {
    const cell = TILE * FIELD_SCALE;
    const f0x = Math.max(0, Math.floor(cam.x / cell));
    const f0y = Math.max(0, Math.floor(cam.y / cell));
    const f1x = Math.min(field.w - 1, Math.ceil((cam.x + cam.w) / cell));
    const f1y = Math.min(field.h - 1, Math.ceil((cam.y + cam.h) / cell));

    for (let fy = f0y; fy <= f1y; fy++) {
      for (let fx = f0x; fx <= f1x; fx++) {
        const v = field.values[fy * field.w + fx];
        if (v <= 0) continue;
        const t = Math.min(1, v / 90);
        const r = Math.round(90 + t * 165);
        const g = Math.round(40 + (1 - t) * 60);
        const b = Math.round(120 - t * 90);
        ctx.fillStyle = `rgba(${r},${g},${b},${0.14 + t * 0.42})`;
        ctx.fillRect(fx * cell, fy * cell, cell, cell);
      }
    }
  }

  // Zombies
  for (const z of horde.zombies) {
    if (z.x < cam.x - 20 || z.y < cam.y - 20 || z.x > cam.x + cam.w + 20 || z.y > cam.y + cam.h + 20) continue;
    ctx.fillStyle =
      z.state === ZState.Seek ? "#d8574a" :
      z.state === ZState.Investigate ? "#d8a04a" :
      "#5d7a5d";
    ctx.beginPath();
    ctx.arc(z.x, z.y, 3.6, 0, Math.PI * 2);
    ctx.fill();
  }

  // Player
  if (player.shoutFlash > 0) {
    const t = player.shoutFlash / 12;
    ctx.strokeStyle = `rgba(255,220,140,${t * 0.8})`;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(player.x, player.y, (1 - t) * 90 + 8, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.fillStyle = player.sprinting ? "#ffd98a" : "#eaeaf2";
  ctx.beginPath();
  ctx.arc(player.x, player.y, 4.4, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}
