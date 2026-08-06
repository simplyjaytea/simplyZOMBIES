// The command queue.
//
// docs/19-architecture.md: "Player input goes through platform/ into a command queue that
// the sim consumes on its own tick -- so input is part of the deterministic record."
//
// That last clause is the point. A run reproduces from a seed plus this log, which is what
// turns a bug report into a seed (docs/19#determinism) and puts something behind the
// fairness promise in docs/01-hardcore-contract.md.

import type { World } from "./world";

/**
 * Movement is expressed as intent, not as a position delta. The sim decides what a
 * direction means in metres; the platform layer only reports what was asked for.
 */
export type Command =
  | { type: "move"; dx: number; dy: number }
  | { type: "sprint"; active: boolean }
  | { type: "wait" }
  /**
   * Swing, or struggle if something already has hold of you.
   *
   * One command for both because they are one button and one intent -- "get it off me".
   * Which of the two happens is a simulation rule (modules/combat.ts), not something the
   * keyboard is entitled to decide.
   */
  | { type: "attack" };

export type CommandType = Command["type"];

/** A command paired with the tick it was consumed on. */
export type TimedCommand = { tick: number; command: Command };

export class CommandQueue {
  private pending: Command[] = [];
  /** Everything consumed so far -- the input log that accompanies a save. */
  private log: TimedCommand[] = [];
  private current: readonly Command[] = [];

  push(command: Command): void {
    this.pending.push(command);
  }

  /** Take everything queued for this tick, recording it in the log. */
  take(tick: number): Command[] {
    if (this.pending.length === 0) {
      this.current = EMPTY;
      return [];
    }
    const taken = this.pending;
    this.pending = [];
    for (const command of taken) this.log.push({ tick, command });
    this.current = taken;
    return taken;
  }

  /**
   * What was taken this tick, readable by every system rather than only the first one to
   * ask.
   *
   * `take` drains, so whichever system called it owned the tick's input and no other module
   * could see it. That was invisible while the player module was the only consumer, and
   * stops being invisible the moment a second one exists: an attack is player input that
   * combat, not movement, has to act on. Draining once in the kernel and publishing the
   * result keeps input a fact about the tick instead of a resource two modules race for.
   */
  get taken(): readonly Command[] {
    return this.current;
  }

  /**
   * Index a recorded log by tick, for replay. The caller queues each tick's commands and
   * steps the world. This is what the determinism test drives, and what replaying a bug
   * report would use.
   */
  static indexByTick(log: readonly TimedCommand[]): (tick: number) => readonly Command[] {
    const byTick = new Map<number, Command[]>();
    for (const { tick, command } of log) {
      const list = byTick.get(tick);
      if (list === undefined) byTick.set(tick, [command]);
      else list.push(command);
    }
    const empty: readonly Command[] = [];
    return (tick: number) => byTick.get(tick) ?? empty;
  }

  get recorded(): readonly TimedCommand[] {
    return this.log;
  }

  clearLog(): void {
    this.log = [];
  }

  /**
   * Drop both the pending queue and the log.
   *
   * Called by `World.restore`. A restore rewinds the world to an earlier tick, and
   * anything still in this queue belongs to the timeline being discarded: pending commands
   * would apply to the restored world on its next tick, and the log would carry entries
   * stamped at ticks the resumed run is about to replay. Either one makes
   * `indexByTick(recorded)` describe a run that never happened, which is the opposite of
   * what docs/19-architecture.md#determinism wants the log for.
   *
   * Note what this deliberately does *not* do: restore the log the save was taken with.
   * The log is not in `WorldSnapshot`, so a loaded run can only be replayed from the
   * restored tick, not from tick 0. Persisting it would mean carrying every command of a
   * fifty-hour run in the save file -- a real trade worth making deliberately, not as a
   * side effect of a bug fix.
   */
  reset(): void {
    this.pending = [];
    this.log = [];
    this.current = EMPTY;
  }
}

const EMPTY: readonly Command[] = [];

/**
 * Drain the queue once per tick, at the top of the input phase.
 *
 * Kernel rather than a module, because input arriving is not optional: with the player
 * module switched off the commands must still be consumed and logged, or a run with a
 * different module configuration would replay a different input log from the same
 * recording.
 */
export function registerCommandSystems(world: World): void {
  world.systems.register({
    id: "kernel.drain-commands",
    phase: "input",
    order: -100,
    run: (w) => {
      w.commands.take(w.tick);
    },
  });
}
