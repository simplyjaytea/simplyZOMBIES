/// <reference types="vite/client" />
//
// Reading content in the browser.
//
// Same job as content-source-node.ts, different host: there is no file system, so Vite's
// glob import stands in for walking a directory. It is still a *pattern* rather than a
// fixed list, which is the property docs/20-ecs-and-content.md:166 actually cares about --
// dropping a new JSON file in should require no code change.
//
// Eager, because content has to be validated before the first tick; and because being a
// real module dependency is what lets Vite hot-reload it in dev.

import { CONTENT_TYPES, type ContentInput } from "../sim/content/registry";
import type { ContentFile } from "../sim/content/types";
import type { SchemaMap } from "./schema-validator";

const rawFiles = import.meta.glob("/godot/content/**/*.json", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

/** Strip the Godot project prefix so paths match the node loader's. */
function relative(path: string): string {
  return path.replace(/^\/godot\/content\//, "");
}

export function readContentFromWeb(): ContentInput[] {
  return CONTENT_TYPES.map((type) => {
    const prefix = `/godot/content/${type.directory}/`;
    const files: ContentFile[] = Object.keys(rawFiles)
      .filter((path) => path.startsWith(prefix))
      .sort() // same reason as the node loader: stable "already defined in <file>" messages
      .map((path) => ({ path: relative(path), text: rawFiles[path] as string }));
    return { type, files };
  });
}

export function readSchemasFromWeb(): SchemaMap {
  const schemas: SchemaMap = {};
  for (const type of CONTENT_TYPES) {
    const path = `/godot/content/schemas/${type.id}.schema.json`;
    const text = rawFiles[path];
    if (text === undefined) {
      throw new Error(`Missing schema for content type "${type.id}" at ${path}`);
    }
    schemas[type.id] = JSON.parse(text);
  }
  return schemas;
}
