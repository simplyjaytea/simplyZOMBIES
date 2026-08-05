// Save and load.
//
// docs/01-hardcore-contract.md makes the save single-slot, continuously written, and
// un-scummable, which means a run is one file that is overwritten constantly for dozens of
// hours. That combination is why docs/22 requires the write to be atomic and docs/19
// requires stale saves to be rejected outright rather than half-applied.

import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  createFileStorage,
  createMemoryStorage,
  createWebStorage,
  SAVE_KEY,
} from "../../src/platform/storage";
import { boot } from "../../src/sim/boot";
import {
  applySave,
  createSave,
  CorruptSaveError,
  decodeSave,
  encodeSave,
  StaleSaveError,
} from "../../src/sim/kernel/save";
import { stepN } from "../../src/sim/kernel/step";

const SEED = 4242;

function runFor(ticks: number) {
  const booted = boot({ seed: SEED, wanderers: 30, mapSize: 64 });
  stepN(booted.world, ticks);
  return booted;
}

describe("save and load", () => {
  it("round-trips a run through text", () => {
    const { world } = runFor(150);
    const text = encodeSave(createSave(world));

    const fresh = boot({ seed: SEED, wanderers: 30, mapSize: 64 });
    applySave(fresh.world, decodeSave(text));

    expect(fresh.world.serialize()).toBe(world.serialize());
    expect(fresh.world.tick).toBe(world.tick);
  });

  it("resumes to the same future as a run that never stopped", () => {
    // The property that actually matters. A save that restores the right numbers but
    // diverges on the next tick is worse than no save at all, because it looks fine.
    const straight = runFor(400);

    const halted = runFor(200);
    const text = encodeSave(createSave(halted.world));

    const resumed = boot({ seed: SEED, wanderers: 30, mapSize: 64 });
    applySave(resumed.world, decodeSave(text));
    stepN(resumed.world, 200);

    expect(resumed.world.serialize()).toBe(straight.world.serialize());
  });

  /**
   * Loading into a *live* world, which is the only thing the game actually does.
   *
   * Every other test here restores into a freshly booted world, where the command queue is
   * empty and nothing can leak across. main.ts's load() applies a save to the world already
   * running, so the queue is whatever the abandoned timeline left in it.
   */
  describe("loading into a live world", () => {
    it("does not carry the abandoned timeline's input log across", () => {
      const { world } = boot({ seed: SEED, wanderers: 30, mapSize: 64 });

      world.commands.push({ type: "move", dx: 1, dy: 0 });
      stepN(world, 100);
      const text = encodeSave(createSave(world));
      const loggedBySave = world.commands.recorded.length;
      expect(loggedBySave).toBeGreaterThan(0);

      // Keep playing -- this is the timeline the load is about to discard.
      for (let i = 0; i < 50; i++) {
        world.commands.push({ type: "move", dx: 0, dy: 1 });
        stepN(world, 1);
      }
      expect(world.commands.recorded.length).toBe(loggedBySave + 50);

      applySave(world, decodeSave(text));

      // The log must not describe ticks the resumed run has not reached. Carrying them
      // makes indexByTick(recorded) replay a run that never happened, which is exactly
      // what docs/19 wants the log for.
      expect(world.commands.recorded.filter((c) => c.tick > world.tick)).toEqual([]);
      expect(world.commands.recorded).toEqual([]);
    });

    it("does not apply a command queued before the load", () => {
      const { world } = boot({ seed: SEED, wanderers: 30, mapSize: 64 });
      stepN(world, 100);
      const text = encodeSave(createSave(world));

      // platform/input pumps every frame, so holding a key while pressing F9 lands a
      // command from the discarded timeline in the queue.
      world.commands.push({ type: "move", dx: -1, dy: 0 });
      applySave(world, decodeSave(text));

      stepN(world, 1);
      expect(world.commands.recorded).toEqual([]);
    });

    it("still resumes to the same future as a run that never stopped", () => {
      // The guarantee above must not have been bought by breaking this one.
      const straight = runFor(400);

      const live = runFor(200);
      const text = encodeSave(createSave(live.world));
      stepN(live.world, 80); // wander off down a timeline we then abandon
      applySave(live.world, decodeSave(text));
      stepN(live.world, 200);

      expect(live.world.serialize()).toBe(straight.world.serialize());
    });
  });

  it("rejects a save from an incompatible version, naming both", () => {
    const { world } = runFor(10);
    const save = JSON.parse(encodeSave(createSave(world)));
    save.snapshot.version = 999;

    expect(() => decodeSave(JSON.stringify(save))).toThrow(StaleSaveError);
    expect(() => decodeSave(JSON.stringify(save))).toThrow(/save format 999.*reads 2/s);
  });

  it("rejects a truncated or malformed save rather than half-applying it", () => {
    expect(() => decodeSave("{ not json")).toThrow(CorruptSaveError);
    expect(() => decodeSave("{}")).toThrow(/missing snapshot/);
    expect(() => decodeSave('{"snapshot":{}}')).toThrow(/missing version stamp/);
  });

  it("refuses a save whose seed does not match the world", () => {
    // The map and every RNG stream derive from the seed, so loading across seeds would put
    // the survivors in a district that no longer exists.
    const { world } = runFor(10);
    const text = encodeSave(createSave(world));
    const different = boot({ seed: SEED + 1, wanderers: 30, mapSize: 64 });

    expect(() => applySave(different.world, decodeSave(text))).toThrow(/does not match world seed/);
  });
});

describe("storage", () => {
  it("round-trips through memory storage", () => {
    const storage = createMemoryStorage();
    expect(storage.read(SAVE_KEY)).toBeNull();
    storage.write(SAVE_KEY, "payload");
    expect(storage.read(SAVE_KEY)).toBe("payload");
    storage.remove(SAVE_KEY);
    expect(storage.read(SAVE_KEY)).toBeNull();
  });

  describe("file storage", () => {
    it("round-trips through the file system", () => {
      const dir = mkdtempSync(join(tmpdir(), "sz-save-"));
      const storage = createFileStorage(dir);

      expect(storage.read(SAVE_KEY)).toBeNull();
      storage.write(SAVE_KEY, "payload");
      expect(storage.read(SAVE_KEY)).toBe("payload");

      storage.remove(SAVE_KEY);
      expect(storage.read(SAVE_KEY)).toBeNull();
    });

    it("leaves no temp file behind, so the write really did rename", () => {
      const dir = mkdtempSync(join(tmpdir(), "sz-save-"));
      createFileStorage(dir).write(SAVE_KEY, "payload");

      const files = readdirSync(dir);
      expect(files).toContain(`${SAVE_KEY}.json`);
      expect(files.filter((f) => f.endsWith(".tmp"))).toEqual([]);
    });

    it("never leaves a partially written file readable under the real name", () => {
      // The scenario the atomic write exists for: a crash during an overwrite. Simulated
      // by writing a temp file that never gets renamed -- the previous save must survive
      // intact, because it is the only copy of a fifty-hour run.
      const dir = mkdtempSync(join(tmpdir(), "sz-save-"));
      const storage = createFileStorage(dir);

      storage.write(SAVE_KEY, "the good save");
      writeFileSync(join(dir, `${SAVE_KEY}.json.tmp`), "truncated ga");

      expect(storage.read(SAVE_KEY)).toBe("the good save");
      expect(readFileSync(join(dir, `${SAVE_KEY}.json`), "utf8")).toBe("the good save");
    });

    it("overwrites an existing save in one step", () => {
      const dir = mkdtempSync(join(tmpdir(), "sz-save-"));
      const storage = createFileStorage(dir);
      storage.write(SAVE_KEY, "first");
      storage.write(SAVE_KEY, "second");
      expect(storage.read(SAVE_KEY)).toBe("second");
    });
  });

  describe("web storage", () => {
    function fakeLocalStorage() {
      const map = new Map<string, string>();
      return {
        map,
        getItem: (k: string) => map.get(k) ?? null,
        setItem: (k: string, v: string) => void map.set(k, v),
        removeItem: (k: string) => void map.delete(k),
      };
    }

    it("round-trips", () => {
      const backing = fakeLocalStorage();
      const storage = createWebStorage(backing);

      expect(storage.read(SAVE_KEY)).toBeNull();
      storage.write(SAVE_KEY, "payload");
      expect(storage.read(SAVE_KEY)).toBe("payload");
    });

    it("alternates slots, so a write never overwrites the live one", () => {
      // localStorage has no rename, so the atomicity comes from writing to the inactive
      // slot and only then moving the pointer. A crash mid-write damages the slot nothing
      // is reading.
      const backing = fakeLocalStorage();
      const storage = createWebStorage(backing);

      storage.write(SAVE_KEY, "first");
      const firstSlot = backing.getItem(`${SAVE_KEY}.live`);
      storage.write(SAVE_KEY, "second");
      const secondSlot = backing.getItem(`${SAVE_KEY}.live`);

      expect(secondSlot).not.toBe(firstSlot);
      expect(storage.read(SAVE_KEY)).toBe("second");
      // The previous payload is still intact in the other slot.
      expect(backing.getItem(`${SAVE_KEY}.slot${firstSlot}`)).toBe("first");
    });

    it("keeps serving the old save if the pointer never moves", () => {
      const backing = fakeLocalStorage();
      const storage = createWebStorage(backing);
      storage.write(SAVE_KEY, "the good save");

      // Simulate a crash after the payload write but before the pointer flip.
      const live = backing.getItem(`${SAVE_KEY}.live`);
      const inactive = live === "1" ? "0" : "1";
      backing.setItem(`${SAVE_KEY}.slot${inactive}`, "truncated ga");

      expect(storage.read(SAVE_KEY)).toBe("the good save");
    });

    it("clears both slots and the pointer on remove", () => {
      const backing = fakeLocalStorage();
      const storage = createWebStorage(backing);
      storage.write(SAVE_KEY, "a");
      storage.write(SAVE_KEY, "b");
      storage.remove(SAVE_KEY);

      expect(storage.read(SAVE_KEY)).toBeNull();
      expect([...backing.map.keys()]).toEqual([]);
    });
  });
});
