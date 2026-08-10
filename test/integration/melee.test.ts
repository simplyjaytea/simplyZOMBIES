// The melee loop, on the path the game actually boots.
//
// The unit tests build a duel: one survivor, one target placed by hand. This drives `boot()`
// with a district and a crowd in it, because that is the difference between "the geometry is
// right" and "the feature is wired up".

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { MELEE_CONNECT_NOISE, recoverTicks, WEAPONS, windupTicks } from "../../src/sim/combat";
import type { GameEvent } from "../../src/sim/events";
import { Facing, Position } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { applySave, createSave, decodeSave, encodeSave } from "../../src/sim/kernel/save";
import { step } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { Body } from "../../src/sim/modules/health";
import { Shambler } from "../../src/sim/modules/shambler";

/** Boot a district, then stand the survivor at arm's length from one of its shamblers. */
function faceOff(seed = 77) {
  const { world, player } = boot({ seed, wanderers: 60, mapSize: 96 });
  const attacker = player as EntityId;
  const victim = world.components.query(Position, Shambler)[0] as EntityId;

  // Put the survivor a metre west of it, looking east. Moving the *survivor* rather than the
  // zombie keeps the horde's own state untouched.
  const there = world.components.getOrThrow(victim, Position);
  const here = world.components.getOrThrow(attacker, Position);
  here.x = there.x - 1;
  here.y = there.y;
  world.components.getOrThrow(attacker, Facing).radians = 0;

  return { world, attacker, victim };
}

/** One full swing, keeping every event it produced. */
function swing(world: World, keepFacing: () => void): GameEvent[] {
  const events: GameEvent[] = [];
  world.commands.push({ type: "swing" });
  const ticks = windupTicks(WEAPONS.bat.weight) + recoverTicks(WEAPONS.bat.weight) + 1;
  for (let i = 0; i < ticks; i++) {
    keepFacing();
    step(world);
    events.push(...world.events.drained);
  }
  return events;
}

describe("melee, on the shipped boot path", () => {
  it("kills a shambler out of a live district, and takes it off the board", () => {
    const { world, attacker, victim } = faceOff();
    const before = world.entities.count;

    // The victim is a live shambler and walks; keep the survivor on top of it and pointed at
    // it, so this measures the loop rather than the survivor's footwork.
    const hold = () => {
      if (!world.entities.isAlive(victim)) return;
      const there = world.components.get(victim, Position);
      if (there === undefined) return;
      const here = world.components.getOrThrow(attacker, Position);
      here.x = there.x - 1;
      here.y = there.y;
      world.components.getOrThrow(attacker, Facing).radians = 0;
    };

    const events: GameEvent[] = [];
    for (let i = 0; i < 40 && world.entities.isAlive(victim); i++) {
      events.push(...swing(world, hold));
    }

    expect(world.entities.isAlive(victim)).toBe(false);
    expect(events.filter((e) => e.type === "attack.connected").length).toBeGreaterThan(0);
    expect(events).toContainEqual({ type: "entity.killed", entity: victim, killer: attacker });
    // Actually gone, not merely flagged.
    expect(world.entities.count).toBe(before - 1);
    expect(world.components.get(victim, Body)).toBeUndefined();
  });

  it("is quiet: a whole fight costs less noise than one shout", () => {
    // The reward the melee branch is paid in. docs/03: a connect is 8 against a shout's 120.
    const { world, attacker, victim } = faceOff();
    const hold = () => {
      const there = world.components.get(victim, Position);
      if (there === undefined) return;
      const here = world.components.getOrThrow(attacker, Position);
      here.x = there.x - 1;
      here.y = there.y;
      world.components.getOrThrow(attacker, Facing).radians = 0;
    };

    const events: GameEvent[] = [];
    for (let i = 0; i < 40 && world.entities.isAlive(victim); i++) {
      events.push(...swing(world, hold));
    }

    const fight = events
      .filter((e) => e.type === "noise.emitted" && e.source === attacker)
      .reduce((sum, e) => sum + (e.type === "noise.emitted" ? e.magnitude : 0), 0);

    expect(fight).toBeGreaterThan(0);
    expect(fight % MELEE_CONNECT_NOISE).toBe(0);
    expect(fight).toBeLessThan(120);
  });

  it("staggers the crowd it hits, which is what makes a crowd survivable", () => {
    const { world, attacker, victim } = faceOff();
    const events = swing(world, () => {
      world.components.getOrThrow(attacker, Facing).radians = 0;
    });
    const staggers = events.filter((e) => e.type === "entity.staggered");
    expect(staggers.map((e) => (e.type === "entity.staggered" ? e.entity : null))).toContain(
      victim,
    );
  });

  it("stays deterministic with swings in the command log", () => {
    // The claim behind docs/19: seed plus command log reproduces a run byte for byte. A swing
    // draws from a seeded stream, so it is exactly the kind of thing that could break it.
    const run = () => {
      const { world, attacker } = faceOff(78);
      for (let tick = 0; tick < 200; tick++) {
        if (tick % 17 === 0) world.commands.push({ type: "swing" });
        if (tick % 23 === 0) world.components.getOrThrow(attacker, Facing).radians = 0;
        step(world);
      }
      return world.serialize();
    };
    expect(run()).toBe(run());
  });

  it("survives a save taken mid-wind-up, and lands the blow on the same tick", () => {
    const { world } = faceOff(79);
    world.commands.push({ type: "swing" });
    step(world);

    // Through the real save path -- text -- rather than `world.snapshot()`. A snapshot shares
    // its component objects with the live world, so a world that keeps running mutates the
    // snapshot underneath you; encoding is what makes it a copy. This is also the case that
    // would have caught a mid-swing save throwing on canonicalize, which rejects -0 outright.
    const text = encodeSave(createSave(world));

    const ticks = windupTicks(WEAPONS.bat.weight);
    const straightThrough: GameEvent[] = [];
    for (let i = 0; i < ticks; i++) {
      step(world);
      straightThrough.push(...world.events.drained);
    }

    const reloaded = boot({ seed: 79, wanderers: 60, mapSize: 96 }).world;
    applySave(reloaded, decodeSave(text));
    const afterLoad: GameEvent[] = [];
    for (let i = 0; i < ticks; i++) {
      step(reloaded);
      afterLoad.push(...reloaded.events.drained);
    }

    // The blow lands on the same tick it would have, against the same target.
    expect(afterLoad.filter((e) => e.type === "attack.connected")).toEqual(
      straightThrough.filter((e) => e.type === "attack.connected"),
    );
    expect(afterLoad.filter((e) => e.type === "attack.connected").length).toBeGreaterThan(0);
    expect(reloaded.serialize()).toBe(world.serialize());
  });
});
