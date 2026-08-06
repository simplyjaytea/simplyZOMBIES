import { describe, expect, it } from "vitest";
import { canonicalize, fingerprint } from "../../src/sim/kernel/serialize";

describe("canonicalize", () => {
  it("sorts object keys, so structure decides the output rather than insertion order", () => {
    expect(canonicalize({ b: 1, a: 2 })).toBe(canonicalize({ a: 2, b: 1 }));
    expect(canonicalize({ b: 1, a: 2 })).toBe('{"a":2,"b":1}');
  });

  it("sorts nested keys too", () => {
    const a = { outer: { z: 1, a: 2 }, first: true };
    const b = { first: true, outer: { a: 2, z: 1 } };
    expect(canonicalize(a)).toBe(canonicalize(b));
  });

  it("preserves array order, which is meaningful", () => {
    expect(canonicalize([3, 1, 2])).toBe("[3,1,2]");
    expect(canonicalize([1, 2, 3])).not.toBe(canonicalize([3, 2, 1]));
  });

  it("handles primitives and null", () => {
    expect(canonicalize(null)).toBe("null");
    expect(canonicalize(true)).toBe("true");
    expect(canonicalize("hi")).toBe('"hi"');
    expect(canonicalize(42)).toBe("42");
  });

  it("distinguishes undefined from null", () => {
    expect(canonicalize(undefined)).not.toBe(canonicalize(null));
  });

  // The three determinism landmines. Each is far cheaper to catch here than to debug later
  // as "the same seed diverged, once".
  it("throws on NaN", () => {
    expect(() => canonicalize({ x: NaN })).toThrow(/NaN at \$\.x/);
  });

  it("throws on Infinity", () => {
    expect(() => canonicalize({ x: Infinity })).toThrow(/Infinity at \$\.x/);
    expect(() => canonicalize({ x: -Infinity })).toThrow(/Infinity at \$\.x/);
  });

  it("throws on negative zero", () => {
    expect(() => canonicalize({ x: -0 })).toThrow(/negative zero at \$\.x/);
    expect(() => canonicalize({ x: 0 })).not.toThrow();
  });

  it("throws on non-serializable values", () => {
    expect(() => canonicalize({ fn: () => {} })).toThrow(/cannot serialize function/);
  });

  it("names the path so a failure points at the field", () => {
    expect(() => canonicalize({ a: { b: [1, NaN] } })).toThrow(/\$\.a\.b\[1\]/);
  });
});

describe("fingerprint", () => {
  it("is stable for identical input and differs for different input", () => {
    expect(fingerprint("abc")).toBe(fingerprint("abc"));
    expect(fingerprint("abc")).not.toBe(fingerprint("abd"));
  });

  it("is a fixed-width hex string", () => {
    expect(fingerprint("anything at all")).toMatch(/^[0-9a-f]{16}$/);
  });
});
