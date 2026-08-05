// Seeded randomness.
//
// docs/19-architecture.md: "any nondeterminism introduced into sim/ is a bug of the same
// severity as a crash." Math.random is banned by lint; this is what replaces it.

/** A stream's entire state. One uint32, so saving and resuming it is trivial. */
export type RngState = number;

/**
 * mulberry32, lifted from the spike (spike/rng.ts) where it was already doing this job.
 *
 * Small, fast, and -- the property that matters here -- it has no hidden state beyond a
 * single uint32. That is what lets a run resume from a save without the sequence skipping.
 */
export class RngStream {
  private a: number;

  constructor(seed: number) {
    this.a = seed >>> 0;
  }

  /** Uniform in [0, 1). */
  next(): number {
    this.a = (this.a + 0x6d2b79f5) >>> 0;
    let t = this.a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Integer in [min, max], inclusive both ends. */
  int(min: number, max: number): number {
    return min + Math.floor(this.next() * (max - min + 1));
  }

  /** Float in [min, max). */
  float(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  bool(chanceTrue = 0.5): boolean {
    return this.next() < chanceTrue;
  }

  /** Uniform pick. Throws on empty rather than returning undefined. */
  pick<T>(items: readonly T[]): T {
    if (items.length === 0) throw new Error("rng.pick: empty array");
    return items[this.int(0, items.length - 1)] as T;
  }

  save(): RngState {
    return this.a;
  }

  restore(state: RngState): void {
    this.a = state >>> 0;
  }
}

/**
 * FNV-1a over the stream name, mixed with the master seed.
 *
 * The property worth protecting: a stream's seed depends only on its own name and the
 * master seed -- never on how many streams exist, or the order they were created in.
 *
 * So adding a "weather" stream two milestones from now leaves every existing stream's
 * sequence untouched, and every seed already recorded in a bug report still means what it
 * meant. Deriving child streams by drawing from a shared parent generator would be simpler
 * and would quietly destroy that.
 */
function deriveSeed(masterSeed: number, name: string): number {
  let h = (0x811c9dc5 ^ (masterSeed >>> 0)) >>> 0;
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  // Avoid a zero state -- mulberry32 handles it, but it reads as "unseeded" in a save file.
  return h === 0 ? 0x9e3779b9 : h;
}

/**
 * The world's named RNG streams, one per subsystem
 * (docs/19-architecture.md#determinism).
 *
 * Separate streams mean one subsystem drawing a different number of values doesn't shift
 * every other subsystem's results. Without that, adding a die roll to combat would change
 * what the weather did.
 */
export class RngRegistry {
  private readonly streams = new Map<string, RngStream>();

  constructor(readonly masterSeed: number) {}

  /** Get or lazily create a named stream. */
  stream(name: string): RngStream {
    let s = this.streams.get(name);
    if (s === undefined) {
      s = new RngStream(deriveSeed(this.masterSeed, name));
      this.streams.set(name, s);
    }
    return s;
  }

  /** Names of every stream created so far, sorted. */
  get names(): string[] {
    return [...this.streams.keys()].sort();
  }

  /** Serializable snapshot, key order canonical. */
  save(): Record<string, RngState> {
    const out: Record<string, RngState> = {};
    for (const name of this.names) {
      out[name] = (this.streams.get(name) as RngStream).save();
    }
    return out;
  }

  restore(saved: Record<string, RngState>): void {
    this.streams.clear();
    for (const [name, state] of Object.entries(saved)) {
      const s = new RngStream(deriveSeed(this.masterSeed, name));
      s.restore(state);
      this.streams.set(name, s);
    }
  }
}
