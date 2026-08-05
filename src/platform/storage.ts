// Persistence.
//
// docs/22-performance.md#save-performance: "Writes are atomic -- write to a temp file, then
// rename -- so a crash mid-write can't corrupt a fifty-hour run. That's a hardcore-game
// obligation, not an optimization."
//
// Saves are frequent and single-slot (docs/01-hardcore-contract.md), so the moment of
// overwriting *is* the risk: a crash halfway through leaves the only slot truncated and the
// run gone. Both implementations below therefore write somewhere else first and switch
// over in one step.

export type Storage = {
  read: (key: string) => string | null;
  /** Must never leave a partially-written value readable under `key`. */
  write: (key: string, value: string) => void;
  remove: (key: string) => void;
};

/**
 * Node: write to a temp file in the same directory, fsync, then rename.
 *
 * Same directory matters -- rename is only atomic within a file system, so a temp file in
 * /tmp would silently degrade to a copy. fsync before the rename matters too: without it
 * the rename can land before the data, and a crash leaves an intact filename pointing at
 * an empty file, which is worse than an obvious failure.
 */
export function createFileStorage(directory: string): Storage {
  // Required lazily so that importing this module in a browser build doesn't pull in node.
  /* eslint-disable @typescript-eslint/no-require-imports */
  const fs = require("node:fs") as typeof import("node:fs");
  const path = require("node:path") as typeof import("node:path");
  /* eslint-enable @typescript-eslint/no-require-imports */

  const fileFor = (key: string): string => path.join(directory, `${key}.json`);

  return {
    read(key: string): string | null {
      try {
        return fs.readFileSync(fileFor(key), "utf8");
      } catch {
        return null;
      }
    },

    write(key: string, value: string): void {
      fs.mkdirSync(directory, { recursive: true });
      const target = fileFor(key);
      const temp = `${target}.tmp`;

      const handle = fs.openSync(temp, "w");
      try {
        fs.writeFileSync(handle, value, "utf8");
        fs.fsyncSync(handle);
      } finally {
        fs.closeSync(handle);
      }

      fs.renameSync(temp, target);
    },

    remove(key: string): void {
      try {
        fs.unlinkSync(fileFor(key));
      } catch {
        // Already gone is the desired state.
      }
    },
  };
}

/**
 * Browser: double-buffered slots with a pointer flip.
 *
 * localStorage has no rename, so the file trick doesn't transfer. Instead the payload goes
 * to whichever of two slots is *not* live, and only then does the pointer move. A crash
 * mid-write corrupts the inactive slot, which nothing reads. The pointer write is a single
 * small key, which is the smallest window this storage can offer.
 */
export function createWebStorage(
  backing: Pick<globalThis.Storage, "getItem" | "setItem" | "removeItem">,
): Storage {
  const pointerKey = (key: string): string => `${key}.live`;
  const slotKey = (key: string, slot: 0 | 1): string => `${key}.slot${slot}`;

  const liveSlot = (key: string): 0 | 1 => (backing.getItem(pointerKey(key)) === "1" ? 1 : 0);

  return {
    read(key: string): string | null {
      return backing.getItem(slotKey(key, liveSlot(key)));
    },

    write(key: string, value: string): void {
      const next: 0 | 1 = liveSlot(key) === 0 ? 1 : 0;
      backing.setItem(slotKey(key, next), value);
      backing.setItem(pointerKey(key), String(next));
    },

    remove(key: string): void {
      backing.removeItem(pointerKey(key));
      backing.removeItem(slotKey(key, 0));
      backing.removeItem(slotKey(key, 1));
    },
  };
}

/** In-memory, for tests. */
export function createMemoryStorage(): Storage {
  const map = new Map<string, string>();
  return {
    read: (key) => map.get(key) ?? null,
    write: (key, value) => void map.set(key, value),
    remove: (key) => void map.delete(key),
  };
}

export const SAVE_KEY = "simplyzombies.save";
