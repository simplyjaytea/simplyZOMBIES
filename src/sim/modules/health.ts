// The health module.
//
// What it means to be damageable, and what happens when you stop being alive. docs/20's
// component inventory puts `Body` and `Stamina` here rather than anywhere else, and this
// module exists at the point melee needs something to hit -- not before, because a survivor
// who cannot be hurt is a health system with nothing to say.
//
// **It never reaches into the melee module, and melee never reaches in here.** The two seams
// are events, per docs/20's rule that "cross-module effects go through events and modifiers,
// never by reaching into another module's data":
//
//   attack.connected -> damage a body part, and maybe kill
//   stamina.spent    -> drain, and stall recovery
//
// Which is also why `attack.connected` carries its damage: the attacker is the only one who
// knows what swung, and the alternative is this file reading a weapon component it does not
// own.
//
// docs/14-zombies.md#damage-model is the spec for what damage *means*: "Meaningful damage is
// to the head or to locomotion. Body damage slows and staggers but doesn't stop them. A
// zombie with a destroyed pelvis crawls, is quiet, is easy to miss in a dark breach, and is
// still perfectly capable of biting an ankle."

import {
  STAMINA_MAX,
  STAMINA_PER_TICK,
  STAMINA_RECOVERY_DELAY_TICKS,
  ZOMBIE_BODY,
  type BodyPart,
} from "../combat";
import { defineComponent } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { Module } from "./index";

/**
 * Integrity of the three parts docs/14 says matter, each counting down to zero.
 *
 * Three numbers rather than one pool, because one pool cannot express the thing that makes
 * zombies zombies: a torso is a sink that never kills, a head is instant, and legs turn one
 * threat into a different and quieter one. A single hit-point total collapses all three into
 * "how many more times do I swing", which is the fight docs/01 says this game does not have.
 */
export type Body = {
  head: number;
  torso: number;
  legs: number;
};

export const Body = defineComponent<Body>("Body");

/**
 * What a body can spend before it is spending itself.
 *
 * Deliberately not a bar (docs/29's cut list is explicit). It is read from swing speed and,
 * when the stance ladder lands, from breathing -- "the consequence *is* the readout".
 */
export type Stamina = {
  current: number;
  max: number;
  /** Ticks before recovery resumes. Reset every time something is spent. */
  ticksUntilRecovery: number;
};

export const Stamina = defineComponent<Stamina>("Stamina");

/** A zombie's body, from the mirrored content values. */
export function makeBody(world: World, entity: EntityId): void {
  world.components.set(entity, Body, { ...ZOMBIE_BODY });
}

export function makeStamina(world: World, entity: EntityId, max = STAMINA_MAX): void {
  world.components.set(entity, Stamina, { current: max, max, ticksUntilRecovery: 0 });
}

/** Is this body still standing? Anything with a head above zero is. */
export function isAlive(body: Body): boolean {
  return body.head > 0;
}

/**
 * Has locomotion been destroyed? docs/14's crawler.
 *
 * Exported because the shambler module reads it to pick a speed. Reading another module's
 * component is permitted (docs/20:55); writing it is not, and nothing outside this file does.
 */
export function isCrawling(body: Body): boolean {
  return body.legs <= 0;
}

export const healthModule: Module = {
  id: "health",

  register({ world }) {
    /**
     * Killed this tick, awaiting despawn.
     *
     * Deferred to `cleanup` rather than despawned inside the event handler, because a handler
     * runs mid-cascade while systems are part-way through iterating: removing an entity's
     * components underneath a loop that is holding one is the kind of bug that surfaces as a
     * crash three systems later, in a file that did nothing wrong.
     *
     * **A body therefore exists for exactly one tick after it dies.** `step` drains the event
     * queue after every system has run (see kernel/step.ts), so a kill published during that
     * drain is reaped by the *next* tick's cleanup. That is 50 ms of corpse, and it is
     * deliberate rather than tolerated: `isAlive` is already false for it, so nothing targets
     * it or kills it twice, and the alternative -- despawning inside the handler -- trades a
     * visible tick of corpse for an invisible class of iterator bug. When corpses become real
     * (docs/03 wants them burned), this is where they stop being reaped at all.
     */
    const killed: EntityId[] = [];

    world.events.subscribe({
      id: "health.take-damage",
      type: "attack.connected",
      handler: (event) => {
        const body = world.components.get(event.target, Body);
        if (body === undefined) return;
        // Already dead and awaiting cleanup. A second blow lands on a corpse, which is
        // allowed, but it must not kill it twice and publish two `entity.killed`.
        if (!isAlive(body)) return;

        const part = event.bodyPart as BodyPart;
        if (part !== "head" && part !== "torso" && part !== "legs") return;

        const before = body[part];
        if (before <= 0) return;
        body[part] = Math.max(0, before - event.damage);

        if (part === "head" && body.head <= 0) {
          killed.push(event.target);
          world.events.publish({
            type: "entity.killed",
            entity: event.target,
            killer: event.attacker,
          });
          return;
        }

        // Locomotion destroyed. A statement of fact -- the shambler module decides what
        // crawling looks like, because how a given zombie moves is its own business.
        if (part === "legs" && body.legs <= 0) {
          world.events.publish({
            type: "injury.sustained",
            entity: event.target,
            injury: "crippled",
            bodyPart: "legs",
          });
        }
      },
    });

    world.events.subscribe({
      id: "health.spend-stamina",
      type: "stamina.spent",
      handler: (event) => {
        const stamina = world.components.get(event.entity, Stamina);
        if (stamina === undefined) return;
        stamina.current = Math.max(0, stamina.current - event.amount);
        stamina.ticksUntilRecovery = STAMINA_RECOVERY_DELAY_TICKS;
      },
    });

    world.systems.register({
      id: "health.recover",
      phase: "health",
      run: (w) => {
        w.components.forEachWith(Stamina, (_entity, stamina) => {
          if (stamina.ticksUntilRecovery > 0) {
            stamina.ticksUntilRecovery--;
            return;
          }
          if (stamina.current < stamina.max) {
            stamina.current = Math.min(stamina.max, stamina.current + STAMINA_PER_TICK);
          }
        });
      },
    });

    world.systems.register({
      id: "health.reap",
      phase: "cleanup",
      run: (w) => {
        if (killed.length === 0) return;
        for (const entity of killed) w.despawn(entity);
        killed.length = 0;
      },
    });
  },
};
