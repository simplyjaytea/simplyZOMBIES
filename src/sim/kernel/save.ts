// Save and load, the pure half.
//
// Producing and consuming a save is simulation state, so it lives here. *Writing bytes
// somewhere* is a host concern and lives in platform/storage.ts.
//
// docs/19-architecture.md#save-model, per the repo owner's decision: stable ids, a version
// stamp, stale saves detected and rejected cleanly, and no migration framework before 1.0
// -- "writing migrations against a design that's still moving is wasted work."

import { canonicalize, SAVE_VERSION } from "./serialize";
import type { World, WorldSnapshot } from "./world";

/** Everything persisted for a run. The map is absent because it regenerates from the seed. */
export type SaveFile = {
  readonly snapshot: WorldSnapshot;
  /** Written for humans reading a save; never used to make decisions. */
  readonly meta: {
    readonly savedAtTick: number;
    readonly seed: number;
  };
};

export function createSave(world: World): SaveFile {
  return {
    snapshot: world.snapshot(),
    meta: { savedAtTick: world.tick, seed: world.seed },
  };
}

/** Canonical text form. Same serializer the determinism test compares through. */
export function encodeSave(save: SaveFile): string {
  return canonicalize(save);
}

export class StaleSaveError extends Error {
  constructor(
    readonly found: number,
    readonly expected: number,
  ) {
    super(
      `This save was written by an incompatible version (save format ${found}, this build reads ${expected}). ` +
        `Saves may break before 1.0 and are not migrated -- start a new run.`,
    );
    this.name = "StaleSaveError";
  }
}

export class CorruptSaveError extends Error {
  constructor(reason: string) {
    super(`Save file is unreadable: ${reason}`);
    this.name = "CorruptSaveError";
  }
}

/**
 * Parse and check a save without applying it.
 *
 * Rejecting is the whole point. A single-slot game with no save-scumming
 * (docs/01-hardcore-contract.md) cannot afford to half-load something it doesn't
 * understand and discover the damage forty hours later.
 */
export function decodeSave(text: string): SaveFile {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    throw new CorruptSaveError(e instanceof Error ? e.message : String(e));
  }

  if (typeof raw !== "object" || raw === null) {
    throw new CorruptSaveError("expected an object");
  }

  const snapshot = (raw as { snapshot?: unknown }).snapshot;
  if (typeof snapshot !== "object" || snapshot === null) {
    throw new CorruptSaveError("missing snapshot");
  }

  const version = (snapshot as { version?: unknown }).version;
  if (typeof version !== "number") {
    throw new CorruptSaveError("missing version stamp");
  }
  if (version !== SAVE_VERSION) {
    throw new StaleSaveError(version, SAVE_VERSION);
  }

  return raw as SaveFile;
}

/**
 * Apply a save to a freshly booted world.
 *
 * The world must have been booted with the save's seed, because the map and every RNG
 * stream derive from it -- loading into a differently-seeded world would put the survivors
 * in a district that no longer exists. `World.restore` enforces that.
 */
export function applySave(world: World, save: SaveFile): void {
  world.restore(save.snapshot);
}
