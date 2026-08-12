// The stance ladder in a booted world.
//
// The unit tests next door assert the ladder's shape without a world. These cover the four
// claims that are only true of the running game, and each one is a claim some other file makes
// and could not previously check:
//
//   - a rung decides how loud you are, so crawling past a shambler is not the same as sprinting
//   - low cover cuts **both ways**, which is the sentence `Eye.Crouched` was threaded for
//   - `move_speed` has a reader, so encumbrance is no longer an inert modifier
//   - a stagger costs you a stance change, on the same seam that costs you a wind-up

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Position } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { step, stepN } from "../../src/sim/kernel/step";
import { World } from "../../src/sim/kernel/world";
import { blankMap, Eye, Tile } from "../../src/sim/map/tilemap";
import { Swing, SwingState } from "../../src/sim/modules/melee";
import { Posture, stanceOf } from "../../src/sim/modules/stance";
import { Stance, stanceChangeTicks, stanceSpec } from "../../src/sim/stances";
import { Observer } from "../../src/sim/vision/visibility";
import { shadowcast, VisibleTiles } from "../../src/sim/vision/shadowcast";

const SEED = 20260812;

/** A world with one survivor and nothing else moving. */
function alone(options: Parameters<typeof boot>[0] = { seed: SEED }) {
  const booted = boot({ wanderers: 0, ...options });
  return { ...booted, survivor: booted.player as EntityId };
}

/** Settle onto a rung, paying the transition the ladder charges for. */
function settle(world: World, survivor: EntityId, stance: Stance): void {
  const from = stanceOf(world, survivor);
  world.commands.push({ type: "stance", stance });
  stepN(world, stanceChangeTicks(from, stance) + 1);
  expect(stanceOf(world, survivor)).toBe(stance);
}

describe("a rung decides how loud you are", () => {
  it("puts more into the field at every rung up the ladder", () => {
    // The exit criterion -- "make a noise and the horde comes; go quiet and it doesn't" --
    // restated one rung at a time. Measured as peak noise rather than live cells, because a
    // crawl and a walk both reach less than one 4 m cell and would tie on the cell count.
    const peaks = new Map<Stance, number>();

    for (const stance of [Stance.Crawl, Stance.Crouch, Stance.Walk, Stance.Jog, Stance.Sprint]) {
      const { world, survivor } = alone();
      settle(world, survivor, stance);
      world.commands.push({ type: "move", dx: 1, dy: 0 });
      stepN(world, 10);
      peaks.set(stance, world.field.peakNoise());
    }

    const ordered = [...peaks.entries()].sort((a, b) => a[0] - b[0]);
    for (let i = 1; i < ordered.length; i++) {
      const [stance, peak] = ordered[i] as [Stance, number];
      const [, quieter] = ordered[i - 1] as [Stance, number];
      expect(peak, `${stanceSpec(stance).name} was not louder`).toBeGreaterThan(quieter);
    }
  });

  it("does not let the ground make a rung silent, or a route stop being a decision", () => {
    // docs/29: "a stance is a decision about the attention field; so is a route." Both, and
    // neither cancels the other -- the surface scales the rung's magnitude rather than replacing
    // it, so sprinting over grass is still louder than crawling over grass.
    const loud = alone();
    const quiet = alone();
    settle(loud.world, loud.survivor, Stance.Sprint);
    settle(quiet.world, quiet.survivor, Stance.Crawl);
    for (const { world } of [loud, quiet]) {
      world.commands.push({ type: "move", dx: 1, dy: 0 });
      stepN(world, 10);
    }
    expect(loud.world.field.peakNoise()).toBeGreaterThan(quiet.world.field.peakNoise());
  });

  it("hears the rung rather than the speed, so rough ground does not buy quiet", () => {
    // The reason emission reads `Posture` and not `Math.hypot(vel)`. Undergrowth slows a body
    // below a walking pace while it is still jogging, and a survivor who got quieter by wading
    // into a bush would be reading the wrong number.
    const { world, survivor } = alone();
    settle(world, survivor, Stance.Jog);
    world.commands.push({ type: "move", dx: 1, dy: 0 });
    stepN(world, 5);
    const jogging = world.field.peakNoise();

    const walked = alone();
    settle(walked.world, walked.survivor, Stance.Walk);
    walked.world.commands.push({ type: "move", dx: 1, dy: 0 });
    stepN(walked.world, 5);

    expect(jogging).toBeGreaterThan(walked.world.field.peakNoise());
  });
});

describe("low cover cuts both ways", () => {
  /**
   * A corridor with a single low tile across the middle of it.
   *
   * Built by hand rather than booted, because the shipped district scatters low cover on open
   * ground and a test that hunted for a useful one would be asserting the generator's luck.
   */
  function withLowCover(): { map: ReturnType<typeof blankMap>; a: number; b: number } {
    const map = blankMap(16, 16, Tile.Floor);
    map.tiles[8 * map.w + 8] = Tile.Low;
    return { map, a: 4, b: 12 };
  }

  it("blocks a crouched sightline and passes a standing one", () => {
    const { map, a, b } = withLowCover();
    const standing = new VisibleTiles();
    const crouched = new VisibleTiles();

    shadowcast(map, a, 8, 12, standing, Eye.Standing);
    shadowcast(map, a, 8, 12, crouched, Eye.Crouched);

    expect(standing.has(b, 8)).toBe(true);
    expect(crouched.has(b, 8)).toBe(false);
  });

  it("is symmetric, so the cover that hides you also blinds you", () => {
    // This is the whole point, and it is the half a test would forget. Sight is symmetric by
    // construction in `shadowcast`, so there is no way to build a crouch that sees out without
    // also being seen -- and asserting only one direction would let a future "peek over cover"
    // change break the other silently.
    const { map, a, b } = withLowCover();
    const fromA = new VisibleTiles();
    const fromB = new VisibleTiles();

    shadowcast(map, a, 8, 12, fromA, Eye.Crouched);
    shadowcast(map, b, 8, 12, fromB, Eye.Crouched);

    expect(fromA.has(b, 8)).toBe(false);
    expect(fromB.has(a, 8)).toBe(false);
  });

  it("moves the survivor's eye when they change rung, and recomputes for it", () => {
    const { world, survivor } = alone();
    step(world);
    expect(world.components.getOrThrow(survivor, Observer).eye).toBe(Eye.Standing);

    const before = world.vision.recomputes;
    settle(world, survivor, Stance.Crouch);
    expect(world.components.getOrThrow(survivor, Observer).eye).toBe(Eye.Crouched);
    // Crouching is a new view, so it has to cost a shadowcast. The cache keys on the eye, which
    // is what makes this true without anybody calling an invalidate.
    expect(world.vision.recomputes).toBeGreaterThan(before);

    settle(world, survivor, Stance.Walk);
    expect(world.components.getOrThrow(survivor, Observer).eye).toBe(Eye.Standing);
  });

  it("does not recompute while a rung is simply held", () => {
    // The other half of "recompute on change, not on tick". Writing the eye every tick would be
    // correct and would also throw the cache away every tick.
    const { world, survivor } = alone();
    settle(world, survivor, Stance.Crouch);
    stepN(world, 5);
    const settled = world.vision.recomputes;
    stepN(world, 20);
    expect(world.vision.recomputes).toBe(settled);
  });
});

describe("move_speed finally has a reader", () => {
  it("walks an overloaded survivor slower than an empty-handed one", () => {
    // The assertion that did not exist. `inventory.encumbrance` has been writing a `move_speed`
    // penalty since the grid landed and `movement.integrate` never read the stat, so the
    // modifier resolved correctly and changed nothing. A unit test asserting `resolve()` passed
    // the whole time; this one walks two survivors instead.
    const light = alone();
    const heavy = alone();

    heavy.world.modifiers.add(
      { stat: "move_speed", op: "mul", value: 0.5, source: "test.overloaded" },
      heavy.survivor,
    );

    const travelled = [light, heavy].map(({ world, survivor }) => {
      const from = { ...world.components.getOrThrow(survivor, Position) };
      world.commands.push({ type: "move", dx: 1, dy: 0 });
      stepN(world, 20);
      const to = world.components.getOrThrow(survivor, Position);
      return Math.hypot(to.x - from.x, to.y - from.y);
    });

    const [fast, slow] = travelled as [number, number];
    expect(fast).toBeGreaterThan(0);
    expect(slow).toBeCloseTo(fast * 0.5, 4);
  });

  it("names its sources, so 'why am I this slow?' has an answer", () => {
    // docs/01's fairness rule: every death is explicable. The pipeline's `explain` is what makes
    // that answerable, and it only means anything if the things that slow you down go through it.
    const { world, survivor } = alone();
    world.modifiers.add(
      { stat: "move_speed", op: "mul", value: 0.6, source: "injury.limp" },
      survivor,
    );
    const explained = world.modifiers.explain("move_speed", survivor);
    expect(JSON.stringify(explained)).toContain("injury.limp");
  });
});

describe("a stance change is a timed, interruptible action", () => {
  it("holds the old rung for the whole transition", () => {
    const { world, survivor } = alone();
    world.commands.push({ type: "stance", stance: Stance.Sprint });

    // One tick short of arriving, the survivor is still not sprinting -- which is what makes
    // committing to a sprint a commitment rather than a state flip.
    stepN(world, stanceChangeTicks(Stance.Walk, Stance.Sprint) - 1);
    expect(stanceOf(world, survivor)).not.toBe(Stance.Sprint);

    stepN(world, 2);
    expect(stanceOf(world, survivor)).toBe(Stance.Sprint);
  });

  it("travels through the rungs between rather than skipping them", () => {
    const { world, survivor } = alone();
    settle(world, survivor, Stance.Crawl);

    world.commands.push({ type: "stance", stance: Stance.Sprint });
    const seen = new Set<Stance>();
    for (let i = 0; i < stanceChangeTicks(Stance.Crawl, Stance.Sprint) + 2; i++) {
      step(world);
      seen.add(stanceOf(world, survivor));
    }
    // Every rung, not just the endpoints. Standing up out of a crawl passes through crouch and
    // walk, and that is why it is the most expensive move on the ladder.
    expect(seen.has(Stance.Crouch)).toBe(true);
    expect(seen.has(Stance.Walk)).toBe(true);
    expect(seen.has(Stance.Jog)).toBe(true);
    expect(stanceOf(world, survivor)).toBe(Stance.Sprint);
  });

  it("loses the pending change to a stagger, and stays on a real rung", () => {
    const { world, survivor } = alone();
    world.commands.push({ type: "stance", stance: Stance.Sprint });
    step(world);

    world.events.publish({ type: "entity.staggered", entity: survivor, ticks: 8 });
    stepN(world, stanceChangeTicks(Stance.Walk, Stance.Sprint) + 2);

    // Interrupted halfway up, so not sprinting -- and on a rung that exists, because the walk up
    // the ladder is one rung at a time rather than a lerp.
    const after = stanceOf(world, survivor);
    expect(after).not.toBe(Stance.Sprint);
    expect(world.components.getOrThrow(survivor, Posture).ticksLeft).toBe(0);
    expect(stanceSpec(after).name.length).toBeGreaterThan(0);
  });
});

describe("exhaustion takes the fast rungs away", () => {
  it("drops a sprinting survivor to a walk when the pool runs out", () => {
    // docs/29: "sprint becomes unavailable before it becomes slow. Failure to run is the thing
    // between a fight going badly and a fight killing you." So the survivor does not become a
    // slow sprinter; they stop sprinting.
    const { world, survivor } = alone();
    settle(world, survivor, Stance.Sprint);
    world.commands.push({ type: "move", dx: 1, dy: 0 });

    // Long enough to empty the pool from full, plus the walk back down the ladder.
    stepN(world, 20 * 30);
    expect(stanceOf(world, survivor)).toBe(Stance.Walk);
  });

  it("never forces an exhausted crawler to stand up", () => {
    // The asymmetry, and the reason it is not a special case: crawl is "the last resort that is
    // not running" and the verb left to a survivor whose legs are gone. Being too tired to crawl
    // further has to mean lying still, not standing up into the thing you were crawling from.
    const { world, survivor } = alone();
    settle(world, survivor, Stance.Crawl);
    world.commands.push({ type: "move", dx: 1, dy: 0 });
    stepN(world, 20 * 200);
    expect(stanceOf(world, survivor)).toBe(Stance.Crawl);
  });
});

describe("the rung gates what you can do", () => {
  it("refuses a swing from a crawl and allows one from a crouch", () => {
    // Through the real gate rather than through the ladder's own field: `melee.intake` queries on
    // `Swing`, which only the dev loadout hands out, so this is the module reading the rung.
    for (const [stance, expected] of [
      [Stance.Crawl, SwingState.Idle],
      [Stance.Crouch, SwingState.WindUp],
    ] as const) {
      const { world, survivor } = alone({ seed: SEED, loadout: "dev" });
      settle(world, survivor, stance);

      world.commands.push({ type: "swing" });
      step(world);
      expect(
        world.components.getOrThrow(survivor, Swing).state,
        `swinging from ${stanceSpec(stance).name}`,
      ).toBe(expected);
    }
  });

  it("abandons a wind-up the moment a sprint is asked for, not when it arrives", () => {
    // The decision costs you the swing, not the arrival -- otherwise a bat's wind-up would land
    // inside the eight ticks the transition takes and docs/09's rule would never fire once.
    const { world, survivor } = alone({ seed: SEED, loadout: "dev" });
    world.commands.push({ type: "swing" });
    step(world);
    expect(world.components.getOrThrow(survivor, Swing).state).toBe(SwingState.WindUp);

    world.commands.push({ type: "stance", stance: Stance.Sprint });
    step(world);
    expect(world.components.getOrThrow(survivor, Swing).state).toBe(SwingState.Idle);
    // Still not sprinting, which is the point: the swing is gone and the speed has not arrived.
    expect(stanceOf(world, survivor)).not.toBe(Stance.Sprint);
  });
});

describe("the ladder is in the save", () => {
  it("keeps a survivor mid-transition mid-transition", () => {
    // A `Posture` restored without its timer would finish an action nobody paid for. The
    // determinism test covers the general case; this pins the field that would go missing.
    const { world, survivor } = alone();
    world.commands.push({ type: "stance", stance: Stance.Sprint });
    step(world);

    const posture = world.components.getOrThrow(survivor, Posture);
    expect(posture.target).toBe(Stance.Sprint);
    expect(posture.ticksLeft).toBeGreaterThan(0);
    expect(JSON.stringify(world.snapshot())).toContain("Posture");
  });
});
