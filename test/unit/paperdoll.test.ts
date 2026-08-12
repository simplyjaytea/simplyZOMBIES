// The condition view's arithmetic, and the ban it exists to enforce.
//
// docs/05-health-injury.md#the-condition-view names what it forbids: "percentages, hit points,
// segmented pips, a fill level of any kind, and tooltips carrying numbers the screen itself does
// not show". A prohibition in a document is a comment. These tests are the mechanism.
//
// Canvas-free, the same way `pose.test.ts` is: `drawPaperdoll` takes the structural sink, so the
// figure can be recorded and asserted in node.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { SURVIVOR_BODY, SURVIVOR_BODY_PARTS, ZOMBIE_BODY } from "../../src/sim/combat";
import { Position } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { step } from "../../src/sim/kernel/step";
import { conditionView } from "../../src/sim/condition";
import { Body, PartState, maxOf, partState } from "../../src/sim/modules/health";
import { Posture } from "../../src/sim/modules/stance";
import { Shambler } from "../../src/sim/modules/shambler";
import { Stance, STANCES, stanceSpec } from "../../src/sim/stances";
import { CONDITION_TINTS, COLOURS } from "../../src/render/palette";
import { drawPaperdoll, isNotable, poseForStance, tintFor } from "../../src/render/paperdoll";
import {
  OUTLINE_POSES,
  OutlinePose,
  outlineMetrics,
  type StrokeSink,
} from "../../src/render/sprites/outline";

const SEED = 20260812;

/** The figure's size in the assertions below. Arbitrary, and large enough to read fractions off. */
const HEIGHT = 168;

function survivor(): { world: ReturnType<typeof boot>["world"]; who: EntityId } {
  const { world, player } = boot({ seed: SEED, wanderers: 0 });
  step(world);
  return { world, who: player as EntityId };
}

/**
 * A sink that records the ink, so a figure can be asserted without a canvas.
 *
 * Strokes as well as fills, because the outline is line art: an unhurt body produces strokes and
 * *no* fills at all, which is a thing worth being able to assert rather than infer.
 */
class Recorder implements StrokeSink {
  fillStyle: string | CanvasGradient | CanvasPattern = "";
  strokeStyle: string | CanvasGradient | CanvasPattern = "";
  lineWidth = 0;
  lineJoin: CanvasLineJoin = "miter";
  readonly fills: string[] = [];
  readonly strokes: string[] = [];
  readonly xs: number[] = [];
  readonly ys: number[] = [];

  beginPath(): void {}
  closePath(): void {}
  save(): void {}
  restore(): void {}
  moveTo(x: number, y: number): void {
    this.xs.push(x);
    this.ys.push(y);
  }
  lineTo(x: number, y: number): void {
    this.xs.push(x);
    this.ys.push(y);
  }
  ellipse(x: number, y: number, rx: number, ry: number): void {
    this.xs.push(x - rx, x + rx);
    this.ys.push(y - ry, y + ry);
  }
  fill(): void {
    this.fills.push(String(this.fillStyle));
  }
  stroke(): void {
    this.strokes.push(String(this.strokeStyle));
  }
}

/** Draw one survivor at one anchor and hand back what came out. */
function record(
  world: ReturnType<typeof boot>["world"],
  who: EntityId,
  anchorX = 200,
  anchorY = 200,
): Recorder {
  const view = conditionView(world, who);
  const sink = new Recorder();
  drawPaperdoll(sink, view as NonNullable<typeof view>, { height: HEIGHT, anchorX, anchorY });
  return sink;
}

describe("the four states are derived in one place", () => {
  it("reads unhurt only at full, and unusable only at zero", () => {
    const body: Body = { ...SURVIVOR_BODY };
    expect(partState(body, "legs")).toBe(PartState.Unhurt);

    body.legs = SURVIVOR_BODY.legs - 0.001;
    expect(partState(body, "legs")).toBe(PartState.Hurt);

    body.legs = SURVIVOR_BODY.legs * 0.25;
    expect(partState(body, "legs")).toBe(PartState.BadlyHurt);

    // Only at zero, and that boundary is load-bearing: `Unusable` is what makes docs/05's
    // crawler and a hand that cannot hold anything the same state, so a limb at 1 hit point has
    // to still be a limb.
    body.legs = 0.5;
    expect(partState(body, "legs")).toBe(PartState.BadlyHurt);
    body.legs = 0;
    expect(partState(body, "legs")).toBe(PartState.Unusable);
  });

  it("has no state for a part the body does not have", () => {
    // A shambler has three parts. Answering `Unhurt` for its hands would put a healthy hand on a
    // body that has none, and the paperdoll would draw it.
    const zombie: Body = { ...ZOMBIE_BODY };
    expect(partState(zombie, "hands")).toBeUndefined();
    expect(maxOf(zombie, "hands")).toBeUndefined();
    expect(partState(zombie, "legs")).toBe(PartState.Unhurt);
  });

  it("finds the right maximum for each kind of body", () => {
    expect(maxOf({ ...SURVIVOR_BODY }, "torso")).toBe(SURVIVOR_BODY.torso);
    expect(maxOf({ ...ZOMBIE_BODY }, "torso")).toBe(ZOMBIE_BODY.torso);
  });
});

describe("the snapshot carries no numbers", () => {
  it("has a state and a sentence per part, and nothing measurable", () => {
    // **The ban, made mechanical.** Serialise the whole view and assert that no integrity value
    // appears anywhere in it -- so a future field carrying "40" for the torso fails here rather
    // than turning up as a bar six months later.
    const { world, who } = survivor();
    const view = conditionView(world, who);
    expect(view).not.toBeNull();

    const json = JSON.stringify(view);
    for (const [part, max] of Object.entries(SURVIVOR_BODY)) {
      expect(json, `${part}'s maximum leaked into the snapshot`).not.toContain(`:${max}`);
    }
    // And no fraction, which is the other shape a fill would arrive in.
    expect(json).not.toMatch(/0\.\d+/);
  });

  it("lists exactly docs/05's six parts, in the declared order", () => {
    const { world, who } = survivor();
    const view = conditionView(world, who);
    expect(view?.parts.map((p) => p.part)).toEqual([...SURVIVOR_BODY_PARTS]);
  });

  it("gives every part a non-empty sentence in every state", () => {
    // A missing string would render as an empty line beside a tinted limb, which reads as a bug
    // rather than as uncertainty.
    const { world, who } = survivor();
    const body = world.components.getOrThrow(who, Body);
    for (const part of SURVIVOR_BODY_PARTS) {
      for (const fraction of [1, 0.8, 0.2, 0]) {
        body[part] = (SURVIVOR_BODY[part] as number) * fraction;
        const view = conditionView(world, who);
        const found = view?.parts.find((p) => p.part === part);
        expect(found?.prose.length, `${part} at ${fraction}`).toBeGreaterThan(0);
      }
      body[part] = SURVIVOR_BODY[part] as number;
    }
  });

  it("refuses a body that is not a survivor's", () => {
    const { world } = boot({ seed: SEED, wanderers: 2 });
    const zombie = world.components.query(Position, Shambler)[0] as EntityId;
    expect(conditionView(world, zombie)).toBeNull();
  });

  it("reports the worst part, so the glimpse does not have to re-derive it", () => {
    const { world, who } = survivor();
    const body = world.components.getOrThrow(who, Body);
    expect(conditionView(world, who)?.worst).toBe(PartState.Unhurt);

    body.hands = 0;
    body.legs = SURVIVOR_BODY.legs * 0.8;
    expect(conditionView(world, who)?.worst).toBe(PartState.Unusable);
  });
});

describe("the paperdoll stands the way the survivor stands", () => {
  it("maps every rung to a shape, and the low rungs to a low body", () => {
    // The user-visible promise: standing shows it standing, crouching shows it crouching, prone
    // shows it prone. Asserted per rung rather than by example, so a rung added to the ladder
    // without a posture fails here.
    for (const stance of STANCES) {
      expect(OUTLINE_POSES, stanceSpec(stance).name).toContain(poseForStance(stance));
    }
    expect(poseForStance(Stance.Crawl)).toBe(OutlinePose.Prone);
    expect(poseForStance(Stance.Crouch)).toBe(OutlinePose.Crouch);
    expect(poseForStance(Stance.Walk)).toBe(OutlinePose.Stand);
    expect(poseForStance(Stance.Jog)).toBe(OutlinePose.Stand);
    expect(poseForStance(Stance.Sprint)).toBe(OutlinePose.Stand);
  });

  it("draws each posture lower than the one above it, and prone wider than tall", () => {
    // The posture has to be visible, not merely selected -- and on a front elevation it can be
    // asserted in the plain unit a player reads it in. This test used to compare prone by *shape*
    // rather than by height, because under the district's isometric camera a body lying away from
    // the viewer occupies up-screen pixels and a crawler's topmost ink sat above a crouch's. The
    // outline has no camera, so the obvious assertion is available again.
    const { world, who } = survivor();
    const profiles = new Map<Stance, { top: number; width: number }>();

    for (const stance of [Stance.Walk, Stance.Crouch, Stance.Crawl]) {
      world.components.getOrThrow(who, Posture).current = stance;
      const sink = record(world, who);
      profiles.set(stance, {
        top: 200 - Math.min(...sink.ys),
        width: Math.max(...sink.xs) - Math.min(...sink.xs),
      });
    }

    const standing = profiles.get(Stance.Walk) as { top: number; width: number };
    const crouched = profiles.get(Stance.Crouch) as { top: number; width: number };
    const prone = profiles.get(Stance.Crawl) as { top: number; width: number };

    expect(crouched.top).toBeLessThan(standing.top);
    expect(prone.top).toBeLessThan(crouched.top);
    // And it is lying down rather than merely short: a prone body is longer than it is tall, and
    // wider than a standing one, which is what separates this shape from a scaled-down figure.
    expect(prone.width).toBeGreaterThan(prone.top);
    expect(prone.width).toBeGreaterThan(standing.width);
  });

  it("keeps every posture inside the box the layout was measured against", () => {
    // The panel and the corner both reserve `outlineMetrics` and draw at its anchor. A pose that
    // out-reached that box would be clipped by the viewport in the corner and would overlap the
    // prose column on the panel -- the same guard `humanoid.test.ts` puts on the sprite sheet.
    const { world, who } = survivor();
    const box = outlineMetrics(HEIGHT);
    const anchorX = box.anchorX;
    const anchorY = box.anchorY;

    for (const stance of STANCES) {
      world.components.getOrThrow(who, Posture).current = stance;
      const sink = record(world, who, anchorX, anchorY);
      const name = stanceSpec(stance).name;

      expect(sink.xs.length, name).toBeGreaterThan(0);
      for (const x of sink.xs) {
        expect(Number.isFinite(x), `${name}: x`).toBe(true);
        expect(x, `${name}: x`).toBeGreaterThanOrEqual(0);
        expect(x, `${name}: x`).toBeLessThanOrEqual(box.width);
      }
      for (const y of sink.ys) {
        expect(Number.isFinite(y), `${name}: y`).toBe(true);
        expect(y, `${name}: y`).toBeGreaterThanOrEqual(0);
        expect(y, `${name}: y`).toBeLessThanOrEqual(box.height);
      }
    }
  });

  it("follows the same predicate as the sightline, so low is low in both", () => {
    // Cover that hides you also blinds you, and the figure agrees with both. If these two ever
    // disagreed, the paperdoll would be drawing a crouch the shadowcast does not believe in.
    for (const stance of STANCES) {
      const lowEye = stanceSpec(stance).eye === 1;
      const lowBody = poseForStance(stance) !== OutlinePose.Stand;
      expect(lowBody, stanceSpec(stance).name).toBe(lowEye);
    }
  });
});

describe("tint is colour and never fill", () => {
  it("tints nothing on an unhurt body", () => {
    // An unhurt survivor is bare line art -- so any colour on the figure means something, which is
    // what keeps the glimpse worth looking at.
    const { world, who } = survivor();
    const view = conditionView(world, who);
    expect(tintFor((view as NonNullable<typeof view>).parts)).toEqual({});
    expect(isNotable(view as NonNullable<typeof view>)).toBe(false);
  });

  it("draws an unhurt body as line and no fill at all", () => {
    // The strongest form of "colour, never fill": on a healthy survivor the figure produces no
    // fill operation of any kind, so there is nothing on screen for a fill *level* to grow out of.
    const { world, who } = survivor();
    const sink = record(world, who);
    expect(sink.fills).toEqual([]);
    expect(sink.strokes.length).toBeGreaterThan(0);
    expect(new Set(sink.strokes)).toEqual(new Set([COLOURS.outline]));
  });

  it("tints exactly the hurt parts, in the state's colour", () => {
    const { world, who } = survivor();
    const body = world.components.getOrThrow(who, Body);
    body.legs = 0;
    body.head = SURVIVOR_BODY.head * 0.8;

    const view = conditionView(world, who) as NonNullable<ReturnType<typeof conditionView>>;
    const tint = tintFor(view.parts);

    expect(Object.keys(tint).sort()).toEqual(["head", "legs"]);
    expect(tint.legs).toBe(CONDITION_TINTS[PartState.Unusable]);
    expect(tint.head).toBe(CONDITION_TINTS[PartState.Hurt]);
    expect(isNotable(view)).toBe(true);
  });

  it("puts the tint on the figure it was asked for, and on nothing else", () => {
    const { world, who } = survivor();
    world.components.getOrThrow(who, Body).legs = 0;

    const sink = record(world, who);
    expect(sink.fills).toContain(CONDITION_TINTS[PartState.Unusable]);
    // Exactly one condition colour on the body, because exactly one part is hurt. A figure that
    // filled a neighbouring region would be pointing at the wrong limb, which is the one failure
    // a body map cannot survive.
    expect(new Set(sink.fills)).toEqual(new Set([CONDITION_TINTS[PartState.Unusable]]));
    // Both legs, and the whole of each: two segments a side, and no feet, which are their own part.
    expect(sink.fills.length).toBe(4);
  });

  it("has one tint per state and no more", () => {
    // Four, because four is how many distinctions the prose supports. A fifth would be a colour
    // with no sentence behind it, which is a gradient wearing a state's clothes.
    expect(CONDITION_TINTS).toHaveLength(4);
    expect(new Set(CONDITION_TINTS).size).toBe(4);
  });
});
