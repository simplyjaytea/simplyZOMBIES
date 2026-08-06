// JSON Schema validation, implemented with Ajv.
//
// This is the only file in the repo that imports Ajv, on purpose. The registry in
// sim/content/ depends on the ContentValidator *contract*, not on a schema engine, so
// sim/ stays plain per docs/19-architecture.md#the-portability-contract -- a Godot port
// rewrites this file and keeps the registry.
//
// Shape only. Uniqueness, reference resolution and cycle detection are not expressible in
// JSON Schema and live in the registry instead.

import Ajv, { type ErrorObject, type ValidateFunction } from "ajv";
import type { ContentValidator, SchemaIssue } from "../sim/content/types";

/**
 * Turn an Ajv instancePath (`/tiers/1/modifiers/0/stat`) into the dotted form the rest of
 * the loader reports (`tiers[1].modifiers[0].stat`), so every error in the output reads
 * the same way regardless of which check produced it.
 */
function toFieldPath(instancePath: string): string | undefined {
  if (instancePath === "") return undefined;
  const parts = instancePath.split("/").filter((p) => p !== "");
  let out = "";
  for (const part of parts) {
    if (/^\d+$/.test(part)) out += `[${part}]`;
    else out += out === "" ? part : `.${part}`;
  }
  return out === "" ? undefined : out;
}

function describe(error: ErrorObject): string {
  const base = error.message ?? "failed validation";
  // additionalProperties names the offending key in params rather than in the path, which
  // is the one case where the default message alone doesn't say what to fix.
  if (error.keyword === "additionalProperties") {
    const extra = (error.params as { additionalProperty?: string }).additionalProperty;
    return `${base} ("${extra ?? "?"}")`;
  }
  if (error.keyword === "enum") {
    const allowed = (error.params as { allowedValues?: unknown[] }).allowedValues;
    return `${base}: ${JSON.stringify(allowed)}`;
  }
  return base;
}

export type SchemaMap = Record<string, unknown>;

/**
 * Build a validator over `typeId -> JSON Schema`.
 *
 * `allErrors` is on because a content author wants every problem in one pass, which is the
 * same reason the registry accumulates issues instead of throwing on the first.
 */
export function createSchemaValidator(schemas: SchemaMap): ContentValidator {
  const ajv = new Ajv({ allErrors: true, strict: true, allowUnionTypes: true });
  const compiled = new Map<string, ValidateFunction>();

  for (const [typeId, schema] of Object.entries(schemas)) {
    compiled.set(typeId, ajv.compile(schema as object));
  }

  return {
    knowsType(typeId: string): boolean {
      return compiled.has(typeId);
    },

    validate(typeId: string, entry: unknown): SchemaIssue[] {
      const validate = compiled.get(typeId);
      if (validate === undefined) {
        return [{ message: `no schema registered for content type "${typeId}"` }];
      }

      if (validate(entry)) return [];

      return (validate.errors ?? []).map((error) => {
        const field = toFieldPath(error.instancePath);
        return field === undefined
          ? { message: describe(error) }
          : { field, message: describe(error) };
      });
    },
  };
}
