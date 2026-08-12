// The stance ladder's own rules.
//
// docs/29-movement-and-stances.md states two things as design rules rather than as numbers, and
// both are the kind that a later tuning pass breaks without noticing:
//
//   1. **No stance may be strictly better than another.** "Sprint is not an upgrade over walk,
//      and crouch is not a free stealth mode."
//   2. **Faster is louder** -- which is "the whole reason this is a system and not two
//      constants".
//
// A rule with no test on it is a comment, so they are asserted here. The ladder is plain
// arithmetic and imports no module, which is what lets all of this run without a world.

import { describe, expect, it } from "vitest";
import { STAMINA_MAX } from "../../src/sim/combat";
import { TICK_HZ } from "../../src/sim/kernel/tick";
import { Eye } from "../../src/sim/map/tilemap";
import { STANCE_KEYS } from "../../src/platform/input";
import {
  DEFAULT_STANCE,
  Stance,
  STANCE_CHANGE_TICKS,
  STANCE_LADDER,
  STANCES,
  stanceChangeTicks,
  stanceSpec,
} from "../../src/sim/stances";
import { PERSON_EMITTER } from "../../src/sim/modules/attention";

/** Consecutive pairs up the ladder, slowest first. */
const RUNGS = STANCES.map(stanceSpec);
const PAIRS = RUNGS.slice(0, -1).map((lower, i) => ({
  lower,
  upper: RUNGS[i + 1] as typeof lower,
}));

describe("the ladder is ordered", () => {
  it("gets faster with every rung", () => {
    for (const { lower, upper } of PAIRS) {
      expect(upper.speedFactor).toBeGreaterThan(lower.speedFactor);
    }
  });

  it("gets louder with every rung -- faster is louder, which is the whole system", () => {
    for (const { lower, upper } of PAIRS) {
      expect(upper.noise).toBeGreaterThan(lower.noise);
    }
  });

  it("keeps its largest noise gap between jog and sprint", () => {
    // docs/29: "The large gap is between jog and sprint, and that is where the decision lives."
    // A ladder that smoothed this out would be five speed settings rather than five decisions,
    // which is exactly what that document's rule exists to prevent -- so the shape of the curve
    // is asserted, not just its direction.
    const gaps = PAIRS.map(({ lower, upper }) => upper.noise - lower.noise);
    const jogToSprint = stanceSpec(Stance.Sprint).noise - stanceSpec(Stance.Jog).noise;
    expect(jogToSprint).toBe(Math.max(...gaps));
  });
});

describe("no rung is strictly better than another", () => {
  it("pays for every gain, on every pair", () => {
    // The rule in its general form: for any two rungs, whichever is better at something must be
    // worse at something else. Checked over every pair rather than the neighbours, because
    // "crouch beats sprint at everything" would be a real failure that a neighbour walk misses.
    //
    // The four axes are the ones the ladder actually trades in: speed, quiet, stamina, and what
    // you are still allowed to do. Anything a stance is *for* has to be one of these, or the
    // ladder is hiding a fifth advantage nothing prices.
    const better = (a: (typeof RUNGS)[number], b: (typeof RUNGS)[number]): boolean =>
      a.speedFactor > b.speedFactor ||
      a.noise < b.noise ||
      a.staminaPerTick < b.staminaPerTick ||
      (a.canSwing && !b.canSwing) ||
      (a.canAim && !b.canAim) ||
      // Getting below low cover is an advantage in its own right and the reason crawl exists at
      // all -- docs/29's "needs something to be low relative to". Without this term a crawl
      // reads as strictly worse than a crouch, which is how the rule would be broken by
      // deleting the thing it protects.
      (a.eye === Eye.Crouched && b.eye !== Eye.Crouched);

    for (const a of RUNGS) {
      for (const b of RUNGS) {
        if (a === b) continue;
        expect(better(a, b), `${a.name} offers nothing over ${b.name}`).toBe(true);
      }
    }
  });

  it("lets exactly the two low rungs under low cover, and no others", () => {
    // Both directions of docs/28's Low class ride on this one field, so which rungs carry it is
    // a decision worth pinning: a jog that saw from crouch height would be strictly better than
    // a crouch, and a crouch that did not would leave `Eye.Crouched` with no writer again.
    const low = STANCES.filter((s) => stanceSpec(s).eye === Eye.Crouched);
    expect(low).toEqual([Stance.Crawl, Stance.Crouch]);
  });

  it("takes swinging away from the crawl and aiming from both ends", () => {
    expect(stanceSpec(Stance.Crawl).canSwing).toBe(false);
    expect(stanceSpec(Stance.Crawl).canAim).toBe(false);
    expect(stanceSpec(Stance.Sprint).canAim).toBe(false);
    // Everything between can do both, or "you cannot swing from a crawl" would be a general
    // penalty rather than the price of that one rung.
    for (const stance of [Stance.Crouch, Stance.Walk, Stance.Jog]) {
      expect(stanceSpec(stance).canSwing).toBe(true);
      expect(stanceSpec(stance).canAim).toBe(true);
    }
  });
});

describe("the calibrated numbers", () => {
  it("leaves walk at 1 and sprint at 6, and keeps one copy of each", () => {
    // docs/29: "The noise magnitudes did not move and must not." Magnitude 1 carries 1.4 m and
    // 6 carries 8.6 m; every claim that document makes about stealth rests on those two reaches.
    expect(stanceSpec(Stance.Walk).noise).toBe(1);
    expect(stanceSpec(Stance.Sprint).noise).toBe(6);
    // And the emitter profile reads them off the ladder rather than restating them, so there is
    // no second copy to drift.
    expect(PERSON_EMITTER.walking).toBe(stanceSpec(Stance.Walk).noise);
    expect(PERSON_EMITTER.sprinting).toBe(stanceSpec(Stance.Sprint).noise);
  });

  it("makes walk the rung with a speed factor of exactly one", () => {
    // Everything else is a ratio of a walk, so a walk that was not 1 would mean the ladder and
    // `locomotion.ts`'s `WALK_SPEED` disagreed about what a walk is.
    expect(stanceSpec(Stance.Walk).speedFactor).toBe(1);
    expect(DEFAULT_STANCE).toBe(Stance.Walk);
  });

  it("keeps a sprint three times a walk, whatever the pace", () => {
    // The ratio the emitter table is balanced against: "sprinting past something wakes it" is a
    // statement about the gap between 1 and 6 at three times the speed.
    expect(stanceSpec(Stance.Sprint).speedFactor).toBe(stanceSpec(Stance.Walk).speedFactor * 3);
  });

  it("costs stamina on exactly the rungs docs/29 says drain, and none of the others", () => {
    const drains = STANCES.filter((s) => stanceSpec(s).staminaPerTick > 0);
    // Crawl is in here on purpose -- "drains slowly; tiring to hold". A crawl that cost nothing
    // would be a free stealth mode, which is the one thing the rule above forbids.
    expect(drains).toEqual([Stance.Crawl, Stance.Jog, Stance.Sprint]);
  });

  it("empties the pool on a sprint in seconds, not minutes", () => {
    // docs/29 wants "sprint becomes unavailable before it becomes slow", and a sprint you could
    // hold for two minutes would never become unavailable inside a fight.
    const seconds = STAMINA_MAX / (stanceSpec(Stance.Sprint).staminaPerTick * TICK_HZ);
    expect(seconds).toBeGreaterThan(5);
    expect(seconds).toBeLessThan(30);
    // And a jog has to be travel rather than a slower sprint: comfortably longer, by a lot.
    const jogSeconds = STAMINA_MAX / (stanceSpec(Stance.Jog).staminaPerTick * TICK_HZ);
    expect(jogSeconds).toBeGreaterThan(seconds * 4);
  });
});

describe("changing stance costs time", () => {
  it("charges per rung travelled, not per change", () => {
    expect(stanceChangeTicks(Stance.Walk, Stance.Jog)).toBe(STANCE_CHANGE_TICKS);
    expect(stanceChangeTicks(Stance.Walk, Stance.Sprint)).toBe(STANCE_CHANGE_TICKS * 2);
    // docs/29 wants the rungs between travelled through rather than skipped, so standing up out
    // of a crawl is the most expensive thing on the ladder -- which is what makes going flat
    // with something nearby a decision you can lose.
    expect(stanceChangeTicks(Stance.Crawl, Stance.Sprint)).toBe(STANCE_CHANGE_TICKS * 4);
  });

  it("is symmetric, and free when you are already there", () => {
    expect(stanceChangeTicks(Stance.Sprint, Stance.Crawl)).toBe(
      stanceChangeTicks(Stance.Crawl, Stance.Sprint),
    );
    expect(stanceChangeTicks(Stance.Walk, Stance.Walk)).toBe(0);
  });
});

describe("every rung is reachable", () => {
  it("has a key, or is the one the sprint key carries", () => {
    // A rung nobody can select is a rung that does not exist. Sprint is the exception by design
    // -- it is the shipped held-Shift key -- so the assertion is that everything else is bound.
    const bound = new Set(Object.values(STANCE_KEYS));
    for (const stance of STANCES) {
      if (stance === Stance.Sprint) continue;
      expect(bound.has(stance), `${stanceSpec(stance).name} has no key`).toBe(true);
    }
  });

  it("names every rung, for the readouts that describe rather than measure", () => {
    const names = STANCES.map((s) => stanceSpec(s).name);
    expect(new Set(names).size).toBe(STANCES.length);
    for (const name of names) expect(name.length).toBeGreaterThan(0);
  });
});

describe("the table is complete", () => {
  it("covers every member of the enum, in order", () => {
    // `STANCES` is what every guard above iterates, so a rung added to the enum and forgotten
    // here would be a rung nothing in this file ever checks.
    const fromEnum = Object.values(Stance).filter((v): v is Stance => typeof v === "number");
    expect(STANCES).toEqual(fromEnum);
    expect(Object.keys(STANCE_LADDER)).toHaveLength(STANCES.length);
  });
});
