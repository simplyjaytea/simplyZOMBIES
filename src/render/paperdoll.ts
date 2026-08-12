// The paperdoll.
//
// docs/05-health-injury.md#the-condition-view: "a **paperdoll**: the parts from the table above --
// head, torso, arms, hands, legs, feet -- laid out as a body, with located conditions sitting on
// the part they are on. That is the entire idea."
//
// **It is a diagram of a person, not a portrait of this one.** The figure is an anonymous outline
// seen flat on from the front -- `sprites/outline.ts` -- and the header of that file is where the
// reasoning lives. The short version: the paperdoll's one job is to say *which part*, and the
// district's isometric camera hides parts. It puts the far arm behind the torso, halves the legs,
// and lays a prone body up-screen. A front elevation has no far side, so all six parts are visible
// in every posture and each one is in the same place every time.
//
// This reverses docs/30's "one body, drawn at two sizes", and it keeps the thing that record was
// protecting: the street and the panel still cannot disagree about whether a survivor is low,
// because {@link poseForStance} is the only answer to that question and both the figure here and
// the sightline in docs/28 read it from `stanceSpec(stance).eye`.
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
import type { BodyRegion } from "./sprites/humanoid";
import { drawOutline, OutlinePose, type StrokeSink } from "./sprites/outline";
import type { ConditionView, PartView } from "../sim/condition";
import { PartState } from "../sim/modules/health";
import { Eye } from "../sim/map/tilemap";
import { Stance, stanceSpec } from "../sim/stances";

/**
 * Which shape shows a body on a given rung.
 *
 * Five rungs, three shapes, and the collapse is not arbitrary: crawl lies down, crouch folds, and
 * walk, jog and sprint differ by *pace*, which is not a thing a portrait has. What this must not
 * do is invent a mapping, so the fold is decided by the **same predicate docs/28's Low class turns
 * on** -- the figure is low exactly when the survivor's sightline is, and there is one answer to
 * that rather than two.
 */
export function poseForStance(stance: Stance): OutlinePose {
  if (stance === Stance.Crawl) return OutlinePose.Prone;
  return stanceSpec(stance).eye === Eye.Crouched ? OutlinePose.Crouch : OutlinePose.Stand;
}

/**
 * The tint map for one body, from its parts.
 *
 * Only hurt parts get an entry. An unhurt body therefore passes an **empty map** and draws as bare
 * line art, which is the right default for two reasons: docs/05's unhurt state is "no condition on
 * this part" rather than a colour it is, and it means any colour at all on the figure is a located
 * condition rather than decoration.
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
 * Used by the glimpse to decide whether there is anything to look at. An always-visible readout
 * that never changes teaches the player to stop looking at it, and then it is not a readout -- so
 * an unhurt survivor is an outline and nothing else, and a hurt one has colour in it.
 */
export function isNotable(view: ConditionView): boolean {
  return view.worst !== PartState.Unhurt;
}

export type PaperdollOptions = {
  /**
   * How tall a standing figure is, in pixels. The one knob that separates the glimpse from the
   * panel.
   *
   * Pixels rather than pixels-per-metre, which is what the world rig takes: the outline is a
   * diagram in fractions of its own height and is not standing on the district's ground, so a
   * zoom would be a unit borrowed from a projection this figure does not go through.
   */
  readonly height: number;
  /** Where the figure's feet go when it is standing, and its midline when it is not. */
  readonly anchorX: number;
  readonly anchorY: number;
};

/**
 * Draw one survivor's condition as a body.
 *
 * The `sink` is a structural type, so this works against a real canvas context and against the
 * recording sink the tests use -- which is what lets the figure be asserted without a canvas, the
 * way `pose.test.ts` asserts the poses.
 */
export function drawPaperdoll(
  sink: StrokeSink,
  view: ConditionView,
  options: PaperdollOptions,
): void {
  drawOutline(
    sink,
    poseForStance(view.stance),
    tintFor(view.parts),
    options.height,
    options.anchorX,
    options.anchorY,
  );
}
