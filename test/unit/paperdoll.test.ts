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
import { CONDITION_TINTS } from "../../src/render/palette";
import { drawPaperdoll, isNotable, poseForStance, tintFor } from "../../src/render/paperdoll";
import { Pose, POSES } from "../../src/render/sprites/pose";
import type { ShapeSink } from "../../src/render/sprites/humanoid";

const SEED = 20260812;

function survivor(): { world: ReturnType<typeof boot>["world"]; who: EntityId } {
  const { world, player } = boot({ seed: SEED, wanderers: 0 });
  step(world);
  return { world, who: player as EntityId };
}

/** A sink that records the fills, so a figure can be asserted without a canvas. */
class Recorder implements ShapeSink {
  fillStyle: string | CanvasGradient | CanvasPattern = "";
  readonly fills: string[] = [];
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
  it("maps every rung to a pose, and the low rungs to a low body", () => {
    // The user-visible promise: standing shows it standing, crouching shows it crouching, prone
    // shows it prone. Asserted per rung rather than by example, so a rung added to the ladder
    // without a posture fails here.
    // Every rung gets one of the poses the sheet actually holds a row for -- a rung mapped to a
    // pose the atlas does not carry would blit whatever is at that offset, which is somebody
    // else's frame rather than a missing one.
    for (const stance of STANCES) {
      expect(POSES, stanceSpec(stance).name).toContain(poseForStance(stance));
    }
    expect(poseForStance(Stance.Crawl)).toBe(Pose.Crawl);
    expect(poseForStance(Stance.Crouch)).toBe(Pose.Crouch);
    expect(poseForStance(Stance.Walk)).toBe(Pose.Idle);
    expect(poseForStance(Stance.Jog)).toBe(Pose.Idle);
    expect(poseForStance(Stance.Sprint)).toBe(Pose.Idle);
  });

  it("draws a crouched body shorter than a standing one, and a prone one differently again", () => {
    // The posture has to be visible, not merely selected.
    //
    // Crouch is measured as the height of the ink above the anchor, which is what a player sees.
    // **Prone is not**, and the reason is the projection rather than the pose: a crawler lies out
    // *along the ground* over about a metre, and under an isometric camera a body extended away
    // from the viewer occupies up-screen pixels. So the crawler's topmost ink is legitimately
    // higher than the crouch's while its head is far lower, and a height comparison would fail on
    // a correct picture. What is asserted instead is that it is a different shape -- which it is,
    // because `drawCrawler` is a separate silhouette rather than a squashed standing one.
    const { world, who } = survivor();
    const profiles = new Map<Stance, { height: number; ink: string }>();

    for (const stance of [Stance.Walk, Stance.Crouch, Stance.Crawl]) {
      world.components.getOrThrow(who, Posture).current = stance;
      const view = conditionView(world, who);
      const sink = new Recorder();
      drawPaperdoll(sink, view as NonNullable<typeof view>, {
        zoom: 84,
        anchorX: 200,
        anchorY: 200,
      });
      profiles.set(stance, {
        height: 200 - Math.min(...sink.ys),
        ink: `${sink.xs.length}:${sink.ys.map((y) => y.toFixed(1)).join(",")}`,
      });
    }

    const standing = profiles.get(Stance.Walk) as { height: number; ink: string };
    const crouched = profiles.get(Stance.Crouch) as { height: number; ink: string };
    const prone = profiles.get(Stance.Crawl) as { height: number; ink: string };

    expect(crouched.height).toBeLessThan(standing.height);
    expect(prone.ink).not.toBe(standing.ink);
    expect(prone.ink).not.toBe(crouched.ink);
  });

  it("follows the same predicate as the sightline, so low is low in both", () => {
    // Cover that hides you also blinds you, and the figure agrees with both. If these two ever
    // disagreed, the paperdoll would be drawing a crouch the shadowcast does not believe in.
    for (const stance of STANCES) {
      const lowEye = stanceSpec(stance).eye === 1;
      const lowBody = poseForStance(stance) !== Pose.Idle;
      expect(lowBody, stanceSpec(stance).name).toBe(lowEye);
    }
  });
});

describe("tint is colour and never fill", () => {
  it("tints nothing on an unhurt body", () => {
    // An unhurt survivor draws as a person, not as a diagram -- so any colour on the figure means
    // something, which is what keeps the glimpse worth looking at.
    const { world, who } = survivor();
    const view = conditionView(world, who);
    expect(tintFor((view as NonNullable<typeof view>).parts)).toEqual({});
    expect(isNotable(view as NonNullable<typeof view>)).toBe(false);
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

  it("puts the tint on the figure it was asked for", () => {
    const { world, who } = survivor();
    world.components.getOrThrow(who, Body).legs = 0;
    const view = conditionView(world, who) as NonNullable<ReturnType<typeof conditionView>>;

    const sink = new Recorder();
    drawPaperdoll(sink, view, { zoom: 84, anchorX: 200, anchorY: 200 });
    expect(sink.fills).toContain(CONDITION_TINTS[PartState.Unusable]);
  });

  it("has one tint per state and no more", () => {
    // Four, because four is how many distinctions the prose supports. A fifth would be a colour
    // with no sentence behind it, which is a gradient wearing a state's clothes.
    expect(CONDITION_TINTS).toHaveLength(4);
    expect(new Set(CONDITION_TINTS).size).toBe(4);
  });
});
