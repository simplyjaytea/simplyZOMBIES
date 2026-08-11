import { describe, expect, it } from "vitest";
import {
  advancePhase,
  CRAWL_STRIDE_METRES,
  frameOf,
  octantOf,
  OCTANTS,
  Pose,
  POSE_FRAMES,
  POSE_ROW,
  FRAMES_PER_ARCHETYPE,
  selectPose,
  STRIDE_METRES,
  type PoseInput,
} from "../../src/render/sprites/pose";
import { SPRINT_THRESHOLD, WALK_SPEED, SPRINT_SPEED } from "../../src/sim/locomotion";
import { SwingState } from "../../src/sim/modules/melee";
import { headingOf } from "../../src/sim/kernel/components";

/** A body doing nothing, which each test perturbs by exactly the one field it is about. */
function still(over: Partial<PoseInput> = {}): PoseInput {
  return {
    speedMetresPerSecond: 0,
    crawling: false,
    staggered: false,
    swing: SwingState.Idle,
    sprintThreshold: SPRINT_THRESHOLD,
    phase: 0,
    ...over,
  };
}

describe("octantOf", () => {
  it("centres each octant on its heading, so a body faces where it is going", () => {
    // Rounding rather than flooring. The floored version is off by half a sector everywhere,
    // which reads as a body that never quite looks in the direction it is walking.
    for (let i = 0; i < OCTANTS; i++) {
      const heading = (i * Math.PI * 2) / OCTANTS;
      expect(octantOf(heading)).toBe(i);
    }
  });

  it("gives the eight headings eight distinct answers", () => {
    const seen = new Set<number>();
    for (let i = 0; i < OCTANTS; i++) seen.add(octantOf((i * Math.PI * 2) / OCTANTS));
    expect(seen.size).toBe(OCTANTS);
  });

  it("is stable across the +/-pi wrap, where Facing's range ends", () => {
    // Facing is normalised to (-pi, pi], so due west arrives as either sign depending on which
    // way the body turned into it. Both must draw the same sprite.
    expect(octantOf(Math.PI)).toBe(octantOf(-Math.PI));
    expect(octantOf(Math.PI - 1e-9)).toBe(octantOf(-Math.PI + 1e-9));
  });

  it("treats the negative zero atan2 produces for due east as east", () => {
    // Facing's own doc warns about this: Math.atan2(-0, 1) is -0, and it reaches it for any
    // due-east heading with a negative-zero dy.
    expect(octantOf(-0)).toBe(0);
    expect(octantOf(0)).toBe(0);
  });

  it("agrees with headingOf, so the sprite matches the velocity that set the facing", () => {
    expect(octantOf(headingOf(1, 0) as number)).toBe(0);
    expect(octantOf(headingOf(0, 1) as number)).toBe(2);
    expect(octantOf(headingOf(-1, 0) as number)).toBe(4);
    expect(octantOf(headingOf(0, -1) as number)).toBe(6);
    expect(octantOf(headingOf(1, 1) as number)).toBe(1);
  });

  it("always lands in range, for any real heading", () => {
    for (let r = -20; r <= 20; r += 0.037) {
      const octant = octantOf(r);
      expect(Number.isInteger(octant)).toBe(true);
      expect(octant).toBeGreaterThanOrEqual(0);
      expect(octant).toBeLessThan(OCTANTS);
    }
  });

  it("never throws on a heading that should be impossible", () => {
    expect(octantOf(NaN)).toBe(0);
    expect(octantOf(Infinity)).toBe(0);
  });
});

describe("selectPose precedence", () => {
  // The order is a design commitment, so each rung gets an assertion that it beats the next.

  it("crawling beats everything, because it is a fact about the body", () => {
    // isCrawling applies in every shambler state, and docs/29 says you cannot swing from a
    // crawl -- so a crawl pose must never be overridden by an attack the sim will not deliver.
    expect(
      selectPose(
        still({
          crawling: true,
          staggered: true,
          swing: SwingState.WindUp,
          speedMetresPerSecond: SPRINT_SPEED,
        }),
      ).pose,
    ).toBe(Pose.Crawl);
  });

  it("a crawling body never draws a swing", () => {
    for (const swing of [SwingState.Idle, SwingState.WindUp, SwingState.Recover]) {
      const { pose } = selectPose(still({ crawling: true, swing }));
      expect(pose).toBe(Pose.Crawl);
    }
  });

  it("stagger beats a swing, because it is the only thing that interrupts", () => {
    // shambler.ts: stagger "is the *only* thing that interrupts this state machine". The
    // drawing interrupts for the same one thing, so the screen cannot claim a body is
    // attacking while the simulation has it on its back foot.
    expect(selectPose(still({ staggered: true, swing: SwingState.WindUp })).pose).toBe(
      Pose.Staggered,
    );
    expect(selectPose(still({ staggered: true, speedMetresPerSecond: SPRINT_SPEED })).pose).toBe(
      Pose.Staggered,
    );
  });

  it("a swing beats locomotion, because the commitment is the mechanic", () => {
    expect(
      selectPose(still({ swing: SwingState.WindUp, speedMetresPerSecond: SPRINT_SPEED })).pose,
    ).toBe(Pose.WindUp);
    expect(
      selectPose(still({ swing: SwingState.Recover, speedMetresPerSecond: WALK_SPEED })).pose,
    ).toBe(Pose.Recover);
  });

  it("splits sprint from walk at the simulation's own threshold", () => {
    // SPRINT_THRESHOLD, not a second speed cut invented here. One answer, two consumers.
    expect(selectPose(still({ speedMetresPerSecond: WALK_SPEED })).pose).toBe(Pose.Walk);
    expect(selectPose(still({ speedMetresPerSecond: SPRINT_THRESHOLD })).pose).toBe(Pose.Sprint);
    expect(selectPose(still({ speedMetresPerSecond: SPRINT_SPEED })).pose).toBe(Pose.Sprint);
  });

  it("is idle only when genuinely stopped", () => {
    expect(selectPose(still()).pose).toBe(Pose.Idle);
    expect(selectPose(still({ speedMetresPerSecond: 0.01 })).pose).toBe(Pose.Walk);
  });
});

describe("frameOf", () => {
  it("stays inside the pose's row, for every phase including the ends", () => {
    // The characteristic atlas bug: an index off the end of a row reads the next pose's frame.
    for (const pose of [Pose.Idle, Pose.Walk, Pose.Sprint, Pose.Crawl, Pose.Staggered]) {
      const frames = POSE_FRAMES[pose] as number;
      for (const phase of [0, 0.0001, 0.25, 0.5, 0.75, 1 - 1e-12, 1]) {
        const frame = frameOf(pose, phase);
        expect(frame).toBeGreaterThanOrEqual(0);
        expect(frame).toBeLessThan(frames);
      }
    }
  });

  it("holds a single-frame pose on its only frame", () => {
    for (const phase of [0, 0.3, 0.99]) {
      expect(frameOf(Pose.Staggered, phase)).toBe(0);
      expect(frameOf(Pose.WindUp, phase)).toBe(0);
    }
  });

  it("steps through a cycle in order", () => {
    expect(frameOf(Pose.Walk, 0)).toBe(0);
    expect(frameOf(Pose.Walk, 0.26)).toBe(1);
    expect(frameOf(Pose.Walk, 0.51)).toBe(2);
    expect(frameOf(Pose.Walk, 0.76)).toBe(3);
  });
});

describe("advancePhase", () => {
  it("does not advance a body that did not move, so nobody moonwalks", () => {
    expect(advancePhase(0.3, 0, Pose.Walk)).toBe(0.3);
    expect(advancePhase(0.3, -1, Pose.Walk)).toBe(0.3);
  });

  it("advances by distance, so the same ground gives the same frame at any frame rate", () => {
    // The property the whole design rests on. Sixty small steps and one large one covering the
    // same ground must land on the same frame, or the cycle depends on the display and skates.
    const oneStep = advancePhase(0, STRIDE_METRES * 0.5, Pose.Walk);
    let many = 0;
    for (let i = 0; i < 60; i++) many = advancePhase(many, (STRIDE_METRES * 0.5) / 60, Pose.Walk);
    expect(many).toBeCloseTo(oneStep, 10);
    expect(frameOf(Pose.Walk, many)).toBe(frameOf(Pose.Walk, oneStep));
  });

  it("covers exactly one cycle in a stride, and wraps", () => {
    expect(advancePhase(0, STRIDE_METRES, Pose.Walk)).toBeCloseTo(0, 10);
    expect(advancePhase(0, STRIDE_METRES * 2.25, Pose.Walk)).toBeCloseTo(0.25, 10);
  });

  it("drags a crawler through its cycle over less ground than a walker", () => {
    // docs/14: a crawler is dragging rather than stepping, so the same distance is more cycle.
    expect(CRAWL_STRIDE_METRES).toBeLessThan(STRIDE_METRES);
    expect(advancePhase(0, 0.3, Pose.Crawl)).toBeGreaterThan(advancePhase(0, 0.3, Pose.Walk));
  });

  it("holds the phase through a non-cyclic pose rather than resetting it", () => {
    // A body that staggers mid-stride resumes where it left off instead of snapping to frame 0.
    expect(advancePhase(0.7, 5, Pose.Staggered)).toBe(0.7);
    expect(advancePhase(0.7, 5, Pose.WindUp)).toBe(0.7);
  });

  it("always returns a phase in [0, 1)", () => {
    let phase = 0;
    for (let i = 0; i < 500; i++) {
      phase = advancePhase(phase, 0.37, Pose.Walk);
      expect(phase).toBeGreaterThanOrEqual(0);
      expect(phase).toBeLessThan(1);
    }
  });

  it("survives a distance that should be impossible", () => {
    expect(advancePhase(0.5, NaN, Pose.Walk)).toBe(0.5);
    expect(Number.isFinite(advancePhase(0.5, Infinity, Pose.Walk))).toBe(true);
  });
});

describe("the sheet layout", () => {
  it("gives every pose a row range that does not overlap the next", () => {
    for (let pose = 1; pose < POSE_FRAMES.length; pose++) {
      expect(POSE_ROW[pose]).toBe(
        (POSE_ROW[pose - 1] as number) + (POSE_FRAMES[pose - 1] as number),
      );
    }
  });

  it("accounts for every frame exactly once", () => {
    const last = POSE_FRAMES.length - 1;
    expect((POSE_ROW[last] as number) + (POSE_FRAMES[last] as number)).toBe(FRAMES_PER_ARCHETYPE);
  });
});
