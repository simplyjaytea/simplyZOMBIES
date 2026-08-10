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

/**
 * Ticks paid off in a single frame at 1x, as a second line of defence behind the clamp.
 *
 * It scales with the speed control, which it has to: 10x at 60 fps needs 3.3 ticks a frame
 * on average and more than that whenever a frame runs long, so a fixed cap of 5 would turn
 * the fast-forward into a silent 5x. The clamp above still bounds the worst case.
 */
const MAX_TICKS_PER_FRAME = 5;

export type LoopHooks = {
  /** Called once per rendered frame, after any ticks. `alpha` is the interpolation factor
   *  in [0, 1) between the last two sim states (docs/22-performance.md#rendering). */
  render?: (world: World, alpha: number) => void;
  /**
   * Called immediately before each tick. This is where the renderer snapshots the state
   * the tick is about to leave behind, which is what it interpolates *from*. Doing it
   * after the tick instead silently defeats the interpolation.
   */
  beforeTick?: (world: World) => void;
  /** Called after each tick, for instrumentation. Must not mutate the world. */
  afterTick?: (world: World) => void;
};

export type Loop = {
  start: () => void;
  stop: () => void;
  readonly running: boolean;
  /**
   * How many simulated seconds pass per real second. docs/02-core-loop.md#time-scale:
   * pause, 1x, 3x, 10x.
   *
   * Implemented by scaling the real interval fed to the accumulator rather than by shrinking
   * the tick, which is the only version that keeps the simulation deterministic: the timestep
   * is still fixed, there are simply more of them per frame. A variable timestep would make
   * the speed control part of the replay record.
   */
  speed: number;
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
  let speed = 1;

  function frame(now: number): void {
    if (!running) return;

    let elapsed = now - last;
    last = now;
    if (elapsed > MAX_ELAPSED_MS) elapsed = MAX_ELAPSED_MS;
    if (elapsed < 0) elapsed = 0; // guard against a non-monotonic clock

    accumulator += elapsed * speed;

    let ticks = 0;
    while (accumulator >= TICK_MS && ticks < maxTicksPerFrame()) {
      hooks.beforeTick?.(world);
      step(world);
      hooks.afterTick?.(world);
      accumulator -= TICK_MS;
      ticks++;
    }

    // If the cap was hit there is still time owed. Dropping it keeps the simulation
    // running at a constant rate rather than accumulating an unpayable debt.
    if (ticks === maxTicksPerFrame() && accumulator > TICK_MS) {
      accumulator = 0;
    }

    hooks.render?.(world, accumulator / TICK_MS);

    handle = requestFrame(frame);
  }

  const maxTicksPerFrame = (): number => Math.max(1, Math.ceil(MAX_TICKS_PER_FRAME * speed));

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

    get speed(): number {
      return speed;
    },

    set speed(value: number) {
      // The accumulator holds real milliseconds owed at the old rate; carrying it across a
      // speed change would pay off that debt at the new one, which is a visible jump.
      accumulator = 0;
      speed = Math.max(0, value);
    },
  };
}
