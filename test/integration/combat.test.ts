// The melee loop, against the contract docs/09-combat.md sets for it.
//
// The through-line of this file is that melee's *costs* are what make it a real choice --
// stamina, exposure, and the fact that a crowd is categorically rather than numerically
// dangerous. A combat system where swinging is free would pass a test suite that only
// checked that swinging works, and it would break the parity contract in docs/09 that the
// whole design of weapons rests on.
//
// Weapon numbers are asserted against `content/weapons/*.json` rather than against
// constants in the module, because the claim being tested is that a new weapon is data.

import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { boot, type BootOptions } from "../../src/sim/boot";
import { Position, SURVIVOR_TAG, Tags, Velocity } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import type { GameEvent } from "../../src/sim/events";
import { stepN } from "../../src/sim/kernel/step";
import { applySave, createSave, decodeSave, encodeSave } from "../../src/sim/kernel/save";
import { fingerprint } from "../../src/sim/kernel/serialize";
import type { World } from "../../src/sim/kernel/world";
import { Body, Grabbed, Grabber, Melee, Staggered } from "../../src/sim/modules/combat";
import { makeBody, makeGrabber } from "../../src/sim/modules/combat";
import { makeZombie, Zombie } from "../../src/sim/modules/zombies";
import { SCENARIOS } from "../../bench/scenarios";

const CONTENT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../content");
/** Mirrors combat.ts's STRUGGLE_STAMINA_PER_TICK: below this, struggling stops entirely. */
const STRUGGLE_COST_PER_TICK = 4;
const SEED = 20260806;

function bootWithContent(options: BootOptions) {
  const booted = boot(options);
  booted.world.content.load(
    readContentFromDisk(CONTENT_ROOT),
    createSchemaValidator(readSchemasFromDisk(CONTENT_ROOT)),
    booted.world.stats,
  );
  return booted;
}

/**
 * A player with a weapon, on open ground, and nothing else.
 *
 * `zombies: 0` because these tests place their opponents deliberately: a scattered horde
 * makes "did the swing reach it" a question about spawn luck.
 */
function arena(options: { weapon?: string; disabled?: string[] } = {}) {
  const booted = bootWithContent({
    seed: SEED,
    wanderers: 0,
    zombies: 0,
    mapSize: 64,
    weapon: options.weapon ?? "weapon.machete",
    disabled: options.disabled ?? ["wander", "zombies"],
  });
  const player = booted.player as EntityId;
  const at = booted.world.components.getOrThrow(player, Position);
  return { ...booted, player, origin: { x: at.x, y: at.y } };
}

/** Put a shambler at an exact offset from the player, with a real body and real grip. */
function placeZombie(
  world: World,
  x: number,
  y: number,
  options: { grabs?: boolean; body?: { head: number; torso: number; legs: number } } = {},
): EntityId {
  const entity = world.spawn();
  world.components.set(entity, Position, { x, y });
  world.components.set(entity, Velocity, { dx: 0, dy: 0 });
  makeZombie(world, entity, world.rng.stream("placement"));
  makeBody(world, entity, options.body ?? { head: 25, torso: 60, legs: 40 });
  if (options.grabs !== false) makeGrabber(world, entity, 0.5);
  return entity;
}

/** Collect events of one type for the length of a run. */
function record<T extends GameEvent["type"]>(
  world: World,
  type: T,
): Extract<GameEvent, { type: T }>[] {
  const seen: Extract<GameEvent, { type: T }>[] = [];
  world.events.subscribe({
    id: `test.record.${type}`,
    type,
    handler: (event) => seen.push(event as Extract<GameEvent, { type: T }>),
  });
  return seen;
}

/** Hold the attack button for `ticks` ticks. */
function swingFor(world: World, ticks: number): void {
  for (let i = 0; i < ticks; i++) {
    world.commands.push({ type: "attack" });
    stepN(world, 1);
  }
}

describe("the swing loop", () => {
  it("winds up, connects, and recovers", () => {
    // docs/09: "wind-up -> connect or miss -> recovery. All three are interruptible windows."
    const { world, origin } = arena();
    placeZombie(world, origin.x + 0.85, origin.y, { grabs: false });
    const connects = record(world, "attack.connected");
    const melee = world.components.getOrThrow(world.components.query(Melee)[0] as EntityId, Melee);

    world.commands.push({ type: "attack" });
    stepN(world, 1);
    expect(melee.state).toBe("windup");

    // The machete's 3 wind-up ticks, from content -- not a number this test invented.
    stepN(world, 3);
    expect(connects).toHaveLength(1);
    expect(melee.state).toBe("recover");

    stepN(world, 4);
    expect(melee.state).toBe("ready");
  });

  it("loses the swing when the wind-up is interrupted", () => {
    // The window is interruptible in both directions, and this is the one that costs you:
    // the stamina is spent and the swing never lands.
    const { world, player, origin } = arena();
    placeZombie(world, origin.x + 0.85, origin.y, { grabs: false });
    const connects = record(world, "attack.connected");

    world.commands.push({ type: "attack" });
    stepN(world, 1);
    const melee = world.components.getOrThrow(player, Melee);
    expect(melee.state).toBe("windup");
    const spent = melee.stamina;

    // Something hits them mid-wind-up.
    world.components.set(player, Staggered, { ticksLeft: 10 });
    stepN(world, 4);

    expect(connects).toHaveLength(0);
    expect(melee.state).toBe("ready");
    // And the cost stands. A cancelled swing must not refund what it spent, or being
    // interrupted would be free and a crowd would stop being dangerous. Ordinary
    // regeneration (0.6 a tick, over the 4 ticks since) is all that may come back.
    expect(melee.stamina).toBeLessThan(melee.staminaMax);
    expect(melee.stamina).toBeLessThanOrEqual(spent + 4 * 0.6 + 1e-9);
  });
});

describe("reach", () => {
  // docs/09: "a spear outranges a knife and that matters more than damage." The two runs
  // differ only in which JSON file the survivor is holding.
  const GAP = 1.8; // metres: outside the machete's 1.0, inside the spear's 2.2

  function connectsAt(weapon: string, gap: number): boolean {
    const { world, origin } = arena({ weapon });
    placeZombie(world, origin.x + gap, origin.y, { grabs: false });
    const connects = record(world, "attack.connected");
    swingFor(world, 20);
    return connects.length > 0;
  }

  it("decides who lands a hit, from content alone", () => {
    expect(connectsAt("weapon.spear", GAP)).toBe(true);
    expect(connectsAt("weapon.machete", GAP)).toBe(false);
  });

  it("also decides how exposed connecting leaves you", () => {
    // The other half of docs/09's claim, and the reason reach is not simply better damage:
    // the risk of taking a bite back on a connect is divided by reach.
    const near = biteRateWhileFighting("weapon.machete");
    const far = biteRateWhileFighting("weapon.spear");
    expect(near).toBeGreaterThan(far * 1.5);
  });

  /**
   * Bites taken *per connect* over a long fight against an endless opponent.
   *
   * Per connect rather than per tick, because the weapons swing at different speeds: a
   * spear that lands half as often would look safer on a tick count without being safer.
   *
   * The dummy stands at 0.95 m -- inside both weapons' reach and outside a grab's 0.9 m.
   * That gap is deliberately narrow, and the narrowness is itself the finding: no weapon
   * with reach under 0.9 m can strike from outside grab range at all, so bare hands mean
   * fighting from inside it.
   */
  function biteRateWhileFighting(weapon: string): number {
    const { world, player, origin } = arena({ weapon });
    placeZombie(world, origin.x + 0.95, origin.y, {
      body: { head: 1e6, torso: 1e6, legs: 1e6 },
    });
    const bites = record(world, "bite.landed");
    const connects = record(world, "attack.connected");
    // Stamina would otherwise stop the comparison early, and an exhausted swing misses --
    // which would measure exhaustion rather than reach.
    const melee = world.components.getOrThrow(player, Melee);
    for (let i = 0; i < 4000; i++) {
      melee.stamina = melee.staminaMax;
      world.commands.push({ type: "attack" });
      stepN(world, 1);
    }
    expect(connects.length).toBeGreaterThan(100);
    return bites.filter((b) => b.victim === player).length / connects.length;
  }
});

describe("stamina", () => {
  it("costs more per swing for a heavier weapon", () => {
    // docs/09: "stamina per swing, scaled by weapon weight." The spear is the heavy option
    // in content/weapons, so it should empty the tank in fewer swings than the machete.
    function swingsBeforeExhausted(weapon: string): number {
      const { world, player, origin } = arena({ weapon });
      placeZombie(world, origin.x + 0.6, origin.y, {
        grabs: false,
        body: { head: 1e6, torso: 1e6, legs: 1e6 },
      });
      const melee = world.components.getOrThrow(player, Melee);
      let swings = 0;
      for (let i = 0; i < 600 && !melee.weak; i++) {
        const before = melee.state;
        world.commands.push({ type: "attack" });
        stepN(world, 1);
        if (before === "ready" && melee.state === "windup") swings++;
      }
      return swings;
    }

    expect(swingsBeforeExhausted("weapon.spear")).toBeLessThan(
      swingsBeforeExhausted("weapon.machete"),
    );
  });

  it("makes an exhausted swing slow and weak", () => {
    // "Exhausted swings are slow, weak, and miss."
    const { world, player, origin } = arena();
    const target = placeZombie(world, origin.x + 0.85, origin.y, { grabs: false });
    const melee = world.components.getOrThrow(player, Melee);
    const body = world.components.getOrThrow(target, Body);

    melee.stamina = 0;
    world.commands.push({ type: "attack" });
    stepN(world, 1);

    expect(melee.weak).toBe(true);
    // The machete's 3 wind-up ticks, doubled. Slow is a real cost, not a label.
    expect(melee.ticksLeft).toBe(6);

    const start = body.head + body.torso + body.legs;
    stepN(world, 6);
    const dealt = start - (body.head + body.torso + body.legs);
    // Half damage when it lands at all, and 0 when the miss roll takes it.
    expect(dealt).toBeLessThanOrEqual(7);
  });
});

describe("grabs", () => {
  it("stops a survivor moving, without the player module knowing what a grab is", () => {
    // The immobilisation travels through the modifier pipeline (docs/21's mechanism 2), so
    // this also asserts the decoupling: modules/player.ts contains no reference to combat.
    const { world, player, origin } = arena({ disabled: ["wander"] });
    placeZombie(world, origin.x + 0.5, origin.y);

    world.commands.push({ type: "move", dx: -1, dy: 0 });
    stepN(world, 30);

    expect(world.components.has(player, Grabbed)).toBe(true);
    const held = world.components.getOrThrow(player, Position);
    const heldAt = { x: held.x, y: held.y };

    stepN(world, 40);
    expect(held.x).toBeCloseTo(heldAt.x, 6);
    expect(held.y).toBeCloseTo(heldAt.y, 6);
    expect(world.modifiers.resolve("move_speed", player)).toBe(0);
  });

  it("takes twice the work to shed two holds as one", () => {
    // docs/09: "being grabbed by two at once is usually terminal." That has to fall out of
    // the arithmetic rather than out of a rule about the number two, or the third grab
    // would need its own special case.
    function ticksToBreakFree(grabbers: number): number {
      const { world, player, origin } = arena({ disabled: ["wander", "zombies"] });
      for (let i = 0; i < grabbers; i++) {
        placeZombie(world, origin.x + 0.5, origin.y + i * 0.1);
      }
      stepN(world, 2); // let the holds land
      expect(world.components.getOrThrow(player, Grabbed).by).toHaveLength(grabbers);

      const melee = world.components.getOrThrow(player, Melee);
      for (let i = 0; i < 400; i++) {
        melee.stamina = melee.staminaMax; // measuring the hold, not the tank
        world.commands.push({ type: "attack" });
        stepN(world, 1);
        if (!world.components.has(player, Grabbed)) return i + 1;
      }
      return Infinity;
    }

    const one = ticksToBreakFree(1);
    const two = ticksToBreakFree(2);
    expect(one).toBeLessThan(Infinity);
    expect(two).toBeGreaterThanOrEqual(one * 2);
  });

  it("bites while it holds you, and the bite is recorded rather than resolved", () => {
    // Milestone 1 owns "a bite happened". docs/06's five-stage timeline is Milestone 2, so
    // the event exists and nothing downstream consumes it yet -- deliberately.
    const { world, player, origin } = arena({ disabled: ["wander", "zombies"] });
    placeZombie(world, origin.x + 0.5, origin.y);
    const bites = record(world, "bite.landed");

    stepN(world, 600);
    expect(bites.length).toBeGreaterThan(0);
    expect(bites.every((b) => b.victim === player)).toBe(true);
  });
});

describe("a crowd is categorically dangerous, not numerically", () => {
  it("pins a survivor who lets more than a couple close", () => {
    // docs/09: "fighting one is a skill check; fighting three is a check you fail once and
    // then can't retry." Found by measuring the breach benchmark rather than by design:
    // over 600 ticks it recorded 95 grabs and 2 connects, because the attack button is
    // spent struggling and the work to shed a hold scales with how many there are.
    //
    // Worth an assertion rather than a note, because it is the property that makes
    // positioning the whole tactical layer -- and it would be easy to "fix" by accident.
    const { world, player, origin } = arena({ disabled: ["wander", "zombies"] });
    for (let i = 0; i < 6; i++) placeZombie(world, origin.x + 0.5, origin.y + i * 0.05);

    const melee = world.components.getOrThrow(player, Melee);
    world.components.getOrThrow(player, Body).torso = 1e6; // outlive the bites, to be sure

    // Let the crowd close first. Swings do land in the couple of seconds before they all
    // get hold of you, and that is the point -- the trap is closing, not instantaneous.
    // Stamina is left alone throughout: running out is the mechanism, not an artefact.
    for (let i = 0; i < 100; i++) {
      world.commands.push({ type: "attack" });
      stepN(world, 1);
    }

    // From here on, nothing. Every tick of the attack button goes into a hold that needs
    // six times the work of one, against a tank that no longer refills.
    const connects = record(world, "attack.connected");
    for (let i = 0; i < 500; i++) {
      world.commands.push({ type: "attack" });
      stepN(world, 1);
    }
    expect(melee.stamina).toBeLessThan(STRUGGLE_COST_PER_TICK);

    expect(world.components.getOrThrow(player, Grabbed).by.length).toBeGreaterThan(1);
    expect(connects).toHaveLength(0);
  });

  it("still lets one be shed, or the mechanic would just be a death sentence", () => {
    // The control. If a single grab were also unrecoverable, the interesting part -- how
    // many you let close -- would not exist.
    const { world, player, origin } = arena({ disabled: ["wander", "zombies"] });
    placeZombie(world, origin.x + 0.5, origin.y);

    for (let i = 0; i < 200; i++) {
      world.commands.push({ type: "attack" });
      stepN(world, 1);
      if (!world.components.has(player, Grabbed)) return;
    }
    throw new Error("never broke free of a single grab");
  });
});

describe("the damage model", () => {
  // docs/14: "meaningful damage is to the head or to locomotion. Body damage slows and
  // staggers but doesn't stop them."

  it("kills on the head and nothing else", () => {
    const { world, origin } = arena();
    const target = placeZombie(world, origin.x + 0.6, origin.y, {
      grabs: false,
      body: { head: 1, torso: 1e6, legs: 1e6 },
    });
    const killed = record(world, "entity.killed");

    swingFor(world, 400);
    expect(killed.some((k) => k.entity === target)).toBe(true);
  });

  it("leaves a crawler when locomotion goes, and a crawler is still lethal", () => {
    const { world, origin } = arena({ disabled: ["wander"] });
    const target = placeZombie(world, origin.x + 0.6, origin.y, {
      body: { head: 1e6, torso: 1e6, legs: 1 },
    });

    swingFor(world, 400);
    const body = world.components.getOrThrow(target, Body);

    expect(body.crawling).toBe(true);
    expect(body.dead).toBe(false);
    // Slower, through the same modifier pipeline a grab uses -- so the zombie module
    // applies it without knowing a fight caused it.
    expect(world.modifiers.resolve("move_speed", target)).toBeLessThan(1);
    // Still holding on. "A zombie with a shattered pelvis crawls and is still perfectly
    // capable of biting an ankle."
    expect(world.components.get(target, Grabber)?.holding).not.toBeUndefined();
  });

  it("does not stop them when the damage is all body", () => {
    const { world, origin } = arena();
    const target = placeZombie(world, origin.x + 0.6, origin.y, {
      grabs: false,
      body: { head: 1e6, torso: 1, legs: 1e6 },
    });

    swingFor(world, 200);
    const body = world.components.getOrThrow(target, Body);
    expect(body.torso).toBe(0);
    expect(body.dead).toBe(false);
    expect(body.crawling).toBe(false);
  });
});

describe("a fight is a noise event", () => {
  it("draws the neighbours toward the fighting", () => {
    // The loop closing: melee writes into the attention field that the horde reads, so
    // fighting decides where the next of them arrive. docs/03 puts a connect at ~11 m --
    // "a fight draws the neighbours, not the block" -- so this is measured at that scale.
    function meanDistance(swinging: boolean): number {
      const { world, origin } = arena({ weapon: "weapon.bat", disabled: ["wander"] });
      // The thing being hit. Unkillable, so the noise keeps coming for the whole run.
      placeZombie(world, origin.x + 0.7, origin.y, {
        grabs: false,
        body: { head: 1e6, torso: 1e6, legs: 1e6 },
      });

      const ring: EntityId[] = [];
      for (let i = 0; i < 12; i++) {
        const angle = (i / 12) * Math.PI * 2;
        ring.push(
          placeZombie(world, origin.x + Math.cos(angle) * 9, origin.y + Math.sin(angle) * 9, {
            grabs: false,
          }),
        );
      }

      for (let i = 0; i < 500; i++) {
        if (swinging) world.commands.push({ type: "attack" });
        stepN(world, 1);
      }

      let total = 0;
      for (const entity of ring) {
        const pos = world.components.getOrThrow(entity, Position);
        total += Math.hypot(pos.x - origin.x, pos.y - origin.y);
      }
      return total / ring.length;
    }

    const fighting = meanDistance(true);
    const quiet = meanDistance(false);

    // The control is what makes this capable of failing: same seed, same ring, same
    // punching bag, and the only difference is whether the survivor swung.
    expect(fighting).toBeLessThan(quiet);
  });
});

describe("combat is part of the deterministic record", () => {
  it("reproduces a fight byte-for-byte from the same seed and input", () => {
    function fight(): string {
      const { world, origin } = arena({ disabled: ["wander"] });
      for (let i = 0; i < 6; i++) {
        placeZombie(world, origin.x + 0.5 + i * 0.3, origin.y + i * 0.2);
      }
      for (let i = 0; i < 300; i++) {
        if (i % 3 === 0) world.commands.push({ type: "attack" });
        if (i % 7 === 0) world.commands.push({ type: "move", dx: 1, dy: 0 });
        stepN(world, 1);
      }
      return fingerprint(world.serialize());
    }

    expect(fight()).toBe(fight());
  });

  it("restores a save taken mid-swing still mid-swing", () => {
    // Otherwise loading would be a way to cancel the recovery window, which docs/09 makes
    // the thing that gets you killed -- a save-scum that undoes the cost of a swing.
    const { world, player, origin } = arena({ disabled: ["wander"] });
    placeZombie(world, origin.x + 0.85, origin.y, { grabs: false });

    world.commands.push({ type: "attack" });
    stepN(world, 5); // resolved, and now recovering

    const melee = world.components.getOrThrow(player, Melee);
    expect(melee.state).toBe("recover");
    const saved = encodeSave(createSave(world));
    const during = { state: melee.state, ticksLeft: melee.ticksLeft, stamina: melee.stamina };

    stepN(world, 60);
    expect(world.components.getOrThrow(player, Melee).state).toBe("ready");

    applySave(world, decodeSave(saved));
    expect(world.components.getOrThrow(player, Melee)).toEqual(expect.objectContaining(during));
  });
});

describe("when the player dies", () => {
  it("says so and stops, rather than inventing a successor", () => {
    // The decision recorded in HANDOFF.md: succession (docs/01) needs the procedurally
    // generated survivors of docs/07 to succeed *into*, which is Milestone 2. So death is
    // published, control ends, and the simulation carries on around the body.
    const { world, player, origin } = arena({ disabled: ["wander", "zombies"] });
    for (let i = 0; i < 3; i++) placeZombie(world, origin.x + 0.5, origin.y + i * 0.1);

    const died = record(world, "survivor.died");
    const body = world.components.getOrThrow(player, Body);
    body.torso = 1;

    stepN(world, 400);

    expect(body.dead).toBe(true);
    expect(died.map((d) => d.entity)).toContain(player);
    // The body stays on the map: entities are only despawned when they are not people.
    expect(world.entities.isAlive(player)).toBe(true);
    expect(world.components.getOrThrow(player, Tags).values).toContain(SURVIVOR_TAG);
  });
});

describe("the breach benchmark", () => {
  it("is measuring a crowd in contact, not a crowd standing about", () => {
    // The habit this repo learned the expensive way: a benchmark that measures nothing
    // still reports a number. The risk-5 scenario's first draft reported a comfortable
    // 0.55 ms while 498 of 500 zombies stood still, so a budget is only worth as much as
    // the assertion that its scenario is doing the thing.
    const scenario = SCENARIOS.find((s) => s.id === "breach");
    expect(scenario).toBeDefined();
    const world = (scenario as (typeof SCENARIOS)[number]).build();

    let grabs = 0;
    world.events.subscribe({ id: "test.grabs", type: "grab.started", handler: () => grabs++ });
    stepN(world, 200);

    expect(grabs).toBeGreaterThan(20);
    const pursuing = world.components
      .query(Zombie)
      .filter((e) => world.components.getOrThrow(e, Zombie).pursuing !== null);

    // Around 90 of the 500, not all of them, and the ceiling is structural rather than a
    // tuning miss: the field's cells are 4 m, so a crowd ascending a point source runs out
    // of gradient on the source's own cell and settles there -- just outside the 3 m at
    // which contact begins. The rest are milling one cell out, which is its own cost.
    expect(pursuing.length).toBeGreaterThan(50);
  });
});

describe("the horde", () => {
  it("comes for someone in reach instead of reading the field", () => {
    // docs/14 step 4: "pursue on direct contact, indefinitely." Pursuit outranks the
    // gradient, so a zombie standing next to you does not wander off up a scent trail.
    const { world, origin } = arena({ disabled: ["wander"] });
    const zombie = placeZombie(world, origin.x + 2.5, origin.y + 1, { grabs: false });

    stepN(world, 5);
    expect(world.components.getOrThrow(zombie, Zombie).pursuing).not.toBeNull();

    const before = world.components.getOrThrow(zombie, Position);
    const gapBefore = Math.hypot(before.x - origin.x, before.y - origin.y);
    stepN(world, 40);
    const after = world.components.getOrThrow(zombie, Position);
    expect(Math.hypot(after.x - origin.x, after.y - origin.y)).toBeLessThan(gapBefore);
  });
});
