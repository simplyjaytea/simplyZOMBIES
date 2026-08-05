// Hand-built district. No content pipeline, no generation rules — this is a spike.

export const MAP_W = 80;
export const MAP_H = 80;
export const TILE = 12;

export const FLOOR = 0;
export const WALL = 1;

export type TileMap = {
  w: number;
  h: number;
  tiles: Uint8Array;
};

function set(m: TileMap, x: number, y: number, v: number): void {
  if (x < 0 || y < 0 || x >= m.w || y >= m.h) return;
  m.tiles[y * m.w + x] = v;
}

/** Hollow rectangle with a door gap on one side. */
function building(m: TileMap, x: number, y: number, w: number, h: number, doorSide: 0 | 1 | 2 | 3): void {
  for (let i = 0; i < w; i++) {
    set(m, x + i, y, WALL);
    set(m, x + i, y + h - 1, WALL);
  }
  for (let j = 0; j < h; j++) {
    set(m, x, y + j, WALL);
    set(m, x + w - 1, y + j, WALL);
  }
  const midX = x + (w >> 1);
  const midY = y + (h >> 1);
  if (doorSide === 0) { set(m, midX, y, FLOOR); set(m, midX + 1, y, FLOOR); }
  if (doorSide === 1) { set(m, x + w - 1, midY, FLOOR); set(m, x + w - 1, midY + 1, FLOOR); }
  if (doorSide === 2) { set(m, midX, y + h - 1, FLOOR); set(m, midX + 1, y + h - 1, FLOOR); }
  if (doorSide === 3) { set(m, x, midY, FLOOR); set(m, x, midY + 1, FLOOR); }
}

export function createMap(): TileMap {
  const m: TileMap = { w: MAP_W, h: MAP_H, tiles: new Uint8Array(MAP_W * MAP_H) };

  // Perimeter
  for (let x = 0; x < MAP_W; x++) { set(m, x, 0, WALL); set(m, x, MAP_H - 1, WALL); }
  for (let y = 0; y < MAP_H; y++) { set(m, 0, y, WALL); set(m, MAP_W - 1, y, WALL); }

  // A block of buildings, leaving streets between them.
  building(m, 8, 8, 16, 12, 2);
  building(m, 30, 8, 14, 12, 2);
  building(m, 52, 6, 18, 16, 3);

  building(m, 6, 30, 13, 14, 1);
  building(m, 26, 28, 20, 18, 0);   // the big one — good for hiding in
  building(m, 54, 30, 16, 12, 3);

  building(m, 10, 54, 18, 14, 0);
  building(m, 36, 56, 12, 12, 0);
  building(m, 56, 52, 16, 18, 3);

  // A couple of free-standing wall runs to break sightlines and block noise
  for (let i = 0; i < 14; i++) set(m, 24 + i, 24, WALL);
  for (let i = 0; i < 10; i++) set(m, 48, 44 + i, WALL);

  return m;
}

export function isWall(m: TileMap, tx: number, ty: number): boolean {
  if (tx < 0 || ty < 0 || tx >= m.w || ty >= m.h) return true;
  return m.tiles[ty * m.w + tx] === WALL;
}

/** World-space collision against the tile grid. */
export function blockedAt(m: TileMap, wx: number, wy: number): boolean {
  return isWall(m, Math.floor(wx / TILE), Math.floor(wy / TILE));
}
