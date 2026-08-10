import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { WEAPONS, ZOMBIE_BODY } from "../../src/sim/combat";
import { Position, Velocity } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { step, stepN } from "../../src/sim/kernel/step";
import { Body } from "../../src/sim/modules/health";
import { Shambler, ShamblerState, SHAMBLER_TUNING } from "../../src/sim/modules/shambler";

function oneShambler() {
  const { world } = boot({ seed: 55, wanderers: 1, mapSize: 48 });
  const zombie = world.components.query(Position, Shambler)[0] as EntityId;
  return { world, zombie };
}

describe("stagger", () => {
  it("stops a shambler dead, for the duration the blow declared", () => {
    const { world, zombie } = oneShambler();
    stepN(world, 5);

    world.events.publish({ type: "entity.staggered", entity: zombie, ticks: 16 });
    step(world); // drains it
    step(world); // first tick of the state machine seeing it

    const self = world.components.getOrThrow(zombie, Shambler);
    const vel = world.components.getOrThrow(zombie, Velocity);
    expect(self.state).toBe(ShamblerState.Staggered);
    expect(vel.dx).toBe(0);
    expect(vel.dy).toBe(0);
  });

  it("holds still for the whole of it, then goes back to drifting", () => {
    const { world, zombie } = oneShambler();
    world.events.publish({ type: "entity.staggered", entity: zombie, ticks: 16 });
    step(world);

    stepN(world, 15);
    expect(world.components.getOrThrow(zombie, Shambler).state).toBe(ShamblerState.Staggered);

    step(world);
    expect(world.components.getOrThrow(zombie, Shambler).state).toBe(ShamblerState.Wander);
  });

  it("takes the longer of two staggers, never the latest", () => {
    // Otherwise a knife tap in a crowd would shorten the stagger a bat had just bought.
    const { world, zombie } = oneShambler();
    world.events.publish({ type: "entity.staggered", entity: zombie, ticks: 16 });
    world.events.publish({ type: "entity.staggered", entity: zombie, ticks: 4 });
    step(world);
    expect(world.components.getOrThrow(zombie, Shambler).ticksStaggered).toBe(16);
  });

  it("is the only thing that interrupts the state machine -- damage never is", () => {
    // docs/14: they "stagger from mass, never flinch from injury".
    const { world, zombie } = oneShambler();
    stepN(world, 5);
    const before = world.components.getOrThrow(zombie, Shambler).state;

    world.events.publish({
      type: "attack.connected",
      attacker: zombie,
      target: zombie,
      bodyPart: "torso",
      damage: ZOMBIE_BODY.torso,
    });
    step(world);
    step(world);

    expect(world.components.getOrThrow(zombie, Shambler).state).toBe(before);
  });

  it("is bought by a swing: a bat holds one four times as long as a knife", () => {
    expect(WEAPONS.bat.staggerTicks).toBe(WEAPONS.knife.staggerTicks * 4);
  });
});

describe("the crawler", () => {
  it("keeps moving with its legs destroyed, at a fraction of the pace", () => {
    // docs/14: a destroyed pelvis crawls, and is still perfectly capable of biting an ankle.
    const intact = oneShambler();
    const broken = oneShambler();
    broken.world.components.getOrThrow(broken.zombie, Body).legs = 0;

    // Force the drift to pick a new heading on the very next tick in both worlds. Left to
    // run, the two would diverge for an honest reason -- a crawler is somewhere else a minute
    // later, so it reads a different field -- and the comparison would stop being about speed.
    for (const { world, zombie } of [intact, broken]) {
      world.components.getOrThrow(zombie, Shambler).ticksToTurn = 0;
      step(world);
    }

    const fast = world2speed(intact);
    const slow = world2speed(broken);

    expect(fast).toBeGreaterThan(0);
    expect(slow).toBeCloseTo(fast * SHAMBLER_TUNING.crawlSpeedFactor, 6);
  });

  it("is still alive, and still a target", () => {
    const { world, zombie } = oneShambler();
    world.components.getOrThrow(zombie, Body).legs = 0;
    stepN(world, 10);
    expect(world.entities.isAlive(zombie)).toBe(true);
    expect(world.components.getOrThrow(zombie, Body).head).toBe(ZOMBIE_BODY.head);
  });
});

function world2speed({
  world,
  zombie,
}: {
  world: ReturnType<typeof boot>["world"];
  zombie: EntityId;
}) {
  const vel = world.components.getOrThrow(zombie, Velocity);
  return Math.hypot(vel.dx, vel.dy);
}
