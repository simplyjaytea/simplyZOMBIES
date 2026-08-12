// The stance module.
//
// docs/29-movement-and-stances.md. The ladder itself -- five rungs and what each one costs --
// is `sim/stances.ts`, which is arithmetic and imports nothing. This is the half that owns
// *state*: which rung a body is on, which rung it is heading for, and how many ticks are left
// before it gets there.
//
// The split is the same one `attention.ts` makes against the field it writes to. A table of
// speeds is a coherent thing to have with nobody standing on it, which is what lets
// `stances.test.ts` exercise every invariant in the ladder without a world.
//
// **What this module deliberately does not do** is decide anything about speed, noise or
// sightlines. It publishes a rung, and three other modules read it:
//
//   movement.integrate      -> speed, via the rung's factor and the modifier pipeline
//   attention.emit-movement -> noise magnitude, via the rung
//   stance.eyes             -> Observer.eye, so Low cover finally cuts both ways
//
// That is docs/20's rule about cross-module effects, and it is also why switching this module
// off leaves a working game: without a `Posture` nobody has a rung, every reader falls back to
// what it did before the ladder existed, and the survivor walks.

import { defineComponent } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import {
  DEFAULT_STANCE,
  Stance,
  STANCE_CHANGE_TICKS,
  stanceSpec,
  type StanceSpec,
} from "../stances";
import { Observer } from "../vision/visibility";
import { Stamina } from "./health";
import type { Module } from "./index";

/**
 * What rung a body is on, and what rung it is trying to reach.
 *
 * Three fields rather than one, because docs/29 and
 * [clause 2](../../../docs/01-hardcore-contract.md#2-actions-take-time-and-time-is-where-you-die)
 * both insist a stance change is a *timed action*: "committing to a sprint is a real
 * commitment". A single `current` would make standing up out of a crawl free, which is the
 * mechanic clause 2 exists to prevent.
 *
 * **In save state**, like `Facing` and the shambler's angular bias. A survivor saved halfway
 * out of a crouch is mid-action, and dropping `ticksLeft` on load would finish an action the
 * player was still paying for.
 */
export type Posture = {
  /** The rung the body is actually on. Every reader uses this one. */
  current: Stance;
  /** The rung it is moving toward. Equal to `current` when nothing is pending. */
  target: Stance;
  /** Ticks until the next rung. Zero when `current === target`. */
  ticksLeft: number;
};

export const Posture = defineComponent<Posture>("Posture");

/** Give a body a stance. Mirrors `makeEmitter` and `makeBody` -- the module owns the write. */
export function makePosture(world: World, entity: EntityId, stance: Stance = DEFAULT_STANCE): void {
  world.components.set(entity, Posture, { current: stance, target: stance, ticksLeft: 0 });
}

/**
 * The rung a body is on, or the shipped default for a body with no {@link Posture}.
 *
 * The fallback is what makes this module removable. Every reader outside here goes through
 * this function rather than querying the component, so "no stance module" and "walking" are
 * the same answer -- which is exactly the behaviour the module-isolation test asserts, and it
 * is also right for a generator or a car, neither of which has a posture to read.
 */
export function stanceOf(world: World, entity: EntityId): Stance {
  return world.components.get(entity, Posture)?.current ?? DEFAULT_STANCE;
}

/** The rung's spec, with the same fallback. The form most callers actually want. */
export function stanceSpecOf(world: World, entity: EntityId): StanceSpec {
  return stanceSpec(stanceOf(world, entity));
}

/**
 * Whether a body may swing or aim right now -- asked of the rung it is on **and** the rung it
 * is heading for.
 *
 * Both, and the reason is a mechanic that would otherwise quietly stop existing. docs/09 says
 * breaking into a sprint abandons a wind-up, "which is what makes running away mid-swing a
 * decision". Reading `current` alone, pressing sprint mid-wind-up would leave the swing running
 * for the eight ticks the transition takes -- and a bat's wind-up is shorter than that, so the
 * blow would land every time and the rule would never fire once.
 *
 * So the *decision* is what costs you the swing, not the arrival. That is also the honest
 * reading of the sentence: you abandoned the swing when you chose to run, and the eight ticks
 * you spend getting up to speed are the price of the choice rather than a window to sneak a
 * hit through.
 */
export function capableOf(world: World, entity: EntityId, of: "canSwing" | "canAim"): boolean {
  const posture = world.components.get(entity, Posture);
  if (posture === undefined) return stanceSpec(DEFAULT_STANCE)[of];
  return stanceSpec(posture.current)[of] && stanceSpec(posture.target)[of];
}

/**
 * Ask a body to change stance.
 *
 * Setting a target, never a rung. The walk up the ladder is the timer's business, which is
 * what keeps "crawl to sprint" costing four transitions rather than one -- docs/29 wants the
 * rungs between to be travelled through, not skipped, so that standing up with something
 * already on top of you is a decision you can lose.
 */
export function requestStance(posture: Posture, target: Stance): void {
  if (posture.target === target) return;
  posture.target = target;
  // Re-aim without restarting the clock when a change is already under way: a player who
  // taps crouch and then sprint has already paid part of a transition, and charging for it
  // twice would make a corrected decision cost more than a committed one.
  if (posture.current !== target && posture.ticksLeft === 0) {
    posture.ticksLeft = STANCE_CHANGE_TICKS;
  }
  if (posture.current === target) posture.ticksLeft = 0;
}

/**
 * Abandon a pending change and stay where you are.
 *
 * The rung does not snap back and does not jump forward -- a body interrupted halfway up the
 * ladder is on a real rung, because the walk is one rung at a time. What is lost is the
 * *pending* half, which is the thing a stagger should cost.
 */
export function interruptStance(posture: Posture): void {
  posture.target = posture.current;
  posture.ticksLeft = 0;
}

export const stanceModule: Module = {
  id: "stance",

  register({ world }) {
    // Before the player module (order 0) and the melee intake (order 10), so a stance
    // command and the move it was pressed with are resolved in that order within one tick:
    // the rung settles, then velocity is taken from it. The other way round would spend a
    // tick at the old speed after every change, which reads as input lag rather than as the
    // transition it already charges for.
    world.systems.register({
      id: "stance.intake",
      phase: "input",
      order: -10,
      run: (w) => {
        const commands = w.commands.current;
        if (commands.length === 0) return;

        for (const entity of w.components.query(Posture)) {
          const posture = w.components.getOrThrow(entity, Posture);
          for (const command of commands) {
            switch (command.type) {
              case "stance":
                requestStance(posture, command.stance);
                break;

              // The shipped sprint key, expressed on the ladder. Holding it targets Sprint
              // and releasing it targets Walk, which is the two-rung ladder the game shipped
              // with -- kept working deliberately, so the input surface does not regress
              // while the five rungs are being tuned.
              case "sprint":
                requestStance(posture, command.active ? Stance.Sprint : Stance.Walk);
                break;

              default:
                break;
            }
          }
        }
      },
    });

    // Immediately after intake, so a change requested this tick starts its clock this tick.
    world.systems.register({
      id: "stance.advance",
      phase: "input",
      order: -9,
      run: (w) => {
        for (const entity of w.components.query(Posture)) {
          const posture = w.components.getOrThrow(entity, Posture);
          if (posture.current === posture.target) continue;
          // The tick that empties the clock is also the tick the rung changes on, rather than
          // the one before it. Written the other way round -- decrement, `continue`, step on the
          // *next* pass -- each rung silently cost `STANCE_CHANGE_TICKS + 1` ticks, and
          // `stanceChangeTicks()` would have been lying about the price by 25%.
          if (posture.ticksLeft > 0) {
            posture.ticksLeft--;
            if (posture.ticksLeft > 0) continue;
          }
          // One rung, then re-arm if there is further to go. This is what makes the cost of a
          // change proportional to the distance without a table of pair-wise costs -- and it
          // is what leaves an interrupted body somewhere real.
          posture.current += Math.sign(posture.target - posture.current);
          posture.ticksLeft = posture.current === posture.target ? 0 : STANCE_CHANGE_TICKS;
        }
      },
    });

    /**
     * Eye level follows the rung.
     *
     * The one write that makes docs/28's **Low** occluder class mean anything. `Eye.Crouched`
     * and the `Low` opacity have both been implemented in `map/tilemap.ts` since visibility
     * landed, with a comment saying nothing sets them yet; this is the writer they were
     * waiting for.
     *
     * It cuts both ways by construction rather than by a second rule. Sight is symmetric --
     * `shadowcast` is built so that if A sees B, B sees A -- so a crouched survivor behind a
     * car cannot see over it and cannot be seen over it, from the same predicate. Cover that
     * hides you also blinds you, and there is no way to get one without the other.
     *
     * In `movement` rather than `input` because a body that crouched this tick should be seen
     * as crouched by the visibility recompute that follows, and vision runs after movement.
     *
     * Nothing here has to invalidate the shadowcast cache, and that is not luck:
     * `VisibilityIndex.refresh` already builds its key from `observer.eye` along with the
     * tile, the range and the map generation. Writing the field *is* the invalidation, which
     * is what the parameter was threaded end to end for.
     */
    world.systems.register({
      id: "stance.eyes",
      phase: "movement",
      order: 10,
      run: (w) => {
        for (const entity of w.components.query(Posture, Observer)) {
          const observer = w.components.getOrThrow(entity, Observer);
          observer.eye = stanceSpec(w.components.getOrThrow(entity, Posture).current).eye;
        }
      },
    });

    /**
     * What holding a rung costs, and what happens when you cannot pay it.
     *
     * Two halves of one rule, and docs/29 states it as one sentence: **"sprint becomes
     * unavailable before it becomes slow. Failure to run is the thing between a fight going
     * badly and a fight killing you."**
     *
     * So an empty pool does not make the survivor a slow sprinter. It drops them to a walk,
     * outright, and the walk back up costs the transition like any other -- which is what turns
     * "I have been running for fifteen seconds" into a fact with a consequence rather than a
     * number on a bar. There is no bar; per docs/05's condition view the readout *is* this
     * happening to you.
     *
     * The drain goes out as `stamina.spent` rather than by writing to the pool, so it stalls
     * recovery on exactly the terms a swing does and the health module stays the only writer.
     * A survivor who sprinted to the fight arrives with fewer swings in them, and nobody had to
     * write that down.
     *
     * In `needs` because that is where the other per-tick upkeep lives (`inventory.encumbrance`
     * is there), and after `health` would spend against a pool that had already recovered.
     */
    world.systems.register({
      id: "stance.upkeep",
      phase: "needs",
      run: (w) => {
        for (const entity of w.components.query(Posture)) {
          const posture = w.components.getOrThrow(entity, Posture);
          const drain = stanceSpec(posture.current).staminaPerTick;
          if (drain <= 0) continue;

          const stamina = w.components.get(entity, Stamina);
          // Nothing to spend from is not the same as nothing to pay: a body with no `Stamina`
          // at all -- which is most of them -- holds any rung indefinitely, exactly as it did
          // before the ladder existed.
          if (stamina === undefined) continue;

          if (stamina.current >= drain) {
            w.events.publish({ type: "stamina.spent", entity, amount: drain });
            continue;
          }

          // Out of stamina. What that costs you depends on which direction the rung is, and
          // the asymmetry is deliberate rather than a special case.
          //
          // The fast rungs stop answering: jog and sprint drop to a walk, and getting back up
          // costs the transition like any other. That is docs/29's sentence exactly.
          //
          // **Crawl does not.** It is "the last resort that is not running" -- the verb left to
          // a survivor whose legs are gone -- and an exhausted crawler forced to stand up would
          // be the game taking away the one option it says is always there. Being too tired to
          // crawl any further has to mean lying still, not standing up into the thing you were
          // crawling away from. So the pool simply bottoms out and the rung holds.
          if (stanceSpec(posture.current).speedFactor > stanceSpec(DEFAULT_STANCE).speedFactor) {
            requestStance(posture, DEFAULT_STANCE);
          } else if (stamina.current > 0) {
            w.events.publish({ type: "stamina.spent", entity, amount: stamina.current });
          }
        }
      },
    });

    // A stagger costs you the change you were making. `entity.staggered` is the same event
    // that already interrupts a wind-up (`melee.ts`), and the symmetry is the point: docs/09
    // says the rule cuts both ways, so a survivor caught standing up stays down.
    world.events.subscribe({
      id: "stance.staggered",
      type: "entity.staggered",
      handler: (event) => {
        const posture = world.components.get(event.entity, Posture);
        if (posture !== undefined) interruptStance(posture);
      },
    });
  },
};
