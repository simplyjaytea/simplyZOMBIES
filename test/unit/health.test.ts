import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import {
  STAMINA_MAX,
  STAMINA_PER_TICK,
  STAMINA_RECOVERY_DELAY_TICKS,
  ZOMBIE_BODY,
} from "../../src/sim/combat";
import { Position } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import type { GameEvent } from "../../src/sim/events";
import { step, stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { Body, isCrawling, Stamina } from "../../src/sim/modules/health";
import { Controlled } from "../../src/sim/modules/player";
import { Shambler } from "../../src/sim/modules/shambler";

function scene(wanderers = 3) {
  const boots = boot({ seed: 31, wanderers, mapSize: 48 });
  const zombie = boots.world.components.query(Position, Shambler)[0] as EntityId;
  return { ...boots, zombie, player: boots.player as EntityId };
}

/** Everything the bus drained on the tick just run. */
function drained(world: World): readonly GameEvent[] {
  return world.events.drained;
}

function hit(world: World, attacker: EntityId, target: EntityId, part: string, damage: number) {
  world.events.publish({ type: "attack.connected", attacker, target, bodyPart: part, damage });
}

describe("Body", () => {
  it("starts at the values the content file states", () => {
    const { world, zombie } = scene();
    expect(world.components.getOrThrow(zombie, Body)).toEqual({ ...ZOMBIE_BODY });
  });

  it("takes damage on the part that was hit, and nowhere else", () => {
    const { world, zombie, player } = scene();
    hit(world, player, zombie, "torso", 10);
    step(world);

    const body = world.components.getOrThrow(zombie, Body);
    expect(body.torso).toBe(ZOMBIE_BODY.torso - 10);
    expect(body.head).toBe(ZOMBIE_BODY.head);
    expect(body.legs).toBe(ZOMBIE_BODY.legs);
  });

  it("never kills on the torso, however much of it is destroyed", () => {
    // docs/14: "Body damage slows and staggers but doesn't stop them."
    const { world, zombie, player } = scene();
    for (let i = 0; i < 10; i++) {
      hit(world, player, zombie, "torso", ZOMBIE_BODY.torso);
      step(world);
    }
    expect(world.entities.isAlive(zombie)).toBe(true);
    expect(world.components.getOrThrow(zombie, Body).torso).toBe(0);
  });

  it("kills on the head, publishes it once, and despawns in cleanup", () => {
    const { world, zombie, player } = scene();
    hit(world, player, zombie, "head", ZOMBIE_BODY.head);
    step(world);

    const kills = drained(world).filter((e) => e.type === "entity.killed");
    expect(kills).toEqual([{ type: "entity.killed", entity: zombie, killer: player }]);

    // Still there, for exactly one tick. `step` drains events after every system has run, so
    // a kill published in that drain is reaped by the *next* tick's cleanup phase. It is
    // already not alive by the only test that matters to a would-be attacker.
    expect(world.entities.isAlive(zombie)).toBe(true);
    expect(world.components.getOrThrow(zombie, Body).head).toBe(0);

    step(world);
    expect(world.entities.isAlive(zombie)).toBe(false);
    expect(world.components.get(zombie, Body)).toBeUndefined();
  });

  it("does not kill a corpse twice when two blows land in one tick", () => {
    // Both events drain before cleanup runs. Without the isAlive guard this publishes two
    // kills and despawns twice, and the second despawn is on a recycled id.
    const { world, zombie, player } = scene();
    hit(world, player, zombie, "head", ZOMBIE_BODY.head);
    hit(world, player, zombie, "head", ZOMBIE_BODY.head);
    step(world);

    expect(drained(world).filter((e) => e.type === "entity.killed")).toHaveLength(1);
  });

  it("cripples rather than kills when locomotion goes, and says so", () => {
    const { world, zombie, player } = scene();
    hit(world, player, zombie, "legs", ZOMBIE_BODY.legs);
    step(world);

    expect(world.entities.isAlive(zombie)).toBe(true);
    expect(isCrawling(world.components.getOrThrow(zombie, Body))).toBe(true);
    expect(drained(world)).toContainEqual({
      type: "injury.sustained",
      entity: zombie,
      injury: "crippled",
      bodyPart: "legs",
    });
  });

  it("announces the crippling once, not on every later hit to a destroyed leg", () => {
    const { world, zombie, player } = scene();
    hit(world, player, zombie, "legs", ZOMBIE_BODY.legs);
    step(world);
    hit(world, player, zombie, "legs", 5);
    step(world);

    expect(drained(world).filter((e) => e.type === "injury.sustained")).toHaveLength(0);
  });

  it("ignores an attack on something with no body, rather than throwing", () => {
    const { world, player } = scene();
    const rock = world.spawn();
    hit(world, player, rock, "head", 100);
    expect(() => step(world)).not.toThrow();
  });
});

describe("Stamina", () => {
  it("drains by what was spent, and stalls recovery for a beat", () => {
    const { world, player } = scene(0);
    world.events.publish({ type: "stamina.spent", entity: player, amount: 30 });
    step(world);

    const stamina = world.components.getOrThrow(player, Stamina);
    expect(stamina.current).toBe(STAMINA_MAX - 30);
    // The drain happens after the health phase, so no tick of the delay has been spent yet.
    expect(stamina.ticksUntilRecovery).toBe(STAMINA_RECOVERY_DELAY_TICKS);
  });

  it("does not recover during the delay, and does afterwards", () => {
    const { world, player } = scene(0);
    world.events.publish({ type: "stamina.spent", entity: player, amount: 30 });
    step(world); // the drain that applies it

    const stamina = world.components.getOrThrow(player, Stamina);
    stepN(world, STAMINA_RECOVERY_DELAY_TICKS);
    expect(stamina.current).toBe(STAMINA_MAX - 30);
    expect(stamina.ticksUntilRecovery).toBe(0);

    stepN(world, 10);
    expect(stamina.current).toBeCloseTo(STAMINA_MAX - 30 + 10 * STAMINA_PER_TICK, 8);
  });

  it("never exceeds its maximum, or falls below nothing", () => {
    const { world, player } = scene(0);
    world.events.publish({ type: "stamina.spent", entity: player, amount: STAMINA_MAX * 3 });
    step(world);
    expect(world.components.getOrThrow(player, Stamina).current).toBe(0);

    stepN(world, STAMINA_RECOVERY_DELAY_TICKS + 1000);
    expect(world.components.getOrThrow(player, Stamina).current).toBe(STAMINA_MAX);
  });

  it("is carried by the survivor, who is the only thing that can spend it yet", () => {
    const { world, player, zombie } = scene();
    expect(world.components.has(player, Stamina)).toBe(true);
    expect(world.components.has(zombie, Stamina)).toBe(false);
    expect(world.components.has(player, Controlled)).toBe(true);
  });
});
