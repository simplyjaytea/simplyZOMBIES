// Content types and the validator contract.
//
// The contract lives here, in sim/, while the JSON Schema engine that implements it lives
// in platform/. sim/ cannot depend on Ajv without dragging a library into the layer that
// docs/19-architecture.md#the-portability-contract requires stay plain -- and a Godot port
// would then have to reimplement it. Inverting the dependency keeps the registry pure and
// makes the schema engine a swappable detail.

/** A raw file handed to the registry. Reading it from disk is platform/'s job. */
export type ContentFile = {
  /** Path relative to the content root, used verbatim in error messages. */
  readonly path: string;
  readonly text: string;
};

/** A schema-level problem. The registry adds file and entry context. */
export type SchemaIssue = {
  /** Dotted path within the entry, e.g. `tiers[1].modifiers[0].stat`. */
  readonly field?: string;
  readonly message: string;
};

/**
 * Shape validation. Implemented in platform/ over real JSON Schema files, which is what
 * gives editors autocomplete via `$schema` -- the reason docs/20's cut list keeps JSON
 * rather than inventing a DSL.
 *
 * Shape only. Uniqueness, reference resolution and cycle detection are not expressible in
 * JSON Schema, so the registry does those itself.
 */
export type ContentValidator = {
  knowsType(typeId: string): boolean;
  validate(typeId: string, entry: unknown): SchemaIssue[];
};

/** A validator that accepts everything. For tests that are exercising semantic checks. */
export const permissiveValidator: ContentValidator = {
  knowsType: () => true,
  validate: () => [],
};

/**
 * Declares a content type and where its entries live.
 *
 * The directory is data rather than a hardcoded file list, because docs/20:166 makes that
 * the thing which keeps the loader mod-ready: third-party content drops into the same
 * directories and travels the same path.
 */
export type ContentTypeDef = {
  /** Type id, e.g. `zombie`. Also the schema key. */
  readonly id: string;
  /** Directory under the content root, e.g. `zombies`. */
  readonly directory: string;
  /**
   * Fields holding behavior-tag names, checked against the registered tag set.
   * docs/20:151 requires "every behavior tag is implemented".
   */
  readonly tagFields?: readonly string[];
};

/** Every content entry has a stable, namespaced string id (docs/20:86-99). */
export type ContentEntry = {
  readonly id: string;
  readonly extends?: string;
  readonly [key: string]: unknown;
};

/** The content types this build knows about. */
export const CONTENT_TYPES: readonly ContentTypeDef[] = [
  { id: "zombie", directory: "zombies", tagFields: ["behaviors"] },
  { id: "affix", directory: "affixes" },
  { id: "item", directory: "items" },
  { id: "calibration", directory: "calibration" },
];

/**
 * Behavior tags the simulation implements.
 *
 * Everything here is named by docs/20-ecs-and-content.md:113 or by the cookbook in
 * docs/21-extensibility.md:106. None of them *do* anything yet -- the systems arrive in
 * Milestone 1 -- but the set has to exist now, because validating that a zombie's
 * behaviours are implemented is exactly the check docs/20:151 asks for, and content that
 * references a tag nobody implements should fail at load rather than shamble inertly.
 */
export const BEHAVIOR_TAGS: readonly string[] = [
  "shamble",
  "pursue",
  "grab",
  "grab_low",
  "alarm_on_sight",
];
