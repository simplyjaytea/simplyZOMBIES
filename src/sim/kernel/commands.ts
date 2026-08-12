// The command queue.
//
// docs/19-architecture.md: "Player input goes through platform/ into a command queue that
// the sim consumes on its own tick -- so input is part of the deterministic record."
//
// That last clause is the point. A run reproduces from a seed plus this log, which is what
// turns a bug report into a seed (docs/19#determinism) and puts something behind the
// fairness promise in docs/01-hardcore-contract.md.

import type { Stance } from "../stances";
import type { EntityId } from "./entities";

/**
 * Movement is expressed as intent, not as a position delta. The sim decides what a
 * direction means in metres; the platform layer only reports what was asked for.
 */
export type Command =
  | { type: "move"; dx: number; dy: number }
  | { type: "sprint"; active: boolean }
  /**
   * Pick a rung on the [stance ladder](../../../docs/29-movement-and-stances.md).
   *
   * An integer decision rather than an analogue one, which is why it serialises, replays and
   * fingerprints exactly the way the voice registers do
   * ([docs/27](../../../docs/27-multiplayer.md#the-transport-split-and-determinism)) -- a
   * stance is a *choice about the attention field*, and there are five of them.
   *
   * `sprint` above is the same decision expressed by a held key, kept because that is the
   * input the game shipped with. Both land on the same target; neither changes a rung
   * directly, because a stance change is a timed action.
   */
  | { type: "stance"; stance: Stance }
  | { type: "wait" }
  /**
   * Deliberate noise. The one action whose entire purpose is to write to the attention
   * field, which makes it the cheapest way to ask docs/03's question out loud: what happens
   * to a district when you stop being quiet?
   */
  | { type: "shout" }
  /**
   * Swing whatever is held, at whatever the survivor is facing.
   *
   * Carries no target and no direction. Both are read from the world at the moment the blow
   * lands rather than at the moment the key was pressed -- which is what makes the wind-up a
   * real window (docs/09-combat.md#swing-loop) rather than a delay before a decision that was
   * already made. Turning away mid-wind-up misses, and that has to be possible.
   */
  | { type: "swing" }
  /**
   * Inventory manipulation, as commands rather than as mutations.
   *
   * This is the part that is easy to get wrong. A grid inventory is a drag-and-drop screen,
   * and a drag-and-drop screen wants to write to the thing it is drawing -- which would put
   * every rearrangement outside the deterministic record and give render/ a write path into
   * sim/ that docs/19-architecture.md#layers forbids.
   *
   * So the screen *proposes* and the simulation decides. Each of these carries the entity
   * ids and cells the player indicated; `modules/inventory.ts` validates every one and
   * silently refuses the illegal ones. A replay that queues the same drags reaches the same
   * loadout, and a UI bug cannot invent a state the sim would not have reached.
   */
  | {
      type: "item.move";
      item: EntityId;
      container: EntityId;
      x: number;
      y: number;
      rotated: boolean;
    }
  | { type: "item.equip"; item: EntityId; slot: string }
  | { type: "item.unequip"; slot: string }
  | { type: "item.drop"; item: EntityId }
  /** Carries no target: what is in reach is read from the world on the tick it lands. */
  | { type: "item.pickUp" }
  | { type: "item.split"; item: EntityId; count: number };

export type CommandType = Command["type"];

/** A command paired with the tick it was consumed on. */
export type TimedCommand = { tick: number; command: Command };

const NONE: readonly Command[] = [];

export class CommandQueue {
  private pending: Command[] = [];
  /** Everything consumed so far -- the input log that accompanies a save. */
  private log: TimedCommand[] = [];
  private taken: readonly Command[] = NONE;

  push(command: Command): void {
    this.pending.push(command);
  }

  /**
   * Take everything queued for this tick, recording it in the log.
   *
   * Called once per tick by the kernel, never by a system. Draining used to be the first
   * system's job, which quietly made input single-consumer: the second module to ask got an
   * empty list, and the bug would look like "shouting works unless you are also moving".
   */
  take(tick: number): readonly Command[] {
    if (this.pending.length === 0) {
      this.taken = NONE;
      return NONE;
    }
    const taken = this.pending;
    this.pending = [];
    for (const command of taken) this.log.push({ tick, command });
    this.taken = taken;
    return taken;
  }

  /** What `take` produced this tick. Every system reads this; none of them consume it. */
  get current(): readonly Command[] {
    return this.taken;
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
