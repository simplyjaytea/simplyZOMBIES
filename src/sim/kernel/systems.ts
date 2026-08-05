// The system registry.
//
// docs/20-ecs-and-content.md#system-ordering: systems run in a fixed, declared order each
// tick, and "ordering is data, not code. A module declares where it inserts. Adding a
// system doesn't require editing a hardcoded list."

import type { World } from "./world";

/**
 * The tick pipeline, verbatim from docs/20-ecs-and-content.md.
 *
 * This array *is* the ordering. A module picks a phase; it does not get to name a
 * neighbour, because "run me right after combat" is how ordering constraints turn into a
 * dependency graph nobody can reason about.
 */
export const PHASES = [
  "input",
  "ai",
  "movement",
  "combat",
  "attention-emit",
  "attention-propagate",
  "needs",
  "health",
  "infection",
  "structures",
  "director",
  "cleanup",
] as const;

export type Phase = (typeof PHASES)[number];

export type System = {
  /** Stable id. Also the final tiebreak in the ordering. */
  readonly id: string;
  readonly phase: Phase;
  /** Within a phase, lower runs first. Defaults to 0. */
  readonly order?: number;
  readonly run: (world: World) => void;
};

const PHASE_INDEX = new Map<Phase, number>(PHASES.map((p, i) => [p, i]));

export class SystemRegistry {
  private systems: System[] = [];
  private sorted = false;

  register(system: System): void {
    if (!PHASE_INDEX.has(system.phase)) {
      throw new Error(
        `System "${system.id}": unknown phase "${system.phase}". Known: ${PHASES.join(", ")}`,
      );
    }
    if (this.systems.some((s) => s.id === system.id)) {
      throw new Error(`System "${system.id}" is already registered`);
    }
    this.systems.push(system);
    this.sorted = false;
  }

  unregister(id: string): boolean {
    const i = this.systems.findIndex((s) => s.id === id);
    if (i === -1) return false;
    this.systems.splice(i, 1);
    return true;
  }

  /**
   * Execution order: (phase, order, id).
   *
   * `id` as the final tiebreak is what makes the order *total*. Without it, two systems in
   * the same phase with the same order fall back to registration order -- which depends on
   * module import order, which is not stable across bundlers or tree-shaking. That is a
   * determinism bug that would not reproduce in development.
   */
  ordered(): readonly System[] {
    if (!this.sorted) {
      this.systems.sort(
        (a, b) =>
          (PHASE_INDEX.get(a.phase) as number) - (PHASE_INDEX.get(b.phase) as number) ||
          (a.order ?? 0) - (b.order ?? 0) ||
          (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
      );
      this.sorted = true;
    }
    return this.systems;
  }

  run(world: World): void {
    for (const system of this.ordered()) system.run(world);
  }

  get ids(): string[] {
    return this.ordered().map((s) => s.id);
  }
}
