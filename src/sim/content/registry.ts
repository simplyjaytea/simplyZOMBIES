// The content registry.
//
// docs/20-ecs-and-content.md#the-registry: "Content loads through a registry that walks
// content directories, parses, validates, resolves `extends`, and indexes by ID. Systems
// query the registry; nothing hardcodes content."
//
// This half is pure: it takes text that platform/ already read, and a validator that
// platform/ already built. That is what lets the whole thing run headless in a test.

import type { ModifierOp } from "../modifiers/modifiers";
import type { StatRegistry } from "../modifiers/stats";
import { IssueCollector } from "./errors";
import {
  BEHAVIOR_TAGS,
  CONTENT_TYPES,
  type ContentEntry,
  type ContentFile,
  type ContentTypeDef,
  type ContentValidator,
} from "./types";

const VALID_OPS: readonly ModifierOp[] = ["set", "add", "mul", "min", "max"];

/** Files, grouped by the content type whose directory they came from. */
export type ContentInput = {
  readonly type: ContentTypeDef;
  readonly files: readonly ContentFile[];
};

type Parsed = {
  readonly entry: ContentEntry;
  readonly type: ContentTypeDef;
  readonly file: string;
};

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * Deep merge for `extends`: child wins, objects merge, arrays replace.
 *
 * Arrays replace rather than concatenate because the alternative has no way to *remove* an
 * inherited element -- a zombie extending a base could never drop a behaviour it shouldn't
 * have. Replacing is the behaviour that keeps `extends` able to express both.
 */
function merge(parent: Record<string, unknown>, child: Record<string, unknown>): ContentEntry {
  const out: Record<string, unknown> = { ...parent };
  for (const [key, value] of Object.entries(child)) {
    const existing = out[key];
    out[key] = isPlainObject(existing) && isPlainObject(value) ? merge(existing, value) : value;
  }
  return out as ContentEntry;
}

/**
 * Walk an entry looking for anything modifier-shaped.
 *
 * Generic rather than per-type on purpose: an affix buries its modifiers under
 * `tiers[].modifiers[]`, a web node or an injury will bury them somewhere else, and a
 * per-type list of "where the modifiers are" is a thing that rots every time content
 * changes shape. Anything with a `stat` and an `op` is a modifier, wherever it sits.
 */
function eachModifier(
  value: unknown,
  path: string,
  visit: (modifier: Record<string, unknown>, path: string) => void,
): void {
  if (Array.isArray(value)) {
    value.forEach((item, i) => eachModifier(item, `${path}[${i}]`, visit));
    return;
  }
  if (!isPlainObject(value)) return;

  if ("stat" in value && "op" in value) {
    visit(value, path);
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    eachModifier(child, path === "" ? key : `${path}.${key}`, visit);
  }
}

export class ContentRegistry {
  /** typeId -> id -> resolved entry. */
  private readonly byType = new Map<string, Map<string, ContentEntry>>();

  /** Every entry of a type, ordered by id. */
  all(typeId: string): ContentEntry[] {
    const entries = this.byType.get(typeId);
    if (entries === undefined) return [];
    return [...entries.keys()].sort().map((id) => entries.get(id) as ContentEntry);
  }

  get(typeId: string, id: string): ContentEntry | undefined {
    return this.byType.get(typeId)?.get(id);
  }

  getOrThrow(typeId: string, id: string): ContentEntry {
    const entry = this.get(typeId, id);
    if (entry === undefined) throw new Error(`No ${typeId} with id "${id}"`);
    return entry;
  }

  has(typeId: string, id: string): boolean {
    return this.byType.get(typeId)?.has(id) === true;
  }

  count(typeId: string): number {
    return this.byType.get(typeId)?.size ?? 0;
  }

  get typeIds(): string[] {
    return [...this.byType.keys()].sort();
  }

  /**
   * Parse, validate, resolve `extends`, and index. Throws a single ContentError listing
   * every problem found, rather than dying on the first one.
   */
  load(inputs: readonly ContentInput[], validator: ContentValidator, stats: StatRegistry): void {
    const issues = new IssueCollector();
    const parsed: Parsed[] = [];
    const seen = new Map<string, string>(); // "type:id" -> file that defined it

    // 1. Parse, and check ids are present and unique.
    for (const { type, files } of inputs) {
      for (const file of files) {
        let raw: unknown;
        try {
          raw = JSON.parse(file.text);
        } catch (e) {
          issues.add({
            file: file.path,
            message: `not valid JSON: ${e instanceof Error ? e.message : String(e)}`,
          });
          continue;
        }

        // A file may hold one entry or an array of them.
        const entries = Array.isArray(raw) ? raw : [raw];
        for (const candidate of entries) {
          if (!isPlainObject(candidate)) {
            issues.add({ file: file.path, message: "expected an object or an array of objects" });
            continue;
          }
          const id = candidate["id"];
          if (typeof id !== "string" || id === "") {
            issues.add({ file: file.path, field: "id", message: "missing or empty string id" });
            continue;
          }

          const key = `${type.id}:${id}`;
          const previous = seen.get(key);
          if (previous !== undefined) {
            issues.add({
              file: file.path,
              entry: id,
              field: "id",
              message: `duplicate ${type.id} id, already defined in ${previous}`,
            });
            continue;
          }
          seen.set(key, file.path);
          parsed.push({ entry: candidate as ContentEntry, type, file: file.path });
        }
      }
    }

    // 2. Resolve `extends`, detecting cycles and dangling parents.
    const byKey = new Map<string, Parsed>(parsed.map((p) => [`${p.type.id}:${p.entry.id}`, p]));
    const resolved = new Map<string, ContentEntry>();
    const failed = new Set<string>();

    const resolve = (p: Parsed, chain: string[]): ContentEntry | undefined => {
      const key = `${p.type.id}:${p.entry.id}`;
      const already = resolved.get(key);
      if (already !== undefined) return already;
      if (failed.has(key)) return undefined;

      if (chain.includes(key)) {
        issues.add({
          file: p.file,
          entry: p.entry.id,
          field: "extends",
          message: `circular extends: ${[...chain, key].map((k) => k.split(":")[1]).join(" -> ")}`,
        });
        failed.add(key);
        return undefined;
      }

      const parentId = p.entry.extends;
      let out: ContentEntry = p.entry;

      if (parentId !== undefined) {
        if (typeof parentId !== "string") {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            field: "extends",
            message: "extends must be a string id",
          });
          failed.add(key);
          return undefined;
        }

        const parent = byKey.get(`${p.type.id}:${parentId}`);
        if (parent === undefined) {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            field: "extends",
            message: `extends unknown ${p.type.id} "${parentId}"`,
          });
          failed.add(key);
          return undefined;
        }

        const resolvedParent = resolve(parent, [...chain, key]);
        if (resolvedParent === undefined) {
          failed.add(key);
          return undefined;
        }

        const { extends: _dropped, ...child } = p.entry;
        out = merge(resolvedParent as Record<string, unknown>, child);
      }

      resolved.set(key, out);
      return out;
    };

    for (const p of parsed) resolve(p, []);

    // 3. Shape validation, then the semantic checks JSON Schema cannot express.
    const index = new Map<string, Map<string, ContentEntry>>();

    for (const p of parsed) {
      const key = `${p.type.id}:${p.entry.id}`;
      const entry = resolved.get(key);
      if (entry === undefined) continue; // already reported above

      if (validator.knowsType(p.type.id)) {
        for (const issue of validator.validate(p.type.id, entry)) {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            ...(issue.field === undefined ? {} : { field: issue.field }),
            message: issue.message,
          });
        }
      } else {
        issues.add({
          file: p.file,
          entry: p.entry.id,
          message: `no schema registered for content type "${p.type.id}"`,
        });
      }

      // Every modifier's stat must exist (docs/20:150) and its op must be real.
      eachModifier(entry, "", (modifier, path) => {
        const stat = modifier["stat"];
        const op = modifier["op"];

        if (typeof stat !== "string" || !stats.has(stat)) {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            field: `${path}.stat`,
            message:
              typeof stat === "string"
                ? `unknown stat "${stat}"; known: ${stats.ids().join(", ")}`
                : "stat must be a string",
          });
        }
        if (typeof op !== "string" || !VALID_OPS.includes(op as ModifierOp)) {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            field: `${path}.op`,
            message: `unknown op "${String(op)}"; known: ${VALID_OPS.join(", ")}`,
          });
        }
        if (typeof modifier["value"] !== "number") {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            field: `${path}.value`,
            message: "value must be a number",
          });
        }
      });

      // Every behavior tag must be implemented (docs/20:151).
      for (const field of p.type.tagFields ?? []) {
        const tags = entry[field];
        if (tags === undefined) continue;
        if (!Array.isArray(tags)) {
          issues.add({
            file: p.file,
            entry: p.entry.id,
            field,
            message: "expected an array of behavior tags",
          });
          continue;
        }
        tags.forEach((tag, i) => {
          if (typeof tag !== "string" || !BEHAVIOR_TAGS.includes(tag)) {
            issues.add({
              file: p.file,
              entry: p.entry.id,
              field: `${field}[${i}]`,
              message: `unimplemented behavior tag "${String(tag)}"; implemented: ${BEHAVIOR_TAGS.join(", ")}`,
            });
          }
        });
      }

      let forType = index.get(p.type.id);
      if (forType === undefined) {
        forType = new Map<string, ContentEntry>();
        index.set(p.type.id, forType);
      }
      forType.set(p.entry.id, entry);
    }

    // Nothing is published unless everything validated -- a half-loaded registry is how a
    // content error becomes a mystery at hour thirty instead of a message at boot.
    issues.throwIfAny();

    this.byType.clear();
    for (const [typeId, entries] of index) this.byType.set(typeId, entries);
  }
}

/** The content types this build knows about, re-exported for loaders. */
export { CONTENT_TYPES };
