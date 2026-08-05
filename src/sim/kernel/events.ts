// The event bus.
// docs/21-extensibility.md: "systems publish facts and never name their consumers."

import type { EventOf, EventType, GameEvent } from "../events";

export type Subscription<T extends EventType = EventType> = {
  /** Stable id. Doubles as the tiebreak that makes handler order total. */
  readonly id: string;
  readonly type: T;
  readonly handler: (event: EventOf<T>) => void;
  /** Lower runs first within a type. Equal orders fall back to `id`. */
  readonly order?: number;
};

/**
 * Cascade guard. Handlers may publish, and those events drain in the same tick so a
 * reaction is never delayed by a frame -- but a cycle (A publishes B, B publishes A) would
 * otherwise spin forever.
 *
 * Throwing is deliberate. docs/20-ecs-and-content.md's rule is "fail loudly at load, never
 * silently at hour thirty"; a silently truncated cascade is exactly that silent failure,
 * and it would be nondeterministic besides.
 */
const MAX_CASCADE_PASSES = 16;

export class EventBus {
  private readonly subs = new Map<EventType, Subscription[]>();
  private queue: GameEvent[] = [];
  /** Everything drained this tick, in order. Part of the replay record (docs/19). */
  private record: GameEvent[] = [];

  /**
   * Subscribe to an event type.
   *
   * Handlers are kept sorted by (order, id) so execution never depends on the order modules
   * happened to be imported in. Import order is not stable across bundlers or tree-shaking,
   * which would make it a determinism bug that only shows up in a production build.
   */
  subscribe<T extends EventType>(sub: Subscription<T>): void {
    const list = this.subs.get(sub.type) ?? [];
    if (list.some((s) => s.id === sub.id)) {
      throw new Error(`EventBus: duplicate subscription id "${sub.id}" for "${sub.type}"`);
    }
    list.push(sub as unknown as Subscription);
    list.sort(
      (a, b) => (a.order ?? 0) - (b.order ?? 0) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
    );
    this.subs.set(sub.type, list);
  }

  unsubscribe(id: string): boolean {
    for (const list of this.subs.values()) {
      const i = list.findIndex((s) => s.id === id);
      if (i !== -1) {
        list.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  /** Fire and forget. The publisher never learns who listened. */
  publish(event: GameEvent): void {
    this.queue.push(event);
  }

  /**
   * Drain the queue, running handlers in deterministic order. Events published *by*
   * handlers join the same drain, up to MAX_CASCADE_PASSES.
   */
  drain(): void {
    let passes = 0;
    while (this.queue.length > 0) {
      if (++passes > MAX_CASCADE_PASSES) {
        const types = [...new Set(this.queue.map((e) => e.type))].join(", ");
        throw new Error(
          `EventBus: cascade exceeded ${MAX_CASCADE_PASSES} passes; ` +
            `likely a publish cycle involving: ${types}`,
        );
      }

      const batch = this.queue;
      this.queue = [];

      for (const event of batch) {
        this.record.push(event);
        const list = this.subs.get(event.type);
        if (list === undefined) continue;
        for (const sub of list) {
          (sub.handler as (e: GameEvent) => void)(event);
        }
      }
    }
  }

  /** Events drained this tick, in order. */
  get drained(): readonly GameEvent[] {
    return this.record;
  }

  clearRecord(): void {
    this.record = [];
  }

  /** Queued but not yet drained. Should be zero at a tick boundary. */
  get pending(): number {
    return this.queue.length;
  }
}
