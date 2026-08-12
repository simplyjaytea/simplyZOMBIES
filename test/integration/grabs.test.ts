// Grabs, bites, and the smallest infection seam needed to make close combat dangerous.
//
// This deliberately stops at wound-time uncertainty. Symptoms, diagnosis, treatment, and
// turning belong to Milestone 2; Milestone 1 only has to preserve the private answer.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { WEAPONS } from "../../src/sim/combat";
import { conditionView } from "../../src/sim/condition";
import { Position, Velocity } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { applySave, createSave, decodeSave, encodeSave } from "../../src/sim/kernel/save";
import { step, stepN } from "../../src/sim/kernel/step";
import {
  Body,
  BITE_PRESENTS_AS_SCRATCH_CHANCE,
  Injuries,
  makeBody,
  Stamina,
} from "../../src/sim/modules/health";
import { BITE_TRANSMISSION_CHANCE, ZombieInfection } from "../../src/sim/modules/infection";
import { Swing, SwingState } from "../../src/sim/modules/melee";
import {
  defaultShamblerSpeeds,
  escapeChance,
  Grabbed,
  GrabState,
  Shambler,
  ShamblerState,
  SHAMBLER_TUNING,
} from "../../src/sim/modules/shambler";

const SEED = 808080;

function grabbedBy(count: number, options: { loadout?: "none" | "dev" } = {}) {
  const booted = boot({
    seed: SEED,
    wanderers: 0,
    mapSize: 64,
    loadout: options.loadout ?? "none",
    disabled: ["attention", "field-memory"],
  });
  const survivor = booted.player as EntityId;
  const here = booted.world.components.getOrThrow(survivor, Position);
  const zombies: EntityId[] = [];

  for (let i = 0; i < count; i++) {
    const zombie = booted.world.spawn();
    zombies.push(zombie);
    // Overlap is intentional fixture geometry: it keeps every source in the survivor's known-open
    // tile and makes this a hold test rather than a generated-map collision test.
    booted.world.components.set(zombie, Position, { x: here.x, y: here.y });
    booted.world.components.set(zombie, Velocity, { dx: 0, dy: 0 });
    booted.world.components.set(zombie, Shambler, {
      ...defaultShamblerSpeeds(),
      state: ShamblerState.Pursue,
      ticksToTurn: 100000,
      ticksCommitted: 0,
      ticksMilling: 0,
      ticksStaggered: 0,
      bias: 0,
    });
    makeBody(booted.world, zombie);
  }

  step(booted.world);
  expect(booted.world.components.getOrThrow(survivor, Grabbed).sources).toEqual(zombies);
  return { ...booted, survivor, zombies };
}

function bodyTotal(body: Body): number {
  return Object.values(body).reduce((sum, value) => sum + (value ?? 0), 0);
}

describe("grab contact", () => {
  it("pins movement and makes F a struggle instead of a swing", () => {
    const { world, survivor } = grabbedBy(1, { loadout: "dev" });
    const before = { ...world.components.getOrThrow(survivor, Position) };
    const staminaBefore = world.components.getOrThrow(survivor, Stamina).current;

    world.commands.push({ type: "move", dx: 1, dy: 0 });
    world.commands.push({ type: "swing" });
    step(world);

    expect(world.components.getOrThrow(survivor, Position)).toEqual(before);
    expect(world.components.getOrThrow(survivor, Swing).state).toBe(SwingState.Idle);
    expect(world.components.getOrThrow(survivor, Grabbed).struggleTicks).toBe(
      SHAMBLER_TUNING.struggleTicks - 1,
    );
    expect(world.components.getOrThrow(survivor, Stamina).current).toBe(
      staminaBefore - SHAMBLER_TUNING.struggleStamina,
    );

    // Input during the committed second does not queue another attempt or spend twice.
    world.commands.push({ type: "swing" });
    step(world);
    expect(world.components.getOrThrow(survivor, Stamina).current).toBe(
      staminaBefore - SHAMBLER_TUNING.struggleStamina,
    );
  });

  it("interrupts a wind-up when contact becomes a hold", () => {
    const booted = boot({
      seed: SEED,
      wanderers: 0,
      mapSize: 64,
      loadout: "dev",
      disabled: ["attention", "field-memory"],
    });
    const survivor = booted.player as EntityId;
    const here = booted.world.components.getOrThrow(survivor, Position);
    const zombie = booted.world.spawn();
    booted.world.components.set(zombie, Position, { ...here });
    booted.world.components.set(zombie, Velocity, { dx: 0, dy: 0 });
    booted.world.components.set(zombie, Shambler, {
      ...defaultShamblerSpeeds(),
      state: ShamblerState.Pursue,
      ticksToTurn: 100000,
      ticksCommitted: 0,
      ticksMilling: 0,
      ticksStaggered: 0,
      bias: 0,
    });

    booted.world.commands.push({ type: "swing" });
    step(booted.world);

    expect(booted.world.components.has(survivor, Grabbed)).toBe(true);
    expect(booted.world.components.getOrThrow(survivor, Swing)).toEqual({
      state: SwingState.Idle,
      ticksLeft: 0,
    });
  });

  it("releases a hold when the grabber is staggered", () => {
    const { world, survivor, zombies } = grabbedBy(1);
    world.events.publish({ type: "entity.staggered", entity: zombies[0] as EntityId, ticks: 10 });
    world.events.drain();

    expect(world.components.has(survivor, Grabbed)).toBe(false);
    expect(world.components.has(zombies[0] as EntityId, GrabState)).toBe(false);
  });
});

describe("escape contest", () => {
  it("gets progressively harder without ever becoming impossible", () => {
    const one = escapeChance(0.5);
    const two = escapeChance(1);
    const three = escapeChance(1.5);

    expect(one).toBeCloseTo(2 / 3);
    expect(two).toBeCloseTo(1 / 2);
    expect(three).toBeCloseTo(2 / 5);
    expect(one).toBeGreaterThan(two);
    expect(two).toBeGreaterThan(three);
    expect(three).toBeGreaterThan(0);
  });

  it("keeps knife play inside grab range while bat and spear can buy space", () => {
    expect(WEAPONS.knife.reachMetres).toBeLessThan(SHAMBLER_TUNING.grabMetres);
    expect(WEAPONS.bat.reachMetres).toBeGreaterThan(SHAMBLER_TUNING.grabMetres);
    expect(WEAPONS.spear.reachMetres).toBeGreaterThan(WEAPONS.bat.reachMetres);
    expect(SHAMBLER_TUNING.grabMetres).toBeLessThan(SHAMBLER_TUNING.contactMetres);
  });

  it("one successful struggle releases every grabber", () => {
    const { world, survivor, zombies } = grabbedBy(3);
    // Remove randomness while retaining the real contest and timing path.
    for (const zombie of zombies) world.components.getOrThrow(zombie, Shambler).grabStrength = 0;

    world.commands.push({ type: "swing" });
    step(world);
    stepN(world, SHAMBLER_TUNING.struggleTicks - 1);

    expect(world.components.has(survivor, Grabbed)).toBe(false);
    for (const zombie of zombies) expect(world.components.has(zombie, GrabState)).toBe(false);
  });
});

describe("bite consequences", () => {
  it("delays the first bite, then creates damage, a located wound, and private exposure", () => {
    const { world, survivor } = grabbedBy(1);
    const before = bodyTotal(world.components.getOrThrow(survivor, Body));

    stepN(world, SHAMBLER_TUNING.firstBiteTicks - 1);
    expect(world.components.getOrThrow(survivor, Injuries).wounds).toHaveLength(0);
    expect(world.components.get(survivor, ZombieInfection)).toBeUndefined();

    step(world);

    const wounds = world.components.getOrThrow(survivor, Injuries).wounds;
    const exposures = world.components.getOrThrow(survivor, ZombieInfection).exposures;
    expect(bodyTotal(world.components.getOrThrow(survivor, Body))).toBe(
      before - SHAMBLER_TUNING.biteDamage,
    );
    expect(wounds).toHaveLength(1);
    expect(wounds[0]?.kind).toBe("bite");
    expect(["bite", "scratch"]).toContain(wounds[0]?.presentation);
    expect(exposures).toHaveLength(1);
    expect(exposures[0]?.bodyPart).toBe(wounds[0]?.bodyPart);
    expect(typeof exposures[0]?.transmitted).toBe("boolean");

    // The UI sees the wound's presentation, never the infection roll or even its field name.
    expect(JSON.stringify(conditionView(world, survivor))).not.toContain("transmitted");
  });

  it("pins the agreed calibration without inventing the Milestone 2 disease timeline", () => {
    expect(SHAMBLER_TUNING.firstBiteTicks).toBe(30);
    expect(SHAMBLER_TUNING.repeatBiteTicks).toBe(40);
    expect(BITE_TRANSMISSION_CHANCE).toBe(0.85);
    expect(BITE_PRESENTS_AS_SCRATCH_CHANCE).toBe(0.3);
  });

  it("saves a hold, its wound, and its private roll into the same deterministic future", () => {
    const straight = grabbedBy(2);
    stepN(straight.world, SHAMBLER_TUNING.firstBiteTicks + 5);
    const text = encodeSave(createSave(straight.world));

    const resumed = boot({
      seed: SEED,
      wanderers: 0,
      mapSize: 64,
      disabled: ["attention", "field-memory"],
    });
    applySave(resumed.world, decodeSave(text));

    stepN(straight.world, SHAMBLER_TUNING.repeatBiteTicks + 5);
    stepN(resumed.world, SHAMBLER_TUNING.repeatBiteTicks + 5);

    expect(resumed.world.serialize()).toBe(straight.world.serialize());
  });
});
