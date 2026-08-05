// Reading content off disk.
//
// docs/20-ecs-and-content.md:166 requires the registry to load *directories*, not a fixed
// file list -- that is what makes third-party content a drop-in later rather than a
// refactor. Directory walking needs a file system, so it lives here rather than in sim/,
// which has neither `fs` nor `fetch` (and, since tsconfig.sim.json, no types for them).
//
// docs/20:167 also insists the project's own content ships through this exact path, so the
// loading mechanism is exercised on every run and cannot quietly rot.

import { readdirSync, readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { CONTENT_TYPES, type ContentInput } from "../sim/content/registry";
import type { ContentFile } from "../sim/content/types";
import type { SchemaMap } from "./schema-validator";

/** Recursively collect files with the given extension, in sorted order. */
function walk(dir: string, extension: string): string[] {
  let names: string[];
  try {
    names = readdirSync(dir, { withFileTypes: true })
      .map((e) => (e.isDirectory() ? `${e.name}${sep}` : e.name))
      .sort();
  } catch {
    return []; // a content type with no directory yet is not an error
  }

  const out: string[] = [];
  for (const name of names) {
    const full = join(dir, name);
    if (name.endsWith(sep)) out.push(...walk(full, extension));
    else if (name.endsWith(extension)) out.push(full);
  }
  return out;
}

/**
 * Read every content file under `root`, grouped by type.
 *
 * Sorted, and deliberately so: the registry reports duplicate ids as "already defined in
 * <file>", and which of the two files gets named should not depend on directory iteration
 * order, which differs between file systems.
 */
export function readContentFromDisk(root: string): ContentInput[] {
  return CONTENT_TYPES.map((type) => {
    const dir = join(root, type.directory);
    const files: ContentFile[] = walk(dir, ".json").map((path) => ({
      path: relative(root, path).split(sep).join("/"),
      text: readFileSync(path, "utf8"),
    }));
    return { type, files };
  });
}

/** Read the JSON Schemas that back the content types, keyed by type id. */
export function readSchemasFromDisk(root: string): SchemaMap {
  const schemas: SchemaMap = {};
  for (const type of CONTENT_TYPES) {
    const path = join(root, "schemas", `${type.id}.schema.json`);
    try {
      schemas[type.id] = JSON.parse(readFileSync(path, "utf8"));
    } catch (e) {
      throw new Error(
        `Missing or invalid schema for content type "${type.id}" at ${path}: ` +
          (e instanceof Error ? e.message : String(e)),
      );
    }
  }
  return schemas;
}
