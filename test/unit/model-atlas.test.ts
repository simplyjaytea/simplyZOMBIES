import { describe, expect, it } from "vitest";
import {
  cellOrigin,
  ModelSprites,
  type ModelAtlas,
  type ModelAtlasSource,
} from "../../src/render/sprites/atlas";
import { cellMetrics } from "../../src/render/sprites/humanoid";
import {
  Archetype,
  ARCHETYPES,
  FRAMES_PER_ARCHETYPE,
  OCTANTS,
  POSE_FRAMES,
  POSES,
} from "../../src/render/sprites/pose";
import { archetypeFor } from "../../src/render/sprites/archetypes";
import { boot } from "../../src/sim/boot";
import { Position } from "../../src/sim/kernel/components";
import { Controlled } from "../../src/sim/modules/player";
import { Shambler } from "../../src/sim/modules/shambler";

const ZOOM = 28;
const CELL = cellMetrics(ZOOM);

/** The grid the procedural source builds, without a canvas to build it on. */
const GRID: Pick<ModelAtlas, "cellWidth" | "cellHeight" | "columns"> = {
  cellWidth: CELL.width,
  cellHeight: CELL.height,
  columns: OCTANTS,
};

describe("cellOrigin", () => {
  it("gives every cell its own rectangle", () => {
    // An off-by-one here reads a neighbouring frame, which presents as an animation glitch
    // rather than as a bug in a lookup -- so it gets a test rather than a careful read.
    const seen = new Set<string>();
    for (const pose of POSES) {
      for (let frame = 0; frame < (POSE_FRAMES[pose] as number); frame++) {
        for (let octant = 0; octant < OCTANTS; octant++) {
          const { sx, sy } = cellOrigin(GRID, pose, frame, octant);
          seen.add(`${sx},${sy}`);
        }
      }
    }
    expect(seen.size).toBe(FRAMES_PER_ARCHETYPE * OCTANTS);
  });

  it("keeps every cell inside the sheet it was cut from", () => {
    const width = CELL.width * OCTANTS;
    const height = CELL.height * FRAMES_PER_ARCHETYPE;
    for (const pose of POSES) {
      for (let frame = 0; frame < (POSE_FRAMES[pose] as number); frame++) {
        for (let octant = 0; octant < OCTANTS; octant++) {
          const { sx, sy } = cellOrigin(GRID, pose, frame, octant);
          expect(sx).toBeGreaterThanOrEqual(0);
          expect(sy).toBeGreaterThanOrEqual(0);
          expect(sx + CELL.width).toBeLessThanOrEqual(width);
          expect(sy + CELL.height).toBeLessThanOrEqual(height);
        }
      }
    }
  });

  it("lays octants across and frames down", () => {
    const a = cellOrigin(GRID, POSES[1] as number, 0, 0);
    const b = cellOrigin(GRID, POSES[1] as number, 0, 1);
    const c = cellOrigin(GRID, POSES[1] as number, 1, 0);
    expect(b.sy).toBe(a.sy);
    expect(b.sx).toBe(a.sx + CELL.width);
    expect(c.sx).toBe(a.sx);
    expect(c.sy).toBe(a.sy + CELL.height);
  });
});

describe("ModelSprites", () => {
  /** A source that counts builds instead of rasterising. The seam, exercised. */
  function countingSource(): ModelAtlasSource & { builds: number; glimpses: number } {
    const atlas: ModelAtlas = {
      image: null as unknown as CanvasImageSource,
      ...GRID,
      anchorX: 0,
      anchorY: 0,
    };
    return {
      builds: 0,
      glimpses: 0,
      build(): ModelAtlas {
        this.builds++;
        return atlas;
      },
      buildGlimpse(): ModelAtlas {
        this.glimpses++;
        return atlas;
      },
    };
  }

  it("builds every sheet once, eagerly", () => {
    // Eagerly rather than lazily: building a sheet the first time a survivor walks on screen
    // would be a single-frame spike mid-play, to save memory that is noise against the tile layer.
    const source = countingSource();
    const sprites = new ModelSprites(source);
    sprites.atlasFor(Archetype.Player, ZOOM);
    expect(source.builds).toBe(ARCHETYPES.length);
  });

  it("does not rebuild while the zoom holds", () => {
    const source = countingSource();
    const sprites = new ModelSprites(source);
    for (let i = 0; i < 100; i++) {
      for (const archetype of ARCHETYPES) sprites.atlasFor(archetype, ZOOM);
    }
    expect(source.builds).toBe(ARCHETYPES.length);
  });

  it("rebuilds when the zoom changes, the way the occluder sprites do", () => {
    const source = countingSource();
    const sprites = new ModelSprites(source);
    sprites.atlasFor(Archetype.Player, ZOOM);
    sprites.atlasFor(Archetype.Player, ZOOM * 2);
    expect(source.builds).toBe(ARCHETYPES.length * 2);
  });

  it("caches a glimpse per colour, so nothing tints in the hot loop", () => {
    const source = countingSource();
    const sprites = new ModelSprites(source);
    sprites.glimpse("#4a5a48", ZOOM);
    sprites.glimpse("#4a5a48", ZOOM);
    sprites.glimpse("#3d4a3c", ZOOM);
    expect(source.glimpses).toBe(2);
  });

  it("drops its glimpses when the zoom changes, or they would blit at the wrong size", () => {
    const source = countingSource();
    const sprites = new ModelSprites(source);
    sprites.glimpse("#4a5a48", ZOOM);
    sprites.glimpse("#4a5a48", ZOOM * 2);
    expect(source.glimpses).toBe(2);
  });

  it("takes a different source without the renderer knowing", () => {
    // The seam. A PNG-backed atlas satisfies this interface unchanged, which is the whole of
    // "room to change later".
    const source = countingSource();
    const sprites = new ModelSprites(source);
    expect(sprites.atlasFor(Archetype.Zombie, ZOOM).columns).toBe(OCTANTS);
  });
});

describe("archetypeFor", () => {
  it("draws the controlled body as the player", () => {
    const { world } = boot({ seed: 7, wanderers: 4 });
    let found = false;
    for (const entity of world.components.query(Position, Controlled)) {
      expect(archetypeFor(world, entity)).toBe(Archetype.Player);
      found = true;
    }
    expect(found).toBe(true);
  });

  it("draws every shambler as a zombie", () => {
    const { world } = boot({ seed: 7, wanderers: 12 });
    let counted = 0;
    for (const entity of world.components.query(Position, Shambler)) {
      expect(archetypeFor(world, entity)).toBe(Archetype.Zombie);
      counted++;
    }
    expect(counted).toBe(12);
  });

  it("classifies every body in a booted world, and none of them as a survivor yet", () => {
    // Survivors are Milestone 2. The branch exists so that the day they spawn they are people
    // rather than whatever the fallback happened to be -- but nothing should reach it today,
    // and if something does, this is where that gets noticed.
    const { world } = boot({ seed: 3, wanderers: 40 });
    const counts = new Map<Archetype, number>();
    for (const entity of world.components.query(Position)) {
      const archetype = archetypeFor(world, entity);
      counts.set(archetype, (counts.get(archetype) ?? 0) + 1);
    }
    expect(counts.get(Archetype.Player)).toBe(1);
    expect(counts.get(Archetype.Zombie)).toBe(40);
    expect(counts.get(Archetype.Survivor)).toBeUndefined();
  });

  it("falls back to a survivor, not to a zombie", () => {
    // The failure modes are not symmetric: a survivor drawn as a shambler is a body the player
    // will swing at, and the fairness rules do not tolerate the screen lying about which of
    // those a thing is. This is the NPC hook, exercised on a body the simulation does not have
    // a component for yet.
    const { world } = boot({ seed: 5, wanderers: 1 });
    const stranger = world.spawn();
    world.components.set(stranger, Position, { x: 4, y: 4 });
    expect(archetypeFor(world, stranger)).toBe(Archetype.Survivor);
  });
});
