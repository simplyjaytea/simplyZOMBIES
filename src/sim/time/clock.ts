// The clock.
//
// docs/02-core-loop.md is the specification, and the shape it asks for is unusual enough to
// state plainly: **the four phases are not modes.** The simulation never stops, nothing is
// gated on a phase, and you can do anything at any time. What a phase changes is the
// pressure -- and, as of this build, how far you can see.
//
// **Time of day is a pure function of `world.tick`.** There is no clock state, nothing new in
// the save, and nothing that can disagree with the world it was saved from. Starting a run at
// dusk is not a field; it is starting at a different tick. The sim still has no notion of real
// time -- `step(world)` takes no delta, reads no wall clock, and this file reads nothing but a
// tick count (docs/19-architecture.md#sim--the-hard-rules).
//
// The one thing that is *not* derived is how long a day is, which is a constant here and a
// guess in the documents that chose it. See {@link DAY_SECONDS}.

import { TICK_HZ } from "../kernel/tick";
import type { World } from "../kernel/world";

/**
 * A day, in seconds of real time at 1x speed.
 *
 * docs/02-core-loop.md#time-scale: "Full day -- ~4 hours at 1x". That number is a **guess**
 * and has been flagged as one in HANDOFF.md's open questions since the roadmap was written;
 * it is here rather than spread across the phase table so that answering the question is
 * editing one line.
 *
 * Four hours is also why the [speed controls](../../platform/loop.ts) are not a convenience.
 * At 1x nobody in a development session will ever see nightfall.
 */
export const DAY_SECONDS = 4 * 60 * 60;

/** A day, in ticks. */
export const DAY_TICKS = DAY_SECONDS * TICK_HZ;

/** The four phases of docs/02-core-loop.md#the-ratchet. */
export const enum Phase {
  /** The bill for last night arrives. Short and administrative. */
  Dawn = 0,
  /** The colony half: scavenge and work. The long phase. */
  Day = 1,
  /** Preparation. Commit to tonight's plan. */
  Dusk = 2,
  /** The defense half. What you spent in daylight arrives. */
  Night = 3,
}

export const PHASE_NAMES: Record<Phase, string> = {
  [Phase.Dawn]: "dawn",
  [Phase.Day]: "day",
  [Phase.Dusk]: "dusk",
  [Phase.Night]: "night",
};

/**
 * Where each phase ends, as a fraction of the day.
 *
 * Straight from docs/02's time-scale table: dawn and dusk are ~30 minutes each of a ~4 hour
 * day, night is ~1 hour, and the day phase is the remainder. The fractions rather than the
 * durations are stored, so that changing {@link DAY_SECONDS} rescales the whole cycle instead
 * of silently eating the day phase.
 */
const DAWN_ENDS = 0.5 / 4;
const DAY_ENDS = DAWN_ENDS + 2 / 4;
const DUSK_ENDS = DAY_ENDS + 0.5 / 4;

/**
 * Where a run starts, by default: first thing in the day phase, in full light.
 *
 * Tick 0 is the *start of dawn*, which is the darkest moment of the cycle -- so a world that
 * simply began at tick 0 would open half-blind, with no lamp to light and no way to know why.
 * docs/02 opens its day at dawn because dawn is where the previous night's bill arrives, and
 * there is no night behind a fresh run to send one.
 */
export const DAY_BEGINS = DAWN_ENDS;

/**
 * How much light there is at the darkest point of the night, as a fraction of daylight.
 *
 * Not zero, and the reason matters: **there is no light channel yet**, so there is nothing to
 * carry, nothing to light, and no counterplay to the dark. A survivor at 0 would simply be
 * blind with no answer available. At 0.25 a daylight view of 48 m becomes 12 m -- enough to
 * play, tight enough that night is a different game -- and the moment lamps and torches exist
 * this number should go *down*, because then the dark has an answer.
 */
export const NIGHT_AMBIENT = 0.25;

/** Fraction of the way through the current day, in [0, 1). */
export function timeOfDay(tick: number): number {
  return (tick % DAY_TICKS) / DAY_TICKS;
}

/** Which day this is. Day 1 is the one the run starts in. */
export function dayNumber(tick: number): number {
  return Math.floor(tick / DAY_TICKS) + 1;
}

/** The phase at a given fraction of the day. */
export function phaseAt(fraction: number): Phase {
  if (fraction < DAWN_ENDS) return Phase.Dawn;
  if (fraction < DAY_ENDS) return Phase.Day;
  if (fraction < DUSK_ENDS) return Phase.Dusk;
  return Phase.Night;
}

/** The phase at a given tick. */
export function phaseOf(tick: number): Phase {
  return phaseAt(timeOfDay(tick));
}

/**
 * Ambient light, from {@link NIGHT_AMBIENT} at the dead of night to 1 in full day.
 *
 * Ramps linearly through dawn and dusk and sits flat through day and night, which is what
 * makes those two the *long* phases in feel as well as in duration: the light is only
 * actually changing for an hour of the four.
 *
 * Linear rather than a curve on purpose. A smoothstep would look marginally better and would
 * make the two transition phases feel shorter at both ends, which is the opposite of what
 * docs/02 wants from them -- dawn and dusk are decision phases, and a decision phase should
 * announce itself early.
 */
export function ambientLight(fraction: number): number {
  if (fraction < DAWN_ENDS) {
    return NIGHT_AMBIENT + (1 - NIGHT_AMBIENT) * (fraction / DAWN_ENDS);
  }
  if (fraction < DAY_ENDS) return 1;
  if (fraction < DUSK_ENDS) {
    return 1 - (1 - NIGHT_AMBIENT) * ((fraction - DAY_ENDS) / (DUSK_ENDS - DAY_ENDS));
  }
  return NIGHT_AMBIENT;
}

/** Ambient light at a given tick. */
export function ambientLightAt(tick: number): number {
  return ambientLight(timeOfDay(tick));
}

/**
 * The in-world hour and minute.
 *
 * Presentation only -- nothing in the simulation reads it. The offset puts dawn at 06:00, so
 * the phases land where a person expects them: dawn 06:00, day 09:00, dusk 21:00, night
 * midnight. A tick count is the truth; this is the thing a survivor could tell from the sun.
 */
export function clockTime(tick: number): { hour: number; minute: number } {
  const hours = ((timeOfDay(tick) + 0.25) % 1) * 24;
  return { hour: Math.floor(hours), minute: Math.floor((hours % 1) * 60) };
}

/** `tick` for a given point in day 1, so a caller can start a run at dusk. */
export function tickAtTimeOfDay(fraction: number): number {
  return Math.floor((((fraction % 1) + 1) % 1) * DAY_TICKS);
}

/**
 * Publish the transitions. Registered by `boot` as a kernel system.
 *
 * Stateless: it compares the phase at this tick with the phase at the previous one rather
 * than remembering what it last announced. That is what makes it survive a load -- a
 * remembered phase would be either save state that can disagree with the tick, or a
 * re-announcement of a transition that already happened.
 *
 * The exception is the first tick of a run, which has no previous tick to differ from. `day
 * 1` is published there explicitly, because a consumer that only listens for `day.started`
 * should not silently miss the day it booted into.
 */
export function publishPhaseChanges(world: World): void {
  const tick = world.tick;
  if (tick <= 0) return;

  if (tick === 1) {
    world.events.publish({ type: "day.started", day: dayNumber(tick) });
    return;
  }

  const now = phaseOf(tick);
  const before = phaseOf(tick - 1);
  if (now === before) return;

  world.events.publish({
    type: "phase.changed",
    phase: PHASE_NAMES[now],
    previous: PHASE_NAMES[before],
  });

  // The two phases the rest of the design keys off get their own events, per
  // docs/21-extensibility.md#core-events -- the vocabulary declared them long before there
  // was anything to publish them.
  if (now === Phase.Night) world.events.publish({ type: "night.fell", day: dayNumber(tick) });
  if (now === Phase.Dawn) world.events.publish({ type: "day.started", day: dayNumber(tick) });
}
