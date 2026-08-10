// The simulation rate.
//
// Its own file, and that is not tidiness. These two constants are needed by things the
// `World` class itself depends on -- the clock is the first -- and importing them from
// `world.ts` makes a cycle: world imports the visibility index, which imports the clock,
// which would import world. At module-init time the constant on the far side of a cycle is
// `undefined`, so `DAY_SECONDS * TICK_HZ` quietly evaluated to `NaN` and every save in the
// suite failed on a canonicalizer that (correctly) refuses to serialize one.
//
// A leaf module cannot be part of a cycle. `world.ts` re-exports both names, so every
// existing import site is unchanged.

/** Fixed simulation rate (docs/22-performance.md#targets). */
export const TICK_HZ = 20;
export const TICK_SECONDS = 1 / TICK_HZ;
