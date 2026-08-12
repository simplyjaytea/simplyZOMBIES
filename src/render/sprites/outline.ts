// The outline figure: a generic human, drawn as a diagram.
//
// This is the paperdoll's body, and it is deliberately **not** the body in the street. The world
// rig in `humanoid.ts` draws *this survivor* through the district's isometric camera; this draws
// *a person*, flat on, at no angle at all.
//
// ## Why a second figure, when the decision log said one
//
// docs/30 recorded "one body, drawn at two sizes, rather than two bodies", on the argument that a
// second figure would eventually disagree with the street about what crouching looks like. The
// reversal is about the camera rather than about taste. The paperdoll has exactly one job -- say
// **which part** -- and an isometric projection is hostile to that job in three ways at once: it
// puts the far arm behind the torso, it foreshortens the legs by half, and it lays a prone body
// *up-screen*, so a crawler's topmost ink sits higher than a crouch's while its head is lower.
// That last one is not a hypothetical: it is why the posture test used to compare prone by shape
// rather than by height, which is a weaker assertion than the picture deserves.
//
// A flat elevation has no near side and no far side. All six of docs/05's parts are visible in
// every posture, each in the same place every time, which is what makes the figure a *layout*.
//
// **The agreement with the street survives, one level down.** The two figures no longer share a
// function; they share the predicate (`poseForStance`, and through it `stanceSpec(stance).eye`)
// and they share the fractions a body folds at ({@link CROUCH_HEIGHT_FRACTION},
// {@link CRAWL_HEIGHT_FRACTION}, imported rather than copied). One function still answers "is this
// body low", for both pictures.
//
// ## One body, three postures
//
// There is a single set of proportions here and a single figure built from it. Standing and
// crouching differ by how far the body folds; **prone differs by the frame it is drawn in**, and
// that is the whole of it -- a lying body is the same body seen from above, turned a quarter turn,
// so it is one projection rather than a second silhouette.
//
// That is the opposite of what the world rig does, and both are right for their own camera.
// docs/14 wants a crawler in the street to be a distinct low shape, because a scaled-down standing
// body under an isometric camera does not read as prone. On a diagram there is nothing to scale
// down: a person turned sideways *is* what lying down looks like from above, and a hand-built
// prone silhouette would be a second answer to a question the rotation already answers -- with two
// sets of six parts to keep in agreement instead of one.
//
// ## Units
//
// Fractions of the standing figure's height, and nothing else. No `metresToRise`, no
// `TILE_HEIGHT_RATIO`, no octant: a diagram is not standing in the district and must not inherit
// its camera. The one input is how many pixels tall a standing body should be.
//
// Pure and sink-based, for the same reason `humanoid.ts` is: Vitest runs in node, so the geometry
// has to be assertable without a canvas.

import { COLOURS } from "../palette";
import {
  CRAWL_HEIGHT_FRACTION,
  CROUCH_HEIGHT_FRACTION,
  type BodyRegion,
  type ShapeSink,
} from "./humanoid";

/**
 * What the outline can be drawn into.
 *
 * {@link ShapeSink} widened with the stroke half of the context, because this figure is line art
 * where the world rig is solid. Picked off `CanvasRenderingContext2D` rather than restated, for
 * the reason `ShapeSink` gives: a hand-written `strokeStyle: string` looks tighter and makes a
 * real context unassignable.
 */
export type StrokeSink = ShapeSink &
  Pick<CanvasRenderingContext2D, "stroke" | "strokeStyle" | "lineWidth" | "lineJoin">;

/**
 * The three shapes a body is in, as the diagram understands it.
 *
 * Three rather than docs/29's five, and the collapse is `poseForStance`'s rather than this file's:
 * walk, jog and sprint differ by *pace*, which is not a thing a portrait has. Crawl and crouch are
 * the two rungs that change the shape of a body, which is the same thing `Eye.Crouched` says about
 * what it can see over.
 */
export const enum OutlinePose {
  Stand = 0,
  Crouch = 1,
  Prone = 2,
}

export const OUTLINE_POSES: readonly OutlinePose[] = [
  OutlinePose.Stand,
  OutlinePose.Crouch,
  OutlinePose.Prone,
];

/** Per-region colour overrides. Absent means the region is unhurt and draws as line only. */
export type RegionTint = Partial<Record<BodyRegion, string>>;

/**
 * The figure's proportions, as fractions of a standing body's height.
 *
 * A flat elevation, so these are the proportions of a person seen head on rather than the
 * projected ones `humanoid.ts` works in. Widths are fractions of height too -- one unit for the
 * whole figure means a single number scales it, and a diagram that scales as one piece cannot
 * develop a head that grows faster than its shoulders.
 *
 * `Y` is up the body from the feet and `Half` is out from the midline, in both cases before the
 * frame decides which way up the body is.
 */
const P = {
  headCentreY: 0.925,
  headRx: 0.052,
  headRy: 0.062,
  neckY: 0.855,
  neckHalf: 0.022,
  shoulderY: 0.815,
  shoulderHalf: 0.145,
  /** The waist, which is the one thing keeping the torso from reading as a slab. */
  waistY: 0.6,
  waistHalf: 0.098,
  hipY: 0.485,
  hipHalf: 0.112,
  armHalf: 0.026,
  /** How far the wrists hang below the shoulders. */
  wristY: 0.44,
  /** How far the wrists sit outboard of the shoulders. Arms clear the torso, always. */
  wristHalf: 0.175,
  handR: 0.032,
  legHalf: 0.042,
  /** Centre of each leg at the hip. */
  hipStanceHalf: 0.055,
  ankleY: 0.055,
  ankleHalf: 0.062,
  footR: 0.036,
} as const;

/**
 * How far the knees travel outboard in a crouch.
 *
 * A crouch seen head on is knees apart: the fold is forward in the world and there is no forward
 * on this figure, so the shape has to spend it sideways or the pose reads as a short person.
 * {@link CROUCH_HEIGHT_FRACTION} takes care of the height; this takes care of the knees.
 */
const CROUCH_KNEE_SPREAD = 0.085;

/**
 * How far a prone body's arms reach ahead of its shoulders, and its legs trail behind its hips.
 *
 * Seen from above, a body dragging itself forward is doing it with its arms out -- which is also
 * how the world rig draws its crawler, for the same reason. Applied only in the prone frame: the
 * limbs are re-aimed, not re-drawn.
 */
const PRONE_REACH = 0.14;

/** Where the wrists get to when the arms reach ahead: past the shoulders, level with the head. */
const PRONE_WRIST_Y = P.shoulderY + PRONE_REACH;

/** The two ends of a prone body: the reaching hands, and the trailing feet. */
const PRONE_NOSE = Math.max(P.headCentreY + P.headRy, PRONE_WRIST_Y + P.handR * 1.7);
const PRONE_TAIL = P.ankleY - PRONE_REACH - P.footR * 1.8;

/**
 * How long a prone body is, and where along itself it balances.
 *
 * A lying figure is *longer* than a standing one is tall -- the arms reach past the crown and the
 * feet trail past where they would have stood -- so the box cannot be sized off the height, and
 * the turn cannot pivot around the midpoint of a standing body either. Both come from the same
 * two ends, so a limb that reaches further tomorrow moves the box with it.
 */
const PRONE_SPAN = PRONE_NOSE - PRONE_TAIL;
const PRONE_PIVOT = (PRONE_NOSE + PRONE_TAIL) / 2;

/** Ink margin around the widest pose, as a fraction of height. Keeps a stroke off the box edge. */
const MARGIN = 0.04;

/**
 * The box one figure is drawn into, and where the anchor sits inside it.
 *
 * Sized around the **widest and tallest** pose rather than the commonest one -- the same lesson
 * `cellMetrics` learned from the crawler's shadow. Prone owns the width, standing owns the height,
 * and a box measured from either alone crops the other.
 *
 * The anchor is where the feet go when standing, and the prone body lies just above it, so a
 * figure changing posture does not walk around inside its own panel.
 */
export function outlineMetrics(height: number): {
  width: number;
  height: number;
  anchorX: number;
  anchorY: number;
} {
  const width = Math.ceil(height * (PRONE_SPAN + MARGIN * 2));
  return {
    width,
    height: Math.ceil(height * (1 + MARGIN * 2)),
    anchorX: Math.round(width / 2),
    anchorY: Math.ceil(height * (1 + MARGIN)),
  };
}

/**
 * Draw one body as an outline, with the feet at (anchorX, anchorY).
 *
 * **Stroke by default, fill only where asked.** An unhurt body is line art in one colour, so any
 * colour at all on the figure is a located condition -- which is docs/05's "colour, never fill"
 * and is also what keeps the glimpse worth looking at. A region is filled or it is not; there is
 * no partial fill for a percentage to hide in.
 */
export function drawOutline(
  sink: StrokeSink,
  pose: OutlinePose,
  tint: RegionTint,
  height: number,
  anchorX: number,
  anchorY: number,
): void {
  sink.lineWidth = Math.max(1, height * 0.014);
  sink.lineJoin = "round";
  sink.strokeStyle = COLOURS.outline;

  const prone = pose === OutlinePose.Prone;

  const frame: Frame = {
    sink,
    tint,
    prone,
    unit: height,
    project: prone
      ? // A quarter turn: along the body becomes across the screen, head to the left, out from the
        // midline becomes up and down it. The lying figure sits {@link CRAWL_HEIGHT_FRACTION} of a
        // standing body above the anchor -- the band the world rig's crawler occupies -- so a
        // survivor who goes prone drops in the panel rather than sliding across it.
        (fx, fy) => [
          anchorX + (PRONE_PIVOT - fy) * height,
          anchorY - CRAWL_HEIGHT_FRACTION * height + fx * height,
        ]
      : (fx, fy) => [anchorX + fx * height, anchorY - fy * height],
  };

  drawFigure(frame, pose);
}

type Frame = {
  sink: StrokeSink;
  tint: RegionTint;
  prone: boolean;
  /** Body coordinates -- along the body, out from the midline -- to pixels. */
  project: (fx: number, fy: number) => readonly [number, number];
  unit: number;
};

/**
 * One region, as a closed polygon: fill it if it is hurt, then outline it.
 *
 * Every shape on the figure goes through here or through {@link disc}, so a region that gains a
 * shape later cannot be the one nobody remembered to make tintable -- the same argument
 * `regionColour` makes in `humanoid.ts`.
 */
function poly(
  frame: Frame,
  region: BodyRegion,
  points: readonly (readonly [number, number])[],
): void {
  const { sink } = frame;
  if (points.length < 3) return;
  sink.beginPath();
  for (const [index, point] of points.entries()) {
    const [x, y] = frame.project(point[0], point[1]);
    if (index === 0) sink.moveTo(x, y);
    else sink.lineTo(x, y);
  }
  sink.closePath();
  paint(frame, region);
}

/**
 * One region, as an ellipse. The head, the hands and the feet.
 *
 * The radii turn with the frame, because a head seen from above is as long as it is tall the other
 * way round -- an ellipse that did not swap would be the one shape on the figure that failed to
 * lie down.
 */
function disc(
  frame: Frame,
  region: BodyRegion,
  cx: number,
  cy: number,
  rHalf: number,
  rAlong: number,
): void {
  const { sink } = frame;
  const [x, y] = frame.project(cx, cy);
  const rx = (frame.prone ? rAlong : rHalf) * frame.unit;
  const ry = (frame.prone ? rHalf : rAlong) * frame.unit;
  sink.beginPath();
  sink.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
  paint(frame, region);
}

/** Fill if the region carries a tint, and outline either way. */
function paint(frame: Frame, region: BodyRegion): void {
  const colour = frame.tint[region];
  if (colour !== undefined) {
    frame.sink.fillStyle = colour;
    frame.sink.fill();
  }
  frame.sink.stroke();
}

/** A limb segment: a quad of constant half-width between two points. */
function segment(
  frame: Frame,
  region: BodyRegion,
  from: readonly [number, number],
  to: readonly [number, number],
  half: number,
): void {
  poly(frame, region, [
    [from[0] - half, from[1]],
    [from[0] + half, from[1]],
    [to[0] + half, to[1]],
    [to[0] - half, to[1]],
  ]);
}

/**
 * The figure, in body coordinates.
 *
 * One function for all three postures. A crouch *is* the standing figure folded: every position
 * along the body is a fraction of a length that {@link CROUCH_HEIGHT_FRACTION} shortens, exactly
 * as the world rig shortens its own. A prone body is the standing figure with its limbs re-aimed
 * -- the turn itself belongs to the frame, so nothing here knows which way up the picture is.
 */
function drawFigure(frame: Frame, pose: OutlinePose): void {
  const crouched = pose === OutlinePose.Crouch;
  const prone = pose === OutlinePose.Prone;
  const fold = crouched ? CROUCH_HEIGHT_FRACTION : 1;
  const up = (f: number): number => f * fold;

  const shoulderY = up(P.shoulderY);
  const hipY = up(P.hipY);
  const kneeOut = crouched ? CROUCH_KNEE_SPREAD : 0;
  // Lying down, the legs trail out behind rather than standing under the hips.
  const ankleY = prone ? P.ankleY - PRONE_REACH : P.ankleY;
  const kneeY = (hipY + ankleY) / 2;
  // And the arms reach ahead of the shoulders instead of hanging beside them.
  const wristY = prone ? PRONE_WRIST_Y : up(P.wristY);

  // Legs first, so the torso reads as being in front of them where they meet.
  for (const side of [-1, 1]) {
    const hipX = side * P.hipStanceHalf;
    const kneeX = side * (P.hipStanceHalf + kneeOut);
    const ankleX = side * (crouched ? P.ankleHalf + kneeOut * 0.25 : P.ankleHalf);
    segment(frame, "legs", [hipX, hipY], [kneeX, kneeY], P.legHalf);
    segment(frame, "legs", [kneeX, kneeY], [ankleX, ankleY], P.legHalf * 0.86);
    disc(frame, "feet", ankleX, ankleY - P.footR * 0.8, P.footR, P.footR * 0.62);
  }

  // Arms, always drawn clear of the torso. The world rig skips a resting arm to save pixels at
  // 31 px; here the arm is a *part being asked about*, so it is never allowed to disappear.
  for (const side of [-1, 1]) {
    const shoulderX = side * (P.shoulderHalf - P.armHalf);
    // Reaching forward, the elbows come in toward the midline; standing, they stay outboard.
    const wristX = side * (prone ? P.wristHalf * 0.62 : P.wristHalf);
    const elbowX = side * ((P.shoulderHalf + Math.abs(wristX)) / 2 + (crouched ? 0.012 : 0));
    const elbowY = (shoulderY + wristY) / 2;
    segment(frame, "arms", [shoulderX, shoulderY], [elbowX, elbowY], P.armHalf);
    segment(frame, "arms", [elbowX, elbowY], [wristX, wristY], P.armHalf * 0.88);
    // The hand sits past the wrist, whichever way the arm is pointing.
    const beyond = prone ? P.handR * 0.6 : -P.handR * 0.6;
    disc(frame, "hands", wristX, wristY + beyond, P.handR, P.handR * 1.05);
  }

  // Torso: shoulders down through the waist to the hips, with the neck on top of it.
  poly(frame, "torso", [
    [-P.neckHalf, up(P.neckY)],
    [P.neckHalf, up(P.neckY)],
    [P.shoulderHalf, shoulderY],
    [P.waistHalf, up(P.waistY)],
    [P.hipHalf, hipY],
    [-P.hipHalf, hipY],
    [-P.waistHalf, up(P.waistY)],
    [-P.shoulderHalf, shoulderY],
  ]);

  // The head, last and on top, the same way the world rig draws it last.
  disc(frame, "head", 0, up(P.headCentreY), P.headRx, P.headRy);
}
