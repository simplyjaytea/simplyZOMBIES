// The module-isolation check.
//
// docs/19-architecture.md#one-spine-many-optional-limbs states the rule and then names the
// way it is kept honest: "the game must boot and run with any non-kernel module disabled.
// This is checked in CI by booting with each module individually switched off."
//
// It is not a hypothetical. The same mechanism implements sandbox presets and the "Nothing
// Personal" storyteller (docs/17), which are not special cases -- they are this, with a
// different set disabled. If a module cannot be switched off, neither can they.

import { describe, expect, it } from "vitest";
import { ALL_MODULES, boot } from "../../src/sim/boot";
import { Position, Velocity } from "../../src/sim/kernel/components";
import { stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";

const TICKS = 200;

/** Nothing may go non-finite -- a NaN position is a silent, spreading corruption. */
function expectNoNaN(world: World): void {
  for (const entity of world.components.query(Position)) {
    const pos = world.components.getOrThrow(entity, Position);
    expect(Number.isFinite(pos.x)).toBe(true);
    expect(Number.isFinite(pos.y)).toBe(true);
  }
  for (const entity of world.components.query(Velocity)) {
    const vel = world.components.getOrThrow(entity, Velocity);
    expect(Number.isFinite(vel.dx)).toBe(true);
    expect(Number.isFinite(vel.dy)).toBe(true);
  }
  // serialize() throws on NaN, Infinity and -0, so this covers everything else in state.
  expect(() => world.serialize()).not.toThrow();
}

describe("module isolation", () => {
  it("has modules to isolate", () => {
    // Guards the premise: with an empty module list every case below would pass vacuously,
    // which is exactly how this check quietly stops meaning anything.
    expect(ALL_MODULES.length).toBeGreaterThan(0);
  });

  it("boots and runs with every module enabled", () => {
    const { world } = boot({ seed: 1, wanderers: 40, mapSize: 64 });
    expect(() => stepN(world, TICKS)).not.toThrow();
    expectNoNaN(world);
  });

  for (const module of ALL_MODULES) {
    it(`boots and runs with "${module.id}" disabled`, () => {
      const { world, modules } = boot({
        seed: 1,
        wanderers: 40,
        mapSize: 64,
        disabled: [module.id],
      });

      expect(modules.isEnabled(module.id)).toBe(false);
      expect(() => stepN(world, TICKS)).not.toThrow();
      expectNoNaN(world);
    });
  }

  it("boots and runs with every module disabled at once", () => {
    // The degenerate case: the kernel alone. Nothing moves, but nothing breaks either.
    const { world, modules } = boot({
      seed: 1,
      wanderers: 40,
      mapSize: 64,
      disabled: ALL_MODULES.map((m) => m.id),
    });

    expect(modules.enabledIds).toEqual([]);
    expect(() => stepN(world, TICKS)).not.toThrow();
    expectNoNaN(world);
    expect(world.tick).toBe(TICKS);
  });

  it("keeps entity ids stable regardless of which modules are enabled", () => {
    // Otherwise disabling a module would shift every id allocated after it, and two runs
    // of the same seed would stop matching -- turning a configuration change into a
    // determinism bug.
    const withAll = boot({ seed: 7, wanderers: 20, mapSize: 64 });
    const withoutShamblers = boot({
      seed: 7,
      wanderers: 20,
      mapSize: 64,
      disabled: ["shambler"],
    });

    expect(withoutShamblers.player).toBe(withAll.player);
    expect(withoutShamblers.world.entities.all()).toEqual(withAll.world.entities.all());
  });

  it("rejects disabling a module that does not exist", () => {
    expect(() => boot({ seed: 1, disabled: ["nonsense"], mapSize: 64, wanderers: 1 })).toThrow(
      /unknown module "nonsense"/,
    );
  });
});
