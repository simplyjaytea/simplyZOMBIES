// Modules.
//
// docs/19-architecture.md#one-spine-many-optional-limbs, the single most important
// structural rule in the design:
//
//   Kernel: the tick loop, the entity store, the event bus, and the attention field.
//   Everything else is a module.
//
// And the property that keeps it honest: "the game must boot and run with any non-kernel
// module disabled", checked in CI. That is also how sandbox presets and the "Nothing
// Personal" storyteller get implemented later -- not as special cases, but as module
// configuration.

import type { World } from "../kernel/world";
import type { TileMap } from "../map/tilemap";

/**
 * Everything a module is allowed to do at registration: add systems, subscribe to events,
 * seed content-derived state. It gets the world and the map, and nothing else -- no
 * reference to other modules, which is what stops the import graph turning into a mesh.
 */
export type ModuleContext = {
  readonly world: World;
  readonly map: TileMap;
};

export type Module = {
  /** Stable id, used to enable/disable and named by the isolation test. */
  readonly id: string;
  readonly register: (context: ModuleContext) => void;
};

export class ModuleRegistry {
  private readonly modules = new Map<string, Module>();
  private readonly enabled = new Set<string>();

  add(module: Module): void {
    if (this.modules.has(module.id)) {
      throw new Error(`Module "${module.id}" is already registered`);
    }
    this.modules.set(module.id, module);
    this.enabled.add(module.id);
  }

  disable(id: string): void {
    if (!this.modules.has(id)) throw new Error(`Cannot disable unknown module "${id}"`);
    this.enabled.delete(id);
  }

  isEnabled(id: string): boolean {
    return this.enabled.has(id);
  }

  /** Every known module id, sorted. */
  get ids(): string[] {
    return [...this.modules.keys()].sort();
  }

  get enabledIds(): string[] {
    return [...this.enabled].sort();
  }

  /**
   * Register the enabled modules, in sorted id order.
   *
   * Sorted for the same reason systems and event handlers are: registration order would
   * otherwise be module import order, which is not stable across bundlers.
   */
  registerAll(context: ModuleContext): void {
    for (const id of this.ids) {
      if (!this.enabled.has(id)) continue;
      (this.modules.get(id) as Module).register(context);
    }
  }
}
