// Uniform spatial hash over entity positions.
//
// docs/22-performance.md#spatial-partitioning. Its first customer is the horde -- a zombie
// investigating a noise needs to know what is next to it, and asking "which of the other
// 2,000 entities are within two metres" by scanning them all is the quadratic cost that
// makes crowd behaviour unaffordable. Combat and render culling take the same queries later.
//
// A uniform grid rather than a quadtree because docs/22 says so and the reason is sound:
// entity density here is roughly uniform over a district, and a grid rebuild is a linear
// pass with no allocation, whereas a tree spends its time rebalancing around a crowd that
// moves every tick.

import { Position } from "./components";
import { entityIndex, type EntityId } from "./entities";
import type { World } from "./world";

/**
 * Cell size in metres.
 *
 * Sized for the queries that dominate: melee reach and body separation, both about a metre.
 * Bigger cells mean scanning neighbours that were never close; smaller ones mean touching
 * more cells per query for the same answer.
 */
export const HASH_CELL_METRES = 4;

export class SpatialHash {
  private readonly cells = new Map<number, EntityId[]>();
  private readonly w: number;
  private readonly h: number;

  constructor(mapWidthMetres: number, mapHeightMetres: number) {
    this.w = Math.max(1, Math.ceil(mapWidthMetres / HASH_CELL_METRES));
    this.h = Math.max(1, Math.ceil(mapHeightMetres / HASH_CELL_METRES));
  }

  private key(x: number, y: number): number {
    const cx = Math.min(this.w - 1, Math.max(0, Math.floor(x / HASH_CELL_METRES)));
    const cy = Math.min(this.h - 1, Math.max(0, Math.floor(y / HASH_CELL_METRES)));
    return cy * this.w + cx;
  }

  clear(): void {
    this.cells.clear();
  }

  insert(entity: EntityId, x: number, y: number): void {
    const k = this.key(x, y);
    const bucket = this.cells.get(k);
    if (bucket === undefined) this.cells.set(k, [entity]);
    else bucket.push(entity);
  }

  /** Rebuild from every entity carrying a Position. One linear pass, no allocation per entity. */
  rebuild(world: World): void {
    this.clear();
    for (const entity of world.components.query(Position)) {
      const pos = world.components.getOrThrow(entity, Position);
      this.insert(entity, pos.x, pos.y);
    }
  }

  /**
   * Entities within `radius` metres of a point, **in ascending entity order**.
   *
   * The sort is the same determinism requirement as `ComponentStore.query`, and for the
   * same reason: bucket contents are in insertion order, insertion order reflects the
   * particular history of spawns and moves that produced it, and a reloaded save rebuilds
   * that history differently. Any system whose behaviour depends on which neighbour it
   * meets first would then diverge -- and "which neighbour do I grab" is exactly the kind
   * of decision the horde is about to start making.
   */
  near(x: number, y: number, radius: number): EntityId[] {
    const out: EntityId[] = [];
    const r = Math.max(0, radius);
    const minX = Math.max(0, Math.floor((x - r) / HASH_CELL_METRES));
    const maxX = Math.min(this.w - 1, Math.floor((x + r) / HASH_CELL_METRES));
    const minY = Math.max(0, Math.floor((y - r) / HASH_CELL_METRES));
    const maxY = Math.min(this.h - 1, Math.floor((y + r) / HASH_CELL_METRES));

    for (let cy = minY; cy <= maxY; cy++) {
      for (let cx = minX; cx <= maxX; cx++) {
        const bucket = this.cells.get(cy * this.w + cx);
        if (bucket === undefined) continue;
        for (const entity of bucket) out.push(entity);
      }
    }

    out.sort((a, b) => entityIndex(a) - entityIndex(b));
    return out;
  }

  /** Like `near`, but excludes entities outside the exact radius rather than the cells. */
  withinRadius(world: World, x: number, y: number, radius: number): EntityId[] {
    const r2 = radius * radius;
    return this.near(x, y, radius).filter((entity) => {
      const pos = world.components.get(entity, Position);
      if (pos === undefined) return false;
      const dx = pos.x - x;
      const dy = pos.y - y;
      return dx * dx + dy * dy <= r2;
    });
  }

  get cellCount(): number {
    return this.cells.size;
  }
}
