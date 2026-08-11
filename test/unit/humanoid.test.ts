import { describe, expect, it } from "vitest";
import {
  BODY_SPECS,
  cellMetrics,
  drawHumanoid,
  drawSilhouette,
  type ShapeSink,
} from "../../src/render/sprites/humanoid";
import { ARCHETYPES, Archetype, OCTANTS, POSE_FRAMES, POSES } from "../../src/render/sprites/pose";

/**
 * A canvas that records instead of drawing.
 *
 * The reason `drawHumanoid` takes a structural sink at all. Vitest runs in node with no DOM, and
 * reviewing 336 procedurally generated sprites by walking around the district is not a review --
 * so the sheet gets checked here, exhaustively, for the three ways generated art goes wrong:
 * it bleeds into the neighbouring cell, it contains a NaN that silently draws nothing, or it
 * floats off its own feet.
 */
class Recorder implements ShapeSink {
  fillStyle: string | CanvasGradient | CanvasPattern = "";
  readonly xs: number[] = [];
  readonly ys: number[] = [];
  readonly ops: string[] = [];

  private mark(x: number, y: number): void {
    this.xs.push(x);
    this.ys.push(y);
  }

  beginPath(): void {
    this.ops.push("beginPath");
  }
  moveTo(x: number, y: number): void {
    this.ops.push(`moveTo:${x.toFixed(3)},${y.toFixed(3)}`);
    this.mark(x, y);
  }
  lineTo(x: number, y: number): void {
    this.ops.push(`lineTo:${x.toFixed(3)},${y.toFixed(3)}`);
    this.mark(x, y);
  }
  closePath(): void {
    this.ops.push("closePath");
  }
  fill(): void {
    this.ops.push(`fill:${String(this.fillStyle)}`);
  }
  ellipse(x: number, y: number, rx: number, ry: number): void {
    this.ops.push(`ellipse:${x.toFixed(3)},${y.toFixed(3)},${rx.toFixed(3)},${ry.toFixed(3)}`);
    // An ellipse's extent, not its centre -- that is what has to fit in the cell.
    this.mark(x - rx, y - ry);
    this.mark(x + rx, y + ry);
  }
  save(): void {
    this.ops.push("save");
  }
  restore(): void {
    this.ops.push("restore");
  }

  get finite(): boolean {
    return (
      this.xs.every((v) => Number.isFinite(v)) &&
      this.ys.every((v) => Number.isFinite(v)) &&
      !this.ops.some((op) => op.includes("NaN"))
    );
  }
}

const ZOOM = 28;
const CELL = cellMetrics(ZOOM);

/** Every cell on every sheet: archetype x pose x frame x octant. */
function everyCell(): { archetype: Archetype; pose: number; frame: number; octant: number }[] {
  const cells = [];
  for (const archetype of ARCHETYPES) {
    for (const pose of POSES) {
      for (let frame = 0; frame < (POSE_FRAMES[pose] as number); frame++) {
        for (let octant = 0; octant < OCTANTS; octant++) {
          cells.push({ archetype, pose, frame, octant });
        }
      }
    }
  }
  return cells;
}

function render(archetype: Archetype, pose: number, frame: number, octant: number): Recorder {
  const sink = new Recorder();
  drawHumanoid(sink, BODY_SPECS[archetype], pose, frame, octant, ZOOM, CELL.anchorX, CELL.anchorY);
  return sink;
}

describe("the sheet", () => {
  it("covers 336 cells", () => {
    // 3 archetypes x 14 frames x 8 octants. If this number moves, the atlas geometry and the
    // memory estimate in the plan move with it.
    expect(everyCell().length).toBe(336);
  });

  it("draws every cell inside its own box", () => {
    // Sprite bleed into a neighbouring cell is the characteristic atlas bug, and it is invisible
    // until two frames happen to be adjacent on screen. One loop catches all of it.
    const bleeding: string[] = [];
    for (const cell of everyCell()) {
      const sink = render(cell.archetype, cell.pose, cell.frame, cell.octant);
      const minX = Math.min(...sink.xs);
      const maxX = Math.max(...sink.xs);
      const minY = Math.min(...sink.ys);
      const maxY = Math.max(...sink.ys);
      if (minX < 0 || maxX > CELL.width || minY < 0 || maxY > CELL.height) {
        bleeding.push(
          `a${cell.archetype} p${cell.pose} f${cell.frame} o${cell.octant}: ` +
            `x[${minX.toFixed(1)}, ${maxX.toFixed(1)}] y[${minY.toFixed(1)}, ${maxY.toFixed(1)}] ` +
            `box ${CELL.width}x${CELL.height}`,
        );
      }
    }
    expect(bleeding).toEqual([]);
  });

  it("produces no NaN anywhere", () => {
    // Angle arithmetic over eight octants and seven poses will reach one eventually, and a NaN
    // in a path draws nothing at all rather than throwing -- so it would ship as an invisible
    // body rather than as a crash.
    for (const cell of everyCell()) {
      const sink = render(cell.archetype, cell.pose, cell.frame, cell.octant);
      expect(sink.finite, `a${cell.archetype} p${cell.pose} f${cell.frame} o${cell.octant}`).toBe(
        true,
      );
    }
  });

  it("actually draws something in every cell", () => {
    for (const cell of everyCell()) {
      const sink = render(cell.archetype, cell.pose, cell.frame, cell.octant);
      expect(sink.ops.filter((op) => op.startsWith("fill:")).length).toBeGreaterThan(2);
    }
  });

  it("stands every body on its own feet", () => {
    // The anchor is the contract with the renderer: it blits at (screenY - anchorY), so a body
    // whose lowest ink is well above the anchor hovers and one below it sinks into the ground.
    for (const cell of everyCell()) {
      const sink = render(cell.archetype, cell.pose, cell.frame, cell.octant);
      const lowest = Math.max(...sink.ys);
      expect(lowest).toBeGreaterThan(CELL.anchorY - 2);
      expect(lowest).toBeLessThanOrEqual(CELL.height);
    }
  });

  it("puts a contact shadow under every body", () => {
    // Without it a foot-anchored sprite floats, which is the characteristic failure of standing
    // sprites over an isometric ground.
    for (const cell of everyCell()) {
      const sink = render(cell.archetype, cell.pose, cell.frame, cell.octant);
      expect(sink.ops.some((op) => op.startsWith("fill:rgba(0, 0, 0,"))).toBe(true);
    }
  });
});

describe("the archetypes are actually distinguishable", () => {
  it("draws a zombie differently from a survivor in every pose", () => {
    // Both are humanoids from the same code path, so "they differ" is a real risk of being
    // accidentally false -- which would make the one cue a player has at night no cue at all.
    for (const pose of POSES) {
      const zombie = render(Archetype.Zombie, pose, 0, 0).ops.join("|");
      const survivor = render(Archetype.Survivor, pose, 0, 0).ops.join("|");
      expect(zombie, `pose ${pose}`).not.toBe(survivor);
    }
  });

  it("stoops a zombie and stands a survivor upright", () => {
    // The single most load-bearing number in the file: it is the cue that still reads once the
    // night wash has taken the colour.
    expect(BODY_SPECS[Archetype.Zombie].stoop).toBeGreaterThan(0.2);
    expect(BODY_SPECS[Archetype.Player].stoop).toBe(0);
    expect(BODY_SPECS[Archetype.Zombie].armsForward).toBe(true);
    expect(BODY_SPECS[Archetype.Player].armsForward).toBe(false);
  });

  it("gives the player the lightest colour, so they survive the night wash", () => {
    const luminance = (hex: string): number => {
      const n = parseInt(hex.slice(1), 16);
      return ((n >> 16) & 255) * 0.299 + ((n >> 8) & 255) * 0.587 + (n & 255) * 0.114;
    };
    expect(luminance(BODY_SPECS[Archetype.Player].colour)).toBeGreaterThan(
      luminance(BODY_SPECS[Archetype.Survivor].colour),
    );
    expect(luminance(BODY_SPECS[Archetype.Survivor].colour)).toBeGreaterThan(
      luminance(BODY_SPECS[Archetype.Zombie].colour),
    );
  });

  it("turns a body: the eight octants draw eight different shapes", () => {
    for (const archetype of ARCHETYPES) {
      const shapes = new Set<string>();
      for (let octant = 0; octant < OCTANTS; octant++) {
        shapes.add(render(archetype, 1 /* Walk */, 1, octant).ops.join("|"));
      }
      expect(shapes.size, `archetype ${archetype}`).toBe(OCTANTS);
    }
  });

  it("moves the feet through a walk cycle", () => {
    const frames = new Set<string>();
    for (let frame = 0; frame < 4; frame++) {
      frames.add(render(Archetype.Player, 1 /* Walk */, frame, 0).ops.join("|"));
    }
    // Frames 0 and 2 are both passing positions, so three distinct shapes is correct.
    expect(frames.size).toBe(3);
  });
});

describe("the anonymous silhouette", () => {
  it("is the same shape whatever it is standing in for", () => {
    // docs/28: the peripheral arc notices movement and withholds identity. A silhouette that
    // differed by archetype would hand that identity over by outline alone.
    const sink = new Recorder();
    drawSilhouette(sink, "#4a5a48", ZOOM, CELL.anchorX, CELL.anchorY);
    const other = new Recorder();
    drawSilhouette(other, "#3d4a3c", ZOOM, CELL.anchorX, CELL.anchorY);
    const shapeOnly = (r: Recorder): string =>
      r.ops.filter((op) => !op.startsWith("fill:")).join("|");
    expect(shapeOnly(sink)).toBe(shapeOnly(other));
  });

  it("has no posture, no limbs and no head notch to read identity from", () => {
    const sink = new Recorder();
    drawSilhouette(sink, "#4a5a48", ZOOM, CELL.anchorX, CELL.anchorY);
    // Shadow, trunk, head. Anything more is a cue the arc did not earn.
    expect(sink.ops.filter((op) => op.startsWith("fill:")).length).toBe(3);
  });

  it("fits its cell and stands on its feet", () => {
    const sink = new Recorder();
    drawSilhouette(sink, "#4a5a48", ZOOM, CELL.anchorX, CELL.anchorY);
    expect(Math.min(...sink.xs)).toBeGreaterThanOrEqual(0);
    expect(Math.max(...sink.xs)).toBeLessThanOrEqual(CELL.width);
    expect(Math.min(...sink.ys)).toBeGreaterThanOrEqual(0);
    expect(Math.max(...sink.ys)).toBeLessThanOrEqual(CELL.height);
    expect(sink.finite).toBe(true);
  });

  it("is person-sized, because that much is honest", () => {
    const sink = new Recorder();
    drawSilhouette(sink, "#4a5a48", ZOOM, CELL.anchorX, CELL.anchorY);
    const height = CELL.anchorY - Math.min(...sink.ys);
    const standing = render(Archetype.Player, 0, 0, 0);
    const playerHeight = CELL.anchorY - Math.min(...standing.ys);
    expect(height).toBeGreaterThan(playerHeight * 0.75);
    expect(height).toBeLessThan(playerHeight * 1.1);
  });
});

describe("cellMetrics", () => {
  it("is one tile wide, so a body and a wall cost the same footprint", () => {
    expect(cellMetrics(28).width).toBe(56);
  });

  it("leaves headroom above the tallest body for the wind-up", () => {
    const tallest = Math.max(...Object.values(BODY_SPECS).map((s) => s.heightMetres));
    expect(cellMetrics(28).anchorY).toBeGreaterThan(tallest * 28 * 0.62);
  });

  it("leaves room below the feet for the contact shadow", () => {
    const cell = cellMetrics(28);
    expect(cell.height).toBeGreaterThan(cell.anchorY);
  });

  it("scales with zoom", () => {
    expect(cellMetrics(56).width).toBe(2 * cellMetrics(28).width);
  });
});
