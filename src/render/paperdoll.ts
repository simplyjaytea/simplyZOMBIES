// The paperdoll.
//
// docs/05-health-injury.md#the-condition-view: "a **paperdoll**: the parts from the table above --
// head, torso, arms, hands, legs, feet -- laid out as a body, with located conditions sitting on
// the part they are on. That is the entire idea."
//
// **It is the world's body, drawn bigger.** `drawHumanoid` takes a zoom and works in metres, so
// this file supplies a larger zoom and a tint map and gets the same rig -- the same proportions,
// the same eight octants, the same poses. That matters beyond tidiness: the paperdoll's whole claim
// is that it is a picture of *this survivor*, and a second body drawn by a second function is a
// body that will eventually disagree with the one in the street about what crouching looks like.
//
// Two tiers use it, and they differ only in size and in whether prose comes with it:
//
//   the glimpse   small, on the canvas, always visible. Tint and posture. No words.
//   the panel     large, on the inventory screen. Tint, posture, and a line per part.
//
// They are **the same readout at two levels of detail**, not two encodings of one fact. docs/05 is
// explicit that "nothing is displayed twice, once as an effect and once as a meter" -- so the
// glimpse says *where*, the panel adds *what*, and neither says *how much*.
//
// It never reaches into the world: it takes a `ConditionView`, which carries no integrity numbers
// at all. That is what makes a fill percentage unavailable rather than merely discouraged.
//
// It lives in `render/` rather than in `ui/` because the renderer draws one of the two tiers, and
// `render/` importing from `ui/` would point the layer arrow backwards -- docs/19's layers run
// sim -> render -> ui, so a screen may reach for a drawing primitive while a primitive may not
// reach for a screen. `ui/inventory.ts` imports this; nothing here imports it back.

import { CONDITION_TINTS } from "./palette";
import { BODY_SPECS, drawHumanoid, type BodyRegion, type BodySpec } from "./sprites/humanoid";
import { Archetype, Pose, POSE_FRAMES } from "./sprites/pose";
import type { ConditionView, PartView } from "../sim/condition";
import { PartState } from "../sim/modules/health";
import { Eye } from "../sim/map/tilemap";
import { Stance, stanceSpec } from "../sim/stances";

/**
 * The octant the paperdoll faces: down-and-toward the camera.
 *
 * Fixed rather than following the survivor's heading, and that is the difference between a diagram
 * and a mirror. A paperdoll that turned as the player turned would put the near arm behind the
 * torso half the time and hide the part the player is trying to look at -- and "which way am I
 * facing" is a question the world view already answers, so answering it twice would be the thing
 * docs/05 warns against.
 *
 * Four is the octant whose near side is toward the viewer, so both arms and both legs are visible
 * and the head notch reads as a face rather than as the back of a skull.
 */
const FACING_OCTANT = 4;

/**
 * Which pose shows a body on a given rung.
 *
 * The same question `selectPose` answers for the world sprite, asked with only the stance -- the
 * paperdoll is a portrait, so there is no swing, no stagger and no velocity in it. What it must not
 * do is invent a mapping: crawl draws the crawler and the crouched rungs draw the crouch, decided
 * by the **same predicate docs/28's Low class turns on**, so the figure is low exactly when the
 * survivor's sightline is.
 */
export function poseForStance(stance: Stance): Pose {
  if (stance === Stance.Crawl) return Pose.Crawl;
  return stanceSpec(stance).eye === Eye.Crouched ? Pose.Crouch : Pose.Idle;
}

/**
 * The tint map for one body, from its parts.
 *
 * Only hurt parts get an entry. An unhurt body therefore passes an **empty map** and draws in its
 * own colour, which is the right default for two reasons: docs/05's unhurt state is "no condition
 * on this part" rather than a colour it is, and it means the common case -- a survivor who is fine
 * -- looks like a person rather than like a diagram of a person.
 */
export function tintFor(parts: readonly PartView[]): Partial<Record<BodyRegion, string>> {
  const tint: Partial<Record<BodyRegion, string>> = {};
  for (const { part, state } of parts) {
    if (state === PartState.Unhurt) continue;
    const colour = CONDITION_TINTS[state];
    if (colour !== undefined) tint[part] = colour;
  }
  return tint;
}

/**
 * Whether a body is worth drawing attention to at all.
 *
 * Used by the glimpse to decide between a figure and nothing. An always-visible readout that never
 * changes teaches the player to stop looking at it, and then it is not a readout -- so an unhurt
 * survivor gets a plain silhouette and a hurt one gets the tints, which means any colour at all in
 * that corner of the screen means something.
 */
export function isNotable(view: ConditionView): boolean {
  return view.worst !== PartState.Unhurt;
}

export type PaperdollOptions = {
  /** Pixels per metre. The one knob that separates the glimpse from the panel. */
  readonly zoom: number;
  /** Where the figure's feet go. */
  readonly anchorX: number;
  readonly anchorY: number;
  /**
   * Which frame of the pose to draw. Defaults to 0.
   *
   * Exposed because a crouch and a crawl are two-frame cycles, and a paperdoll animating in place
   * would be motion nobody asked for on a screen that is meant to be read. The panel holds frame
   * 0; nothing currently advances it, and the parameter is here so that a future "he is limping"
   * animation has somewhere to go rather than needing this signature changed.
   */
  readonly frame?: number;
};

/**
 * Draw one survivor's condition as a body.
 *
 * The `sink` is the same structural type the world rig draws into, so this works against a real
 * canvas context and against the recording sink the tests use -- which is what lets the paperdoll
 * be asserted without a canvas, the way `pose.test.ts` asserts the poses.
 */
export function drawPaperdoll(
  sink: Parameters<typeof drawHumanoid>[0],
  view: ConditionView,
  options: PaperdollOptions,
): void {
  const base = BODY_SPECS[Archetype.Player];
  const pose = poseForStance(view.stance);
  const frames = POSE_FRAMES[pose] ?? 1;

  const spec: BodySpec = { ...base, tint: tintFor(view.parts) };
  drawHumanoid(
    sink,
    spec,
    pose,
    (options.frame ?? 0) % frames,
    FACING_OCTANT,
    options.zoom,
    options.anchorX,
    options.anchorY,
  );
}
