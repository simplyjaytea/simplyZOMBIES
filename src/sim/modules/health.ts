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
  SURVIVOR_BODY,
  ZOMBIE_BODY,
  type SurvivorBodyPart,
} from "../combat";
import { defineComponent } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { Module } from "./index";

/**
 * Integrity per body part, each counting down to zero.
 *
 * Numbers per part rather than one pool, because one pool cannot express the thing that makes
 * zombies zombies: a torso is a sink that never kills, a head is instant, and legs turn one
 * threat into a different and quieter one. A single hit-point total collapses all three into
 * "how many more times do I swing", which is the fight docs/01 says this game does not have.
 *
 * **How many parts depends on what the body is.** A zombie has the three docs/14 says matter; a
 * survivor has docs/05's six, which add arms, hands and feet -- the parts whose loss costs work
 * rather than life. `head` and `torso` are the two every body has, which is why they are the two
 * declared required: `isAlive` reads one of them and has to hold for anything that can die.
 *
 * The optional parts are genuinely optional rather than zero-filled. A zombie with `hands: 0`
 * would be a zombie with destroyed hands, and the condition view would draw it that way.
 */
export type Body = {
  head: number;
  torso: number;
} & Partial<Record<SurvivorBodyPart, number>>;

export const Body = defineComponent<Body>("Body");

/** The stable injury vocabulary from docs/05. Milestone 1 produces only scratches and bites. */
export type InjuryKind =
  "scratch" | "laceration" | "deep-wound" | "bite" | "fracture" | "sprain" | "burn" | "concussion";

/**
 * A located wound and the honest observation currently available to the player.
 *
 * `kind` is simulation truth. `presentation` is deliberately separate: docs/01's most
 * important uncertainty rule is that a bite may present as a scratch. The condition view
 * reads only the latter, so adding a paperdoll can never leak the private answer by accident.
 */
export type Injury = {
  kind: InjuryKind;
  presentation: InjuryKind;
  bodyPart: SurvivorBodyPart;
  source: EntityId;
  sustainedAtTick: number;
};

export type Injuries = { wounds: Injury[] };

export const Injuries = defineComponent<Injuries>("Injuries");

/** Initial calibration. A real bite is visually ambiguous this often. */
export const BITE_PRESENTS_AS_SCRATCH_CHANCE = 0.3;

/**
 * The **maximum** integrity of each part, by body, so a current value can be read as a fraction.
 *
 * Derived from the two tables rather than stored per entity, and that is the whole reason this
 * lookup exists: a `max` alongside every `current` would be six more numbers in every save that
 * can never change, and six more numbers for a content edit to leave stale. What a part *was*
 * is a property of the kind of body, not of the body.
 *
 * Which body a given entity has is answered by which parts it carries -- see {@link maxOf} --
 * rather than by a discriminator field, because the parts are already the discriminator and a
 * second copy of that fact is a second copy that can disagree.
 */
const MAXIMA: readonly Readonly<Record<string, number>>[] = [SURVIVOR_BODY, ZOMBIE_BODY];

/** What this part started at, or `undefined` if the body has no such part. */
export function maxOf(body: Body, part: string): number | undefined {
  const table = MAXIMA.find((t) => Object.keys(t).every((k) => k in body));
  return table?.[part];
}

/**
 * How a part reads, in the four states docs/05's condition view allows.
 *
 * **Four, because four is how many distinctions the prose actually supports** -- that is docs/05's
 * own reasoning, and it is also the ceiling on how much a tint can say. The states are ordinal so
 * the paperdoll can compare them without knowing the thresholds.
 */
export const enum PartState {
  Unhurt = 0,
  Hurt = 1,
  BadlyHurt = 2,
  /** Gone, for practical purposes. Legs here is docs/05's crawler; hands here cannot work. */
  Unusable = 3,
}

/**
 * The two thresholds, as fractions of a part's maximum.
 *
 * In **one place**, read by both the tint and the prose. Two copies of these numbers is how a
 * limb comes to be drawn amber while the words beside it say it is fine, and a screen that
 * contradicts itself is worse than either half alone -- docs/05 is a document about a readout
 * that is allowed to be *uncertain*, not one that is allowed to be inconsistent.
 *
 * `Unhurt` means **undamaged**, not "nearly undamaged". There is no tolerance band, and there
 * should not be one: a threshold of 0.99 would make the first scratch invisible, and the whole
 * argument for prose over a bar is that it tells you *something happened here* before it tells you
 * how much. A survivor who has been hurt at all should read as having been hurt.
 */
const HURT_BELOW = 1;
const BADLY_HURT_BELOW = 0.5;

/** Read a part's integrity as one of the four states. Unusable at zero, and only at zero. */
export function partState(body: Body, part: string): PartState | undefined {
  const current = body[part as SurvivorBodyPart];
  if (current === undefined) return undefined;
  const max = maxOf(body, part);
  if (max === undefined || max <= 0) return undefined;
  if (current <= 0) return PartState.Unusable;
  const fraction = current / max;
  if (fraction < BADLY_HURT_BELOW) return PartState.BadlyHurt;
  if (fraction < HURT_BELOW) return PartState.Hurt;
  return PartState.Unhurt;
}

/**
 * What a body can spend before it is spending itself.
 *
 * Deliberately not a bar (docs/29's cut list is explicit). It is read from swing speed, and from
 * the rung: holding a jog or a sprint drains it, and running out is what makes sprint stop
 * answering rather than make the survivor a slow sprinter. "The consequence *is* the readout".
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

/**
 * A survivor's body: docs/05's six parts.
 *
 * A separate function rather than a parameter on {@link makeBody}, because the two are handed
 * out by different callers for different reasons and a boolean argument at the call site would
 * read as `makeBody(world, entity, true)`.
 */
export function makeSurvivorBody(world: World, entity: EntityId): void {
  world.components.set(entity, Body, { ...SURVIVOR_BODY });
  world.components.set(entity, Injuries, { wounds: [] });
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
  // A body with no `legs` part at all is not crawling. Nothing ships like that today -- both
  // bodies have legs -- but answering `true` for an absent part would mean "we do not model this
  // creature's locomotion" and "its locomotion is destroyed" came out the same, and the second
  // one is a state the renderer draws differently.
  return body.legs !== undefined && body.legs <= 0;
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
    const injuryRng = world.rng.stream("injury");

    /**
     * Apply one located hit and publish death exactly once.
     *
     * Kept inside the health owner so `attack.connected` and `bite.landed` cannot drift into
     * two subtly different meanings of damage. The caller still supplies force and location.
     */
    const damagePart = (
      target: EntityId,
      source: EntityId,
      namedPart: string,
      amount: number,
    ): { body: Body; part: SurvivorBodyPart; before: number } | null => {
      const body = world.components.get(target, Body);
      if (body === undefined || !isAlive(body)) return null;

      const part = namedPart as SurvivorBodyPart;
      const before = body[part];
      if (before === undefined || before <= 0) return null;
      body[part] = Math.max(0, before - amount);

      if (part === "head" && body.head <= 0) {
        killed.push(target);
        world.events.publish({ type: "entity.killed", entity: target, killer: source });
      }

      return { body, part, before };
    };

    world.events.subscribe({
      id: "health.take-damage",
      type: "attack.connected",
      handler: (event) => {
        const result = damagePart(event.target, event.attacker, event.bodyPart, event.damage);
        if (result === null) return;
        const { body, part } = result;

        if (!isAlive(body)) return;

        // Locomotion destroyed. A statement of fact -- the shambler module decides what
        // crawling looks like, because how a given zombie moves is its own business.
        if (part === "legs" && isCrawling(body)) {
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
      id: "health.take-bite",
      type: "bite.landed",
      handler: (event) => {
        const result = damagePart(event.victim, event.source, event.bodyPart, event.damage);
        if (result === null || result.body.arms === undefined) return;

        const wounds = world.components.get(event.victim, Injuries) ?? { wounds: [] };
        if (!world.components.has(event.victim, Injuries)) {
          world.components.set(event.victim, Injuries, wounds);
        }

        const presentation: InjuryKind =
          injuryRng.next() < BITE_PRESENTS_AS_SCRATCH_CHANCE ? "scratch" : "bite";
        wounds.wounds.push({
          kind: "bite",
          presentation,
          bodyPart: result.part,
          source: event.source,
          sustainedAtTick: world.tick,
        });
        world.events.publish({
          type: "injury.sustained",
          entity: event.victim,
          injury: "bite",
          bodyPart: result.part,
        });
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
