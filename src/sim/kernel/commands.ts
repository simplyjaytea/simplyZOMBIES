// The command queue.
//
// docs/19-architecture.md: "Player input goes through platform/ into a command queue that
// the sim consumes on its own tick -- so input is part of the deterministic record."
//
// That last clause is the point. A run reproduces from a seed plus this log, which is what
// turns a bug report into a seed (docs/19#determinism) and puts something behind the
// fairness promise in docs/01-hardcore-contract.md.

/**
 * Movement is expressed as intent, not as a position delta. The sim decides what a
 * direction means in metres; the platform layer only reports what was asked for.
 */
export type Command =
  { type: "move"; dx: number; dy: number } | { type: "sprint"; active: boolean } | { type: "wait" };

export type CommandType = Command["type"];

/** A command paired with the tick it was consumed on. */
export type TimedCommand = { tick: number; command: Command };

export class CommandQueue {
  private pending: Command[] = [];
  /** Everything consumed so far -- the input log that accompanies a save. */
  private log: TimedCommand[] = [];

  push(command: Command): void {
    this.pending.push(command);
  }

  /** Take everything queued for this tick, recording it in the log. */
  take(tick: number): Command[] {
    if (this.pending.length === 0) return [];
    const taken = this.pending;
    this.pending = [];
    for (const command of taken) this.log.push({ tick, command });
    return taken;
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
}
