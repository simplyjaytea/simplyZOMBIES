// The fixed-timestep loop.
//
// This is the boundary between real time and simulated time, and the only code in the
// project that reads a clock. sim/ is forbidden from doing so (docs/19-architecture.md),
// which is what makes its output a function of seed and inputs alone.
//
// The accumulator shape is carried over from the spike (spike/main.ts), where both guards
// below were already earning their keep.

import { step } from "../sim/kernel/step";
import { TICK_HZ, type World } from "../sim/kernel/world";

const TICK_MS = 1000 / TICK_HZ;

/**
 * Longest real interval fed to the accumulator in one go.
 *
 * A backgrounded tab, a breakpoint, or a slow frame can hand back a gap of seconds. Without
 * a clamp the accumulator would owe hundreds of ticks, take longer than a frame to pay them
 * off, and owe even more next time -- the classic spiral of death. Clamping means the
 * simulation falls behind wall-clock time instead, which is the right trade: nobody minds
 * a lost second after a tab stall, everybody minds a locked-up page.
 */
const MAX_ELAPSED_MS = 250;

/** Ticks paid off in a single frame, as a second line of defence behind the clamp. */
const MAX_TICKS_PER_FRAME = 5;

export type LoopHooks = {
  /** Called once per rendered frame, after any ticks. `alpha` is the interpolation factor
   *  in [0, 1) between the last two sim states (docs/22-performance.md#rendering). */
  render?: (world: World, alpha: number) => void;
  /** Called after each tick, for instrumentation. Must not mutate the world. */
  afterTick?: (world: World) => void;
};

export type Loop = {
  start: () => void;
  stop: () => void;
  readonly running: boolean;
};

/** Monotonic milliseconds. Injectable so tests can drive the loop without a real clock. */
export type Clock = () => number;

/** Schedules the next frame. Injectable for the same reason. */
export type FrameScheduler = (callback: (timeMs: number) => void) => number;
export type FrameCanceller = (handle: number) => void;

export type LoopOptions = {
  clock?: Clock;
  requestFrame?: FrameScheduler;
  cancelFrame?: FrameCanceller;
};

/**
 * Drive a world in real time.
 *
 * Deliberately not started on construction -- the caller decides when the clock starts, so
 * setup work doesn't land in the first frame's elapsed time.
 */
export function createLoop(world: World, hooks: LoopHooks = {}, options: LoopOptions = {}): Loop {
  const clock = options.clock ?? (() => performance.now());
  const requestFrame = options.requestFrame ?? ((cb) => requestAnimationFrame(cb));
  const cancelFrame = options.cancelFrame ?? ((h) => cancelAnimationFrame(h));

  let accumulator = 0;
  let last = 0;
  let handle: number | null = null;
  let running = false;

  function frame(now: number): void {
    if (!running) return;

    let elapsed = now - last;
    last = now;
    if (elapsed > MAX_ELAPSED_MS) elapsed = MAX_ELAPSED_MS;
    if (elapsed < 0) elapsed = 0; // guard against a non-monotonic clock

    accumulator += elapsed;

    let ticks = 0;
    while (accumulator >= TICK_MS && ticks < MAX_TICKS_PER_FRAME) {
      step(world);
      hooks.afterTick?.(world);
      accumulator -= TICK_MS;
      ticks++;
    }

    // If the cap was hit there is still time owed. Dropping it keeps the simulation
    // running at a constant rate rather than accumulating an unpayable debt.
    if (ticks === MAX_TICKS_PER_FRAME && accumulator > TICK_MS) {
      accumulator = 0;
    }

    hooks.render?.(world, accumulator / TICK_MS);

    handle = requestFrame(frame);
  }

  return {
    start(): void {
      if (running) return;
      running = true;
      accumulator = 0;
      last = clock();
      handle = requestFrame(frame);
    },

    stop(): void {
      running = false;
      if (handle !== null) {
        cancelFrame(handle);
        handle = null;
      }
    },

    get running(): boolean {
      return running;
    },
  };
}
