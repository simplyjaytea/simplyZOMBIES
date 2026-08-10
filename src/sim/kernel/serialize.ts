// Canonical serialization.
//
// Two jobs, and it matters that they share code: comparing two runs byte-for-byte in the
// determinism test, and writing saves (docs/19-architecture.md#save-model). If the
// determinism test compared through a different path than saves use, it would be verifying
// something the game does not actually do.

/**
 * Bumped whenever the snapshot shape changes. Stale saves are rejected, never migrated,
 * pre-1.0 (docs/19-architecture.md#save-model).
 *
 * 6: `Observer` joined the components -- eyes, with a range and two arc angles
 *    (docs/28-visibility-and-sightlines.md#what-an-observer-is). A version-5 save restores
 *    survivors with no eyes at all, and an observer that cannot see is not a survivor with a
 *    default view, it is one the renderer shows nothing to. The visibility *result* is not in
 *    the snapshot and never will be -- it is derived from position, facing and the map, all
 *    three of which are already here.
 * 5: `Facing` joined the kernel components, so every moving entity carries a heading the
 *    snapshot did not previously hold. A version-4 save restores bodies with no facing at
 *    all, and the systems that will read it -- sightlines, aiming -- have no sensible
 *    default to invent for a survivor who was mid-turn when the save was written.
 * 4: the scent channel joined the field, and `AttentionEmitter` grew a scent magnitude.
 *    Both change the shape of the snapshot. Scent is stored sparsely like noise, but it
 *    decays over tens of minutes rather than seconds, so a save taken at a smelly moment
 *    legitimately carries far more live cells than a loud one ever did.
 * 3: the attention field joined the snapshot. A horde converging on a shout is mid-response
 *    to a field that no longer exists if the field is dropped, so loading would rewind the
 *    stimulus while leaving its consequences walking. Stored sparsely -- live cells only.
 * 2: modifiers joined the snapshot. They are state, not derived -- rain's contribution has
 *    to survive a save, and the alternative (every module re-emitting on load) fails the
 *    moment one forgets.
 * 1: initial kernel state -- tick, seed, rng streams, entities, components.
 */
export const SAVE_VERSION = 6;

/**
 * Values that break determinism if they ever reach state, and are far cheaper to catch at
 * the boundary than to debug later as "the same seed diverged, once":
 *
 * - `NaN` never equals itself, so no comparison of two runs can be trusted again.
 * - `Infinity` is almost always a divide-by-zero that should have been caught upstream.
 * - `-0` serializes as `0` but behaves differently under division, so a round-trip through
 *   a save silently changes behaviour.
 *
 * docs/20-ecs-and-content.md's rule for content applies just as well here: fail loudly,
 * never silently at hour thirty.
 */
function checkNumber(value: number, path: string): void {
  if (Number.isNaN(value)) throw new Error(`serialize: NaN at ${path}`);
  if (!Number.isFinite(value)) throw new Error(`serialize: ${value} at ${path}`);
  if (Object.is(value, -0)) throw new Error(`serialize: negative zero at ${path}`);
}

/**
 * Deterministic JSON: object keys sorted, array order preserved, numbers validated.
 *
 * `JSON.stringify` alone is not enough -- it emits keys in insertion order, so two
 * structurally identical worlds built by different paths produce different strings.
 */
export function canonicalize(value: unknown, path = "$"): string {
  if (value === null) return "null";

  switch (typeof value) {
    case "number":
      checkNumber(value, path);
      return JSON.stringify(value);

    case "string":
    case "boolean":
      return JSON.stringify(value);

    case "undefined":
      // Distinct from null, so a dropped field cannot masquerade as an explicit null.
      return '"__undefined__"';

    case "object": {
      if (Array.isArray(value)) {
        return `[${value.map((v, i) => canonicalize(v, `${path}[${i}]`)).join(",")}]`;
      }
      const obj = value as Record<string, unknown>;
      const parts = Object.keys(obj)
        .sort()
        .map((k) => `${JSON.stringify(k)}:${canonicalize(obj[k], `${path}.${k}`)}`);
      return `{${parts.join(",")}}`;
    }

    default:
      // Functions, symbols, bigints: something non-serializable leaked into state, which
      // breaks saves and the engine port alike (docs/19#the-portability-contract).
      throw new Error(`serialize: cannot serialize ${typeof value} at ${path}`);
  }
}

/**
 * A short comparable fingerprint of a canonical string, so a failing test prints something
 * readable instead of a megabyte of JSON. The canonical string stays the source of truth.
 */
export function fingerprint(canonical: string): string {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < canonical.length; i++) {
    const ch = canonical.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (h2 >>> 0).toString(16).padStart(8, "0") + (h1 >>> 0).toString(16).padStart(8, "0");
}
