// The day/night cycle.
//
// docs/02-core-loop.md defines the four phases and insists they are **not modes**: the
// simulation never stops and nothing is gated on a phase. So these guards are about two
// things only -- that the clock is a function of the tick and nothing else, and that the dark
// is mechanical rather than a filter over the screen.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Position } from "../../src/sim/kernel/components";
import { step, stepN } from "../../src/sim/kernel/step";
import { fingerprint } from "../../src/sim/kernel/serialize";
import {
  ambientLight,
  ambientLightAt,
  clockTime,
  DAY_BEGINS,
  DAY_TICKS,
  dayNumber,
  NIGHT_AMBIENT,
  Phase,
  phaseOf,
  tickAtTimeOfDay,
  timeOfDay,
} from "../../src/sim/time/clock";
import { DAYLIGHT_EYES, Detail } from "../../src/sim/vision/visibility";
import { tileRange } from "../../src/sim/map/tilemap";
import { THREAT_METRES, threatWithin } from "../../src/sim/threat";

const SEED = 20260805;
const NIGHT = 0.8;

describe("the clock", () => {
  it("runs through the four phases in order, once a day", () => {
    const seen: Phase[] = [];
    for (let i = 0; i < 200; i++) {
      const phase = phaseOf(Math.floor((i / 200) * DAY_TICKS));
      if (seen[seen.length - 1] !== phase) seen.push(phase);
    }
    expect(seen).toEqual([Phase.Dawn, Phase.Day, Phase.Dusk, Phase.Night]);
  });

  it("keeps docs/02's proportions: two long phases and two short ones", () => {
    const ticks = new Map<Phase, number>();
    for (let tick = 0; tick < DAY_TICKS; tick += 20) {
      const phase = phaseOf(tick);
      ticks.set(phase, (ticks.get(phase) ?? 0) + 1);
    }
    const share = (phase: Phase): number => (ticks.get(phase) ?? 0) / (DAY_TICKS / 20);

    // ~30 minutes each of a ~4 hour day, night ~1 hour, day the remainder.
    expect(share(Phase.Dawn)).toBeCloseTo(0.125, 2);
    expect(share(Phase.Day)).toBeCloseTo(0.5, 2);
    expect(share(Phase.Dusk)).toBeCloseTo(0.125, 2);
    expect(share(Phase.Night)).toBeCloseTo(0.25, 2);
  });

  it("is a pure function of the tick, with nothing in the save", () => {
    const { world } = boot({ seed: SEED, wanderers: 5 });
    stepN(world, 50);

    // Stated as "nothing was added to the snapshot" rather than by searching the serialized
    // text for words. The first version of this looked for "ambient" and found
    // `AttentionEmitter.ambient` -- the noise a standing body makes -- which is a different
    // thing entirely and would have failed for a reason with nothing to do with the clock.
    const serialized = world.serialize();
    expect(Object.keys(world.snapshot()).sort()).toEqual([
      "components",
      "entities",
      "field",
      "modifiers",
      "rng",
      "seed",
      "tick",
      "version",
    ]);

    const other = boot({ seed: SEED, wanderers: 5 });
    other.world.restore(JSON.parse(JSON.stringify(world.snapshot())));
    expect(timeOfDay(other.world.tick)).toBe(timeOfDay(world.tick));
    expect(ambientLightAt(other.world.tick)).toBe(ambientLightAt(world.tick));
    expect(fingerprint(other.world.serialize())).toBe(fingerprint(serialized));
  });

  it("starts a run in the morning, not in the dark", () => {
    // Tick 0 is the *start of dawn*, which is the darkest moment of the cycle. A fresh world
    // opening half-blind with no lamp to light and no way to know why is not a default.
    const { world } = boot({ seed: SEED, wanderers: 0 });
    expect(phaseOf(world.tick)).toBe(Phase.Day);
    expect(ambientLightAt(world.tick)).toBe(1);
    expect(timeOfDay(world.tick)).toBeCloseTo(DAY_BEGINS, 5);
  });

  it("starts wherever it is asked to", () => {
    const { world } = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT });
    expect(phaseOf(world.tick)).toBe(Phase.Night);
    expect(ambientLightAt(world.tick)).toBe(NIGHT_AMBIENT);
  });

  it("reads the hours off the sun", () => {
    expect(clockTime(tickAtTimeOfDay(0))).toEqual({ hour: 6, minute: 0 }); // dawn
    expect(clockTime(tickAtTimeOfDay(DAY_BEGINS))).toEqual({ hour: 9, minute: 0 }); // day
    expect(clockTime(tickAtTimeOfDay(0.625))).toEqual({ hour: 21, minute: 0 }); // dusk
    expect(clockTime(tickAtTimeOfDay(0.75))).toEqual({ hour: 0, minute: 0 }); // night
  });

  it("counts days", () => {
    expect(dayNumber(0)).toBe(1);
    expect(dayNumber(DAY_TICKS - 1)).toBe(1);
    expect(dayNumber(DAY_TICKS)).toBe(2);
  });
});

describe("the light", () => {
  it("ramps through dawn and dusk and sits flat through day and night", () => {
    expect(ambientLight(0)).toBeCloseTo(NIGHT_AMBIENT, 5);
    expect(ambientLight(DAY_BEGINS)).toBe(1);
    expect(ambientLight(0.3)).toBe(1);
    expect(ambientLight(0.6)).toBe(1);
    expect(ambientLight(0.75)).toBeCloseTo(NIGHT_AMBIENT, 5);
    expect(ambientLight(0.9)).toBe(NIGHT_AMBIENT);

    // Monotonic through each transition, so nothing flickers.
    let previous = ambientLight(0);
    for (let f = 0; f < DAY_BEGINS; f += 0.005) {
      const now = ambientLight(f);
      expect(now).toBeGreaterThanOrEqual(previous);
      previous = now;
    }
  });

  it("goes darker than the weakest emitter, so a candle is an upgrade", () => {
    // This test used to be called "never goes fully dark, because there is nothing to light
    // yet", and it existed to explain why the number was 0.25. Emitters exist now, so it has
    // become the guard on the *derivation* instead.
    //
    // The rule, and the unit is the whole point: bare eyes at midnight must come out below the
    // weakest emitter in docs/03's table **in whole tiles**, because an integer tile radius is
    // what a shadowcast actually casts. Asserting it in metres is what let the first version of
    // this land on 0.05, where bare eyes are 2.4 m and a candle is 3 m and both round to a
    // three-tile window -- an upgrade on paper and invisible in play.
    const CANDLE_METRES = 3;
    const bareEyed = NIGHT_AMBIENT * DAYLIGHT_EYES.rangeMetres;
    expect(NIGHT_AMBIENT).toBeGreaterThan(0);
    expect(tileRange(bareEyed)).toBeLessThan(tileRange(CANDLE_METRES));

    // And not so dark that the one-tile floor in `tileRange` is what decides what night is,
    // rather than this constant.
    expect(tileRange(bareEyed)).toBeGreaterThan(1);

    let darkest = 1;
    for (let f = 0; f < 1; f += 0.001) darkest = Math.min(darkest, ambientLight(f));
    expect(darkest).toBe(NIGHT_AMBIENT);
  });
});

describe("the dark is mechanical", () => {
  /** How far the survivor can actually see, measured by probing along its facing. */
  function sightMetres(startTimeOfDay: number): number {
    const { world, player } = boot({ seed: SEED, wanderers: 0, startTimeOfDay, mapSize: 96 });
    const eyes = player as number;
    step(world);
    const here = world.components.getOrThrow(eyes, Position);

    let furthest = 0;
    for (let metres = 1; metres < 60; metres += 0.5) {
      // Straight ahead (facing is due east at boot) so no wall is in the way for the first
      // stretch, and stop at the first thing that is not visible for a reason we control.
      if (world.vision.detail(eyes, here.x + metres, here.y) === Detail.Unseen) break;
      furthest = metres;
    }
    return furthest;
  }

  it("shrinks what a survivor can see at night", () => {
    const byDay = sightMetres(DAY_BEGINS);
    const byNight = sightMetres(NIGHT);

    expect(byDay).toBeGreaterThan(byNight);
    // Not a tint over the same view -- a quarter of the view. Range is a property of light.
    expect(byNight).toBeLessThan(byDay * 0.5);
  });

  it("does not recompute a shadowcast every tick while the light is changing", () => {
    // The affordability claim, and the reason range is rounded to whole tiles. Ambient light
    // changes every tick through dusk; the integer tile radius does not.
    //
    // MUTATION CHECK: drop the Math.ceil in VisibilityIndex.refresh and this jumps to one
    // shadowcast per tick.
    const { world } = boot({ seed: SEED, wanderers: 0, startTimeOfDay: 0.63 });
    step(world);
    const before = world.vision.recomputes;

    stepN(world, 2000); // a hundred seconds of dusk, standing still
    const casts = world.vision.recomputes - before;

    expect(casts).toBeGreaterThan(0); // the light really is changing
    expect(casts).toBeLessThan(40); // and it is not costing a cast a tick
  });

  it("leaves noise and scent alone", () => {
    // Light is one channel of three. Night makes you blind, not quiet -- docs/03's channels
    // are independent, and a night that also muffled footsteps would be doing the light
    // channel's job twice and the noise channel's job wrong.
    const loudness = (startTimeOfDay: number): number => {
      const { world } = boot({ seed: SEED, wanderers: 0, startTimeOfDay, disabled: ["shambler"] });
      world.commands.push({ type: "shout" });
      step(world);
      return world.field.peakNoise();
    };
    expect(loudness(NIGHT)).toBe(loudness(DAY_BEGINS));
  });
});

describe("phase transitions", () => {
  it("publishes the change, and the two the design keys off", () => {
    // Boot just before nightfall and step over the boundary.
    const { world } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    world.tick = tickAtTimeOfDay(0.75) - 2;

    const heard: string[] = [];
    world.events.subscribe({
      id: "test.phase",
      type: "phase.changed",
      handler: (event) => heard.push(`${event.previous}->${event.phase}`),
    });
    world.events.subscribe({
      id: "test.night",
      type: "night.fell",
      handler: (event) => heard.push(`night ${event.day}`),
    });

    stepN(world, 4);
    expect(heard).toEqual(["dusk->night", "night 1"]);
  });

  it("publishes each transition exactly once, across a whole day", () => {
    const { world } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    world.tick = 0;
    let changes = 0;
    world.events.subscribe({
      id: "test.count",
      type: "phase.changed",
      handler: () => changes++,
    });

    // Sampled rather than stepped: a full day is 288,000 ticks. Stepping the boundaries is
    // what matters, and every one of them is crossed here.
    for (const boundary of [0.125, 0.625, 0.75, 1.0]) {
      world.tick = tickAtTimeOfDay(boundary) - 2;
      if (boundary === 1.0) world.tick = DAY_TICKS - 2;
      stepN(world, 4);
    }
    expect(changes).toBe(4);
  });

  it("does not re-announce a transition after a load", () => {
    // The reason the publisher is stateless: a remembered phase would be either save state
    // that can disagree with the tick, or a re-announcement of something that already
    // happened. Here the save is taken *after* nightfall and reloaded.
    const { world } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    world.tick = tickAtTimeOfDay(0.75) + 50;
    stepN(world, 5);
    const snapshot = JSON.parse(JSON.stringify(world.snapshot()));

    const second = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    second.world.restore(snapshot);
    let announced = 0;
    second.world.events.subscribe({
      id: "test.reload",
      type: "night.fell",
      handler: () => announced++,
    });
    stepN(second.world, 20);
    expect(announced).toBe(0);
  });
});

describe("threat contact", () => {
  it("sees a body inside the contact range and not one outside it", () => {
    const { world, player } = boot({ seed: SEED, wanderers: 300 });
    step(world);
    const eyes = player as number;

    expect(threatWithin(world, eyes, 0.5)).toBe(false);
    expect(threatWithin(world, eyes, 400)).toBe(true);
    // The shipped range is somewhere between those, and it is a distance rather than a
    // sightline on purpose: a fast-forward is most dangerous at night, which is exactly when
    // a sightline-based rule would stop firing.
    expect(THREAT_METRES).toBeGreaterThan(1);
    expect(THREAT_METRES).toBeLessThan(48);
  });

  it("finds nothing in a world with no zombies in it", () => {
    const { world, player } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    step(world);
    expect(threatWithin(world, player as number)).toBe(false);
  });

  it("ignores an observer that does not exist", () => {
    const { world } = boot({ seed: SEED, wanderers: 10 });
    expect(threatWithin(world, 99999)).toBe(false);
  });
});
