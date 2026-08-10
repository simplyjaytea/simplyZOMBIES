import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import {
  MELEE_CONNECT_NOISE,
  recoverTicks,
  swingStamina,
  WEAPONS,
  windupTicks,
  ZOMBIE_BODY,
  type WeaponProfile,
} from "../../src/sim/combat";
import type { GameEvent } from "../../src/sim/events";
import { Facing, Position, Velocity } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { step, stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { Body, makeBody, Stamina } from "../../src/sim/modules/health";
import { makeMeleeArmed, MeleeWeapon, Swing, SwingState } from "../../src/sim/modules/melee";
import { Controlled } from "../../src/sim/modules/player";

/**
 * A survivor alone on open ground, facing due east, with a target placed exactly where the
 * caller asks. No wanderers, so nothing walks into frame and confuses a result.
 */
function duel(options: { weapon?: keyof typeof WEAPONS; at?: [number, number] } = {}) {
  const { world, player } = boot({ seed: 41, wanderers: 0, mapSize: 64 });
  const attacker = player as EntityId;
  makeMeleeArmed(world, attacker, WEAPONS[options.weapon ?? "bat"]);

  const from = world.components.getOrThrow(attacker, Position);
  world.components.getOrThrow(attacker, Facing).radians = 0; // due east

  let target: EntityId | null = null;
  if (options.at !== undefined) {
    target = world.spawn();
    world.components.set(target, Position, {
      x: from.x + options.at[0],
      y: from.y + options.at[1],
    });
    world.components.set(target, Velocity, { dx: 0, dy: 0 });
    world.components.set(target, Facing, { radians: 0 });
    makeBody(world, target);
  }
  return { world, attacker, target };
}

const swingOf = (world: World, entity: EntityId) => world.components.getOrThrow(entity, Swing);

/**
 * Step, keeping every event.
 *
 * `world.events.drained` is cleared at the top of each tick -- it is *this tick's* record,
 * not a log -- so anything watching for a blow that lands several ticks after the key was
 * pressed has to accumulate as it goes.
 */
function stepCollecting(world: World, ticks: number, into: GameEvent[]): GameEvent[] {
  for (let i = 0; i < ticks; i++) {
    step(world);
    into.push(...world.events.drained);
  }
  return into;
}

const connects = (events: readonly GameEvent[]) =>
  events.filter((e) => e.type === "attack.connected");

/** Press the key, then run until the blow has landed and the recovery has run out. */
function swingThrough(world: World, weapon: WeaponProfile = WEAPONS.bat): GameEvent[] {
  world.commands.push({ type: "swing" });
  return stepCollecting(world, windupTicks(weapon.weight) + recoverTicks(weapon.weight) + 1, []);
}

describe("the swing loop", () => {
  it("runs wind-up, then recovery, for exactly the ticks the weapon declares", () => {
    const { world, attacker } = duel();
    const w = WEAPONS.bat;

    expect(swingOf(world, attacker).state).toBe(SwingState.Idle);

    world.commands.push({ type: "swing" });
    step(world);
    expect(swingOf(world, attacker).state).toBe(SwingState.WindUp);

    // The tick the wind-up was started on already spent one of its ticks in the combat phase.
    stepN(world, windupTicks(w.weight) - 1);
    expect(swingOf(world, attacker).state).toBe(SwingState.Recover);

    stepN(world, recoverTicks(w.weight) - 1);
    expect(swingOf(world, attacker).state).toBe(SwingState.Recover);

    step(world);
    expect(swingOf(world, attacker).state).toBe(SwingState.Idle);
  });

  it("spends stamina when the swing starts, not when it lands", () => {
    const { world, attacker } = duel();
    const cost = swingStamina(WEAPONS.bat.weight);

    world.commands.push({ type: "swing" });
    step(world);
    expect(world.components.getOrThrow(attacker, Stamina).current).toBe(100 - cost);
  });

  it("refuses to start when there is not enough stamina left to pay for it", () => {
    const { world, attacker } = duel();
    world.components.getOrThrow(attacker, Stamina).current = 0;

    world.commands.push({ type: "swing" });
    step(world);
    expect(swingOf(world, attacker).state).toBe(SwingState.Idle);
  });

  it("ignores a second press inside a window, rather than buffering it", () => {
    // An input buffer would let a player pre-pay for a window they have not survived yet.
    const { world, attacker } = duel();
    const cost = swingStamina(WEAPONS.bat.weight);

    world.commands.push({ type: "swing" });
    step(world);
    world.commands.push({ type: "swing" });
    world.commands.push({ type: "swing" });
    step(world);

    expect(world.components.getOrThrow(attacker, Stamina).current).toBe(100 - cost);
  });
});

describe("interruptibility", () => {
  it("loses a wind-up to a sprint, and does not refund the stamina", () => {
    const { world, attacker } = duel();
    const cost = swingStamina(WEAPONS.bat.weight);

    world.commands.push({ type: "swing" });
    step(world);
    world.commands.push({ type: "sprint", active: true });
    step(world);

    expect(swingOf(world, attacker).state).toBe(SwingState.Idle);
    expect(world.components.getOrThrow(attacker, Stamina).current).toBe(100 - cost);
  });

  it("does not let a sprint escape a recovery", () => {
    // docs/09: being caught in recovery is how melee kills you. A sprint out of it would
    // delete the only window that has teeth.
    const { world, attacker } = duel();
    world.commands.push({ type: "swing" });
    stepN(world, windupTicks(WEAPONS.bat.weight));
    expect(swingOf(world, attacker).state).toBe(SwingState.Recover);

    world.commands.push({ type: "sprint", active: true });
    step(world);
    expect(swingOf(world, attacker).state).toBe(SwingState.Recover);
  });

  it("loses a wind-up to being staggered", () => {
    const { world, attacker } = duel();
    world.commands.push({ type: "swing" });
    step(world);

    world.events.publish({ type: "entity.staggered", entity: attacker, ticks: 10 });
    step(world);
    expect(swingOf(world, attacker).state).toBe(SwingState.Idle);
  });

  it("reads facing when the blow lands, not when the key was pressed", () => {
    // The whole reason a wind-up is a window. Start the swing pointed at something, turn
    // away before it lands, and it has to miss.
    const { world } = duel({ at: [1.0, 0] });
    const attacker = world.components.query(Position, Controlled)[0] as EntityId;

    world.commands.push({ type: "swing" });
    step(world);
    world.components.getOrThrow(attacker, Facing).radians = Math.PI; // about-face

    const events = stepCollecting(world, windupTicks(WEAPONS.bat.weight), []);
    expect(connects(events)).toHaveLength(0);
  });
});

describe("reach and arc", () => {
  it("connects with something dead ahead and inside reach", () => {
    const { world, target } = duel({ at: [1.0, 0] });
    expect(connects(swingThrough(world)).map((e) => e.target)).toEqual([target]);
  });

  it("misses the same body just outside reach", () => {
    // Reach is centre-to-centre plus the target's half-width; a bat reaches 1.4 + 0.35.
    const { world } = duel({ at: [WEAPONS.bat.reachMetres + 0.4, 0] });
    expect(connects(swingThrough(world))).toHaveLength(0);
  });

  it("misses a body inside reach but outside the arc", () => {
    // Directly behind, at point-blank. docs/09: your arc covers one of them at a time.
    const { world } = duel({ at: [-1.0, 0] });
    expect(connects(swingThrough(world))).toHaveLength(0);
  });

  it("gives a spear a hit a knife cannot reach", () => {
    // docs/09's reach, made falsifiable: "a spear connects from where a knife does not".
    const between: [number, number] = [1.8, 0];

    const knife = duel({ weapon: "knife", at: between });
    expect(connects(swingThrough(knife.world, WEAPONS.knife))).toHaveLength(0);

    const spear = duel({ weapon: "spear", at: between });
    expect(connects(swingThrough(spear.world, WEAPONS.spear)).map((e) => e.target)).toEqual([
      spear.target,
    ]);
  });

  it("hits the nearest of several bodies in the arc, and only one", () => {
    const { world } = duel({ at: [1.2, 0] });
    const from = world.components.query(Position, Controlled)[0] as EntityId;
    const origin = world.components.getOrThrow(from, Position);

    const closer = world.spawn();
    world.components.set(closer, Position, { x: origin.x + 0.6, y: origin.y });
    makeBody(world, closer);

    const landed = connects(swingThrough(world));
    expect(landed).toHaveLength(1);
    expect(landed[0]?.target).toBe(closer);
  });
});

describe("what a connect states", () => {
  it("emits exactly the calibrated melee magnitude, and a miss emits nothing", () => {
    const hit = duel({ at: [1.0, 0] });
    const landed = swingThrough(hit.world).filter((e) => e.type === "noise.emitted");
    expect(landed.map((e) => e.magnitude)).toEqual([MELEE_CONNECT_NOISE]);

    const miss = duel({ at: [-1.0, 0] });
    const missed = swingThrough(miss.world).filter((e) => e.type === "noise.emitted");
    expect(missed).toHaveLength(0);
  });

  it("staggers what it hits, for the weapon's own duration", () => {
    const { world, target } = duel({ at: [1.0, 0] });
    expect(swingThrough(world)).toContainEqual({
      type: "entity.staggered",
      entity: target,
      ticks: WEAPONS.bat.staggerTicks,
    });
  });

  it("kills outright on a head strike, and takes several swings otherwise", () => {
    // docs/09: "a clean head strike is instant; anything else takes multiple hits."
    const { world, target } = duel({ at: [1.0, 0] });
    const t = target as EntityId;

    let swings = 0;
    while (world.entities.isAlive(t) && swings < 60) {
      swingThrough(world);
      swings++;
    }

    expect(world.entities.isAlive(t)).toBe(false);
    // It must not be a one-swing certainty, or "kill quality" means nothing.
    expect(swings).toBeGreaterThan(1);
  });

  it("wears a body down on the parts it actually struck", () => {
    const { world, target } = duel({ at: [1.0, 0] });
    swingThrough(world);
    const body = world.components.getOrThrow(target as EntityId, Body);
    const lost =
      ZOMBIE_BODY.head -
      body.head +
      (ZOMBIE_BODY.torso - body.torso) +
      (ZOMBIE_BODY.legs - body.legs);
    expect(lost).toBeGreaterThan(0);
  });

  it("does not swing at all with the module disabled, and the world still runs", () => {
    const { world } = boot({ seed: 41, wanderers: 5, mapSize: 64, disabled: ["melee"] });
    world.commands.push({ type: "swing" });
    const events: GameEvent[] = [];
    expect(() => stepCollecting(world, 40, events)).not.toThrow();
    expect(connects(events)).toHaveLength(0);
  });

  it("swings but connects with nothing when health is disabled", () => {
    // Nothing has a Body, so there is no valid target -- coherent rather than crashing.
    const { world } = boot({ seed: 41, wanderers: 20, mapSize: 32, disabled: ["health"] });
    world.commands.push({ type: "swing" });
    const events: GameEvent[] = [];
    expect(() => stepCollecting(world, 40, events)).not.toThrow();
    expect(connects(events)).toHaveLength(0);
  });
});

describe("weapon profiles", () => {
  it("orders reach the way the design says, and keeps it distinct from damage", () => {
    expect(WEAPONS.knife.reachMetres).toBeLessThan(WEAPONS.bat.reachMetres);
    expect(WEAPONS.bat.reachMetres).toBeLessThan(WEAPONS.spear.reachMetres);
    // The spear out-reaches the bat while doing less damage, or reach is just a damage stat.
    expect(WEAPONS.spear.damage).toBeLessThan(WEAPONS.bat.damage);
    // Blunt staggers better than blades (docs/09).
    expect(WEAPONS.bat.staggerTicks).toBeGreaterThan(WEAPONS.spear.staggerTicks);
    expect(WEAPONS.spear.staggerTicks).toBeGreaterThan(WEAPONS.knife.staggerTicks);
  });

  it("makes a heavier weapon slower and dearer, through one weight", () => {
    expect(windupTicks(WEAPONS.bat.weight)).toBeGreaterThan(windupTicks(WEAPONS.knife.weight));
    expect(recoverTicks(WEAPONS.bat.weight)).toBeGreaterThan(recoverTicks(WEAPONS.knife.weight));
    expect(swingStamina(WEAPONS.bat.weight)).toBeGreaterThan(swingStamina(WEAPONS.knife.weight));
  });

  it("carries a weapon and an idle swing on the survivor from boot", () => {
    const { world, player } = boot({ seed: 41, wanderers: 0, mapSize: 32 });
    const p = player as EntityId;
    expect(world.components.getOrThrow(p, MeleeWeapon)).toEqual({ ...WEAPONS.bat });
    expect(world.components.getOrThrow(p, Swing)).toEqual({ state: SwingState.Idle, ticksLeft: 0 });
  });
});
