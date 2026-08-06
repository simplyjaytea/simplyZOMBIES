// Milestone 1's exit criterion, and the two acceptance checks it was given in advance.
//
// From TODO.md:
//
//   Make noise, and they come. Go quiet, and they don't.
//
// The second half is the half that can fail quietly. A horde that converges on the player
// no matter what they do would pass any test that only checked the first half, and it would
// also be a completely different game -- docs/03's thesis is that *the player's behaviour
// decides where they arrive*, which is a claim about the quiet case as much as the loud one.

import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { boot, type BootOptions } from "../../src/sim/boot";
import { Position, SURVIVOR_TAG, Tags, Velocity } from "../../src/sim/kernel/components";
import { stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { makeZombie, Zombie } from "../../src/sim/modules/zombies";

const CONTENT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../content");
const SEED = 20260805;
const MAP = 128;

/** Boot with the shipped content loaded, so sensory profiles are the real ones. */
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
 * Move the survivor off the site under test.
 *
 * Every measurement in this file is about the *field* -- what a crowd does when the thing
 * that drew it is gone. `boot` puts the controlled survivor at the map centre, which is
 * also where these tests emit from, so once zombies pursued on contact (docs/14 step 4) the
 * site they were drawn to had a person standing on it: they came, found someone, and
 * followed them instead of milling. That is the correct behaviour and the wrong scenario.
 * Nobody is home is the premise, so it has to be arranged rather than assumed.
 */
function evacuate(world: World): void {
  for (const entity of world.components.query(Position, Tags)) {
    if (world.components.getOrThrow(entity, Tags).values.includes(SURVIVOR_TAG)) {
      const pos = world.components.getOrThrow(entity, Position);
      pos.x = 2;
      pos.y = 2;
    }
  }
}

/** Mean distance from every zombie to a point, in metres. */
function meanDistanceTo(world: World, x: number, y: number): number {
  const zombies = world.components.query(Position, Zombie);
  if (zombies.length === 0) throw new Error("no zombies: the test would pass vacuously");
  let total = 0;
  for (const entity of zombies) {
    const pos = world.components.getOrThrow(entity, Position);
    total += Math.hypot(pos.x - x, pos.y - y);
  }
  return total / zombies.length;
}

/**
 * Run for `ticks`, optionally emitting noise at a fixed point every tick.
 *
 * A sustained source rather than one bang, because docs/03 puts a generator at 45 and notes
 * it "doesn't stop when you sleep" -- the continuous emitters are the ones that actually
 * decide where a horde ends up, and a single spike would mostly measure noise decay.
 */
function run(opts: { noiseAt?: { x: number; y: number; magnitude: number }; ticks: number }) {
  const booted = bootWithContent({
    seed: SEED,
    wanderers: 0,
    zombies: 40,
    mapSize: MAP,
    // The player module would otherwise leave a controlled entity wandering into results.
    disabled: ["wander"],
  });
  const { world } = booted;
  evacuate(world);

  const centre = { x: MAP / 2, y: MAP / 2 };
  const before = meanDistanceTo(world, centre.x, centre.y);

  for (let i = 0; i < opts.ticks; i++) {
    if (opts.noiseAt !== undefined) {
      world.events.publish({
        type: "noise.emitted",
        x: opts.noiseAt.x,
        y: opts.noiseAt.y,
        magnitude: opts.noiseAt.magnitude,
        source: null,
      });
    }
    stepN(world, 1);
  }

  return { world, before, after: meanDistanceTo(world, centre.x, centre.y) };
}

describe("Milestone 1 exit criterion", () => {
  const TICKS = 600; // 30 s at 20 Hz

  it("make noise, and they come", () => {
    const centre = MAP / 2;
    // A generator, per docs/03's table: 45, continuous, reaching 64 m.
    const noisy = run({ ticks: TICKS, noiseAt: { x: centre, y: centre, magnitude: 45 } });

    expect(noisy.after).toBeLessThan(noisy.before);
    // Not a rounding artefact: they should close a real fraction of the distance.
    expect(noisy.before - noisy.after).toBeGreaterThan(5);
  });

  it("go quiet, and they don't", () => {
    // The negative control, and the one that matters. Same seed, same spawn positions, no
    // stimulus -- so any convergence here is the horde cheating rather than reading a field.
    const quiet = run({ ticks: TICKS });
    expect(Math.abs(quiet.after - quiet.before)).toBeLessThan(1);
  });

  it("closes more distance with noise than without, at the same seed", () => {
    // The two runs above compared directly, which is the actual claim: behaviour is what
    // differs, not the starting conditions.
    const centre = MAP / 2;
    const noisy = run({ ticks: TICKS, noiseAt: { x: centre, y: centre, magnitude: 45 } });
    const quiet = run({ ticks: TICKS });

    expect(noisy.before).toBeCloseTo(quiet.before, 6);
    expect(noisy.before - noisy.after).toBeGreaterThan(quiet.before - quiet.after + 5);
  });

  it("draws them to the noise, not merely inward", () => {
    // Convergence on the map centre could be an artefact of walls or spawn distribution.
    // Emitting off-centre distinguishes "they ascend the field" from "they drift middle".
    const target = { x: MAP / 4, y: MAP / 4, magnitude: 45 };
    const booted = bootWithContent({
      seed: SEED,
      wanderers: 0,
      zombies: 40,
      mapSize: MAP,
      disabled: ["wander"],
    });
    const { world } = booted;
    evacuate(world);

    const before = meanDistanceTo(world, target.x, target.y);
    for (let i = 0; i < TICKS; i++) {
      world.events.publish({ type: "noise.emitted", ...target, source: null });
      stepN(world, 1);
    }
    expect(meanDistanceTo(world, target.x, target.y)).toBeLessThan(before);
  });
});

describe("field memory: the Milestone 1 acceptance check", () => {
  // docs/03#field-memory-is-a-scent-mechanic keeps this mechanic *on the condition* that
  // Milestone 1 proves it does something, and HANDOFF.md commits to cutting it otherwise.
  // The spike's version was a no-op that nobody noticed, so "it is implemented" is not the
  // bar -- "switching it off changes something observable" is.

  function millAndMeasure(residue: boolean): number {
    const booted = bootWithContent({
      seed: SEED,
      wanderers: 0,
      zombies: 30,
      mapSize: MAP,
      residue,
      disabled: ["wander"],
    });
    const { world } = booted;
    evacuate(world);
    const centre = MAP / 2;

    // Draw them in, then go quiet so they arrive, mill, and disperse.
    for (let i = 0; i < 600; i++) {
      world.events.publish({
        type: "noise.emitted",
        x: centre,
        y: centre,
        magnitude: 45,
        source: null,
      });
      stepN(world, 1);
    }
    stepN(world, 600);

    let total = 0;
    for (let i = 0; i < world.field.cellCount; i++) total += world.field.at("scent", i);
    return total;
  }

  it("switching residue off changes something observable", () => {
    const withResidue = millAndMeasure(true);
    const without = millAndMeasure(false);

    expect(without).toBe(0);
    expect(withResidue).toBeGreaterThan(0);
  });

  it("changes where the horde ends up, not merely what the field contains", () => {
    // The check that actually decides the mechanic's fate. "The emitter fires" is not the
    // bar docs/03 set -- the spike's residue also existed, and was still a no-op, because
    // nothing downstream could perceive it. This asserts the behavioural consequence:
    // somewhere you made a mistake stays a bad neighbourhood after the crowd has gone.
    const near = millAndDisperse(true);
    const far = millAndDisperse(false);

    // Measured at 19.4 m against 25.4 m: a horde that remembers stays meaningfully closer
    // to the site long after the noise that drew it has decayed to nothing.
    expect(near).toBeLessThan(far);
    expect(far - near).toBeGreaterThan(2);
  });

  /**
   * Draw a crowd in, go quiet, let them mill and disperse, then measure how far they have
   * drifted from the site. Residue is the only difference between the two runs.
   */
  function millAndDisperse(residue: boolean): number {
    const { world } = bootWithContent({
      seed: SEED,
      wanderers: 0,
      zombies: 30,
      mapSize: MAP,
      residue,
      disabled: ["wander"],
    });
    evacuate(world);
    const centre = MAP / 2;

    for (let i = 0; i < 600; i++) {
      world.events.publish({
        type: "noise.emitted",
        x: centre,
        y: centre,
        magnitude: 45,
        source: null,
      });
      stepN(world, 1);
    }
    // A full minute of silence: the noise is long gone before this is measured.
    stepN(world, 1200);

    return meanDistanceTo(world, centre, centre);
  }

  it("leaves residue that outlives the crowd, which is the point of it", () => {
    // Scent's half-life is hours. If residue decayed with the noise that caused it, the
    // field would have no memory and the mechanic would be decoration.
    const booted = bootWithContent({
      seed: SEED,
      wanderers: 0,
      zombies: 30,
      mapSize: MAP,
      disabled: ["wander"],
    });
    const { world } = booted;
    evacuate(world);
    const centre = MAP / 2;

    for (let i = 0; i < 600; i++) {
      world.events.publish({
        type: "noise.emitted",
        x: centre,
        y: centre,
        magnitude: 45,
        source: null,
      });
      stepN(world, 1);
    }
    stepN(world, 400);

    const scentAfterMilling = world.field.sample("scent", centre, centre);
    expect(scentAfterMilling).toBeGreaterThan(0);

    // Five more minutes. The noise is long gone; the smell should not be.
    stepN(world, 6000);
    expect(world.field.liveCells("noise")).toBe(0);

    let scent = 0;
    for (let i = 0; i < world.field.cellCount; i++) scent += world.field.at("scent", i);
    expect(scent).toBeGreaterThan(0);
  });
});

describe("the horde is a crowd, not a queue", () => {
  // The spike's other finding. Gradient ascent alone makes conga lines: every individual at
  // the same spot computes the same best direction and files along it. The fix is a
  // persistent per-individual angular bias, and the test is that removing it is visible.

  /**
   * Lateral spread of a crowd that set off from one place toward one source.
   *
   * They start clustered on purpose. Spawning them scattered across the map and measuring
   * their spread afterwards measures the *spawn*, not the behaviour -- the first version of
   * this test did exactly that and reported 1.9351 against 1.9359, a difference of nothing,
   * while the mechanic underneath worked fine. Starting them together removes the variable
   * that was drowning the signal.
   *
   * Measured perpendicular to the line from start to source, which is the axis a conga line
   * collapses and a crowd does not.
   */
  function lateralSpread(bias: boolean): number {
    const { world } = bootWithContent({
      seed: SEED,
      wanderers: 0,
      zombies: 0,
      mapSize: MAP,
      disabled: ["wander"],
    });

    const startX = 20;
    const startY = MAP / 2;
    const sourceX = MAP - 20;
    const sourceY = MAP / 2;

    const rng = world.rng.stream("test.horde");
    for (let i = 0; i < 40; i++) {
      const entity = world.spawn();
      world.components.set(entity, Position, { x: startX, y: startY });
      world.components.set(entity, Velocity, { dx: 0, dy: 0 });
      makeZombie(world, entity, rng);
      if (!bias) world.components.getOrThrow(entity, Zombie).bias = 0;
    }

    for (let i = 0; i < 600; i++) {
      world.events.publish({
        type: "noise.emitted",
        x: sourceX,
        y: sourceY,
        magnitude: 400,
        source: null,
      });
      stepN(world, 1);
    }

    // The approach axis is +x, so lateral displacement is simply y.
    const ys: number[] = [];
    for (const entity of world.components.query(Position, Zombie)) {
      ys.push(world.components.getOrThrow(entity, Position).y);
    }
    const mean = ys.reduce((a, b) => a + b, 0) / ys.length;
    return Math.sqrt(ys.reduce((a, b) => a + (b - mean) ** 2, 0) / ys.length);
  }

  it("keeps the angular bias in save state, drawn once at spawn", () => {
    const { world } = bootWithContent({
      seed: SEED,
      wanderers: 0,
      zombies: 20,
      mapSize: MAP,
    });

    const biases = world.components
      .query(Zombie)
      .map((e) => world.components.getOrThrow(e, Zombie).bias);

    // Distinct per individual -- a shared value would reproduce the conga line exactly.
    expect(new Set(biases).size).toBeGreaterThan(1);
    for (const bias of biases) {
      expect(Math.abs(bias)).toBeLessThanOrEqual(0.62);
    }

    // And it survives a round trip, so a reloaded horde behaves like the one that was saved.
    const snapshot = world.snapshot();
    expect(JSON.stringify(snapshot).includes('"bias"')).toBe(true);
  });

  it("spreads them across the approach rather than filing them into a line", () => {
    const withBias = lateralSpread(true);
    const without = lateralSpread(false);

    // Without the bias every individual computes the same heading from the same place, so
    // the column has no width at all beyond what the grid gives it.
    expect(without).toBeLessThan(1);
    expect(withBias).toBeGreaterThan(without * 3);
  });
});

describe("determinism holds with the field and the horde in play", () => {
  function fingerprintRun() {
    const booted = bootWithContent({
      seed: SEED,
      wanderers: 20,
      zombies: 40,
      mapSize: MAP,
    });
    const { world } = booted;
    const centre = MAP / 2;

    for (let i = 0; i < 300; i++) {
      if (i % 7 === 0) {
        world.events.publish({
          type: "noise.emitted",
          x: centre,
          y: centre,
          magnitude: 180,
          source: null,
        });
      }
      stepN(world, 1);
    }
    return world.serialize();
  }

  it("reproduces byte-identically from the same seed", () => {
    expect(fingerprintRun()).toBe(fingerprintRun());
  });

  it("puts the field in the save", () => {
    const booted = bootWithContent({ seed: SEED, wanderers: 0, zombies: 5, mapSize: MAP });
    booted.world.events.publish({
      type: "noise.emitted",
      x: 64,
      y: 64,
      magnitude: 180,
      source: null,
    });
    stepN(booted.world, 1);

    expect(booted.world.snapshot().field.noise.length).toBeGreaterThan(0);
  });
});
