// The bodies, as shapes.
//
// Procedural rather than authored, which is the whole art pipeline: there are no image files in
// this repository and this does not add any. The same argument `buildOccluderSprites` makes for
// walls -- rasterise once, blit thereafter -- scaled from five sprites to three sheets.
//
// **It draws into a sink, not a context.** The structural type follows the precedent
// `PathSink` sets in projection.ts, and it is what makes this file testable: a recording sink in
// a node test can assert that all 336 cells stay inside their box, produce no NaN, and stand on
// their own feet. Reviewing that many generated sprites by walking around the district is not a
// review.
//
// ## The size budget
//
// At the shipped 28 px/m a 1.8 m person stands `metresToRise(1.8, 28)` = 31 px above the ground
// diamond. That is a **silhouette budget, not a detail budget**. There are no faces at 31 px, and
// docs/01-hardcore-contract.md's night takes 80% of the frame on top. So every shape below has to
// earn its pixels, and the archetypes differ by posture before they differ by colour -- posture is
// what survives the wash.

import { metresToRise, TILE_HEIGHT_RATIO, TILE_WIDTH_RATIO } from "../projection";
import { COLOURS, SHADE, SHADOW } from "../palette";
import { Archetype, OCTANTS, Pose } from "./pose";

/**
 * What a body can be drawn into.
 *
 * Structural, for the reason the header gives. Everything including `fillStyle` is picked off
 * `CanvasRenderingContext2D` rather than restated, so a real context satisfies it exactly -- a
 * hand-written `fillStyle: string` looks tighter and is wrong, because a context's is
 * `string | CanvasGradient | CanvasPattern` and the narrower type makes the real thing
 * unassignable.
 */
export type ShapeSink = Pick<
  CanvasRenderingContext2D,
  | "beginPath"
  | "moveTo"
  | "lineTo"
  | "closePath"
  | "fill"
  | "ellipse"
  | "save"
  | "restore"
  | "fillStyle"
>;

/**
 * The parts of a body this rig draws separately, and can therefore colour separately.
 *
 * docs/05's six, exactly -- so the condition view's parts and the shapes on screen are the same
 * list rather than two lists that have to be mapped onto each other. `hands` and `feet` are the
 * ends of the limbs rather than shapes of their own, which is enough at the sizes involved: a
 * hand is about two pixels in the world view, and on the paperdoll it is a marker at the wrist.
 */
export type BodyRegion = "head" | "torso" | "arms" | "hands" | "legs" | "feet";

/**
 * A body's proportions and posture.
 *
 * Metres throughout, so the same spec draws correctly at any zoom and the figures stay in
 * proportion with the walls -- both go through {@link metresToRise}.
 */
export type BodySpec = {
  colour: string;
  /**
   * Per-region colour overrides, for the paperdoll.
   *
   * **Absent in the world view, and that is the design rather than an optimisation.** docs/05 puts
   * located conditions on the condition view; a survivor whose bad leg was tinted amber out in the
   * street would be a health readout painted onto the world, which is a bar with extra steps. The
   * body in the district is one colour because what it is *for* is being identified at forty
   * metres in the dark.
   *
   * Anything absent falls back to {@link colour}, so a partial map is legitimate -- and a zombie,
   * which has no `arms` part to report, simply never supplies one.
   */
  tint?: Partial<Record<BodyRegion, string>>;
  /** Standing height. A person is about 1.8 m; a shambler stands slightly shorter for stooping. */
  heightMetres: number;
  /** Shoulder width. */
  shoulderMetres: number;
  /** Head radius. */
  headMetres: number;
  /**
   * Radians the torso leans forward off vertical.
   *
   * Zero for a survivor. Positive for a shambler, and this is the single most load-bearing
   * number in the file: it is the cue that still reads when the night has taken the colour.
   */
  stoop: number;
  /** Arms hang at the sides, or reach ahead. docs/14's zombies reach. */
  armsForward: boolean;
  /** How far a foot swings from centre at the extremes of the cycle, in metres. */
  strideMetres: number;
};

/**
 * The three archetypes.
 *
 * Ordered by what a player reads first in a dark district: **hue** at any distance, **posture** at
 * conversational distance, **brightness** last. The survivor is the player's colour darkened --
 * see the palette's note on why they are the same family and not a fourth hue.
 */
export const BODY_SPECS: Readonly<Record<Archetype, BodySpec>> = {
  [Archetype.Player]: {
    colour: COLOURS.player,
    heightMetres: 1.8,
    shoulderMetres: 0.52,
    headMetres: 0.115,
    stoop: 0,
    armsForward: false,
    strideMetres: 0.3,
  },
  [Archetype.Survivor]: {
    colour: COLOURS.survivor,
    heightMetres: 1.75,
    shoulderMetres: 0.5,
    headMetres: 0.113,
    stoop: 0.04,
    armsForward: false,
    strideMetres: 0.28,
  },
  [Archetype.Zombie]: {
    colour: COLOURS.wanderer,
    // Shorter standing, because it is stooping rather than because it is small.
    heightMetres: 1.68,
    shoulderMetres: 0.56,
    headMetres: 0.12,
    // docs/14's shambler, in one number: the head sits forward of the shoulder line.
    //
    // Tuned down from 0.3 against the sheet. The displacement scales with *standing height* and
    // the whole body is only about 15 px wide at the shipped zoom, so 0.3 rad carried the head a
    // full body-width past the hips -- which did not read as a stoop, it read as a head that had
    // come off. A stoop only has a few pixels to work in here, and it needs all of them to stay
    // attached to the shoulders.
    stoop: 0.15,
    armsForward: true,
    // A shuffle: the feet barely leave the ground line.
    strideMetres: 0.16,
  },
};

/**
 * Metres of clearance above the tallest head, for poses whose arms go up.
 *
 * Sized by the wind-up, which is the sheet's highest-reaching frame: it raises both arms above
 * and behind the shoulder, and the shoulder itself rides up for the octants that turn the near
 * side of the body toward the top of the screen. A cell that clipped it would crop the one frame
 * whose whole job is to be legible *before* it lands, which is the frame docs/09-combat.md's cut
 * list leans on hardest.
 *
 * The containment test is what holds this honest -- it fails the moment a pose out-reaches the
 * budget, rather than shipping a cropped arm nobody notices until the sheet is on screen.
 */
const HEADROOM_METRES = 0.95;

/** Half the ground ellipse's width, in metres. */
const SHADOW_RADIUS_METRES = 0.3;

/**
 * How much wider a crawler's shadow is than a standing body's.
 *
 * A prone body touches the ground along its length rather than at two feet. It is a constant
 * rather than a literal because {@link cellMetrics} has to size the box around the *widest*
 * shadow on the sheet -- sizing it around the standing one crops the crawler, which is exactly
 * what the containment test caught.
 */
const CRAWL_SHADOW_SCALE = 1.7;

/** How far a crawler lies down: its height as a fraction of standing. */
const CRAWL_HEIGHT_FRACTION = 0.34;

/**
 * How far a crouching body comes down: its height as a fraction of standing.
 *
 * Between the crawler's 0.34 and a standing 1, and nearer the top than the middle. Two thirds is
 * about where a real crouch puts the eyeline, and it is also the smallest reduction that still
 * reads at 31 px -- much less and a crouched survivor looks like a shorter survivor, which is
 * information the player would misread rather than miss.
 */
const CROUCH_HEIGHT_FRACTION = 0.68;

/** A crawler stretches out along the ground as much as it loses in height. */
const CRAWL_LENGTH_METRES = 1.1;

/**
 * The pixel box one body is drawn into, and where its feet sit inside it.
 *
 * Width is one tile diamond, so a body and a wall occupy the same footprint budget -- an arm out
 * mid-swing reaches about a metre, which fits. Height is the standing body, plus the headroom
 * above, plus the lower half of the contact shadow below the feet.
 */
export function cellMetrics(zoom: number): {
  width: number;
  height: number;
  anchorX: number;
  anchorY: number;
} {
  const width = Math.ceil(zoom * TILE_WIDTH_RATIO);
  const tallest = Math.max(...Object.values(BODY_SPECS).map((spec) => spec.heightMetres));
  const rise = metresToRise(tallest + HEADROOM_METRES, zoom);
  // The widest shadow on the sheet, not the commonest one: the box has to hold the crawler.
  const shadowRx = SHADOW_RADIUS_METRES * zoom * CRAWL_SHADOW_SCALE;
  const shadowDrop = Math.ceil((shadowRx * TILE_HEIGHT_RATIO) / TILE_WIDTH_RATIO) + 1;
  const anchorY = Math.ceil(rise);
  return {
    width,
    height: anchorY + shadowDrop,
    anchorX: Math.round(width / 2),
    anchorY,
  };
}

/**
 * A heading's screen direction, as the unit vector one metre along it projects to.
 *
 * Computed through the projection rather than by rotating a screen angle, for the reason the
 * facing stub used to give before the models replaced it: same answer, and it cannot drift from
 * where the projection actually puts things. The vertical component is halved by the 2:1 squash,
 * which is exactly why a stride to the north-east looks shorter than one to the east -- and it
 * should.
 */
function octantDirection(octant: number): { dx: number; dy: number } {
  const radians = (octant * Math.PI * 2) / OCTANTS;
  const wx = Math.cos(radians);
  const wy = Math.sin(radians);
  // The projection's axes, per metre, normalised out of the zoom.
  return {
    dx: (wx - wy) / TILE_WIDTH_RATIO,
    dy: ((wx + wy) / TILE_HEIGHT_RATIO) * 0.5,
  };
}

/**
 * The colour a region draws in: its tint if the caller supplied one, the body's colour otherwise.
 *
 * One function rather than `spec.tint?.head ?? spec.colour` repeated at a dozen call sites, so a
 * region that gains a shape later cannot be the one nobody remembered to make tintable.
 */
function regionColour(spec: BodySpec, region: BodyRegion): string {
  return spec.tint?.[region] ?? spec.colour;
}

/** Fill a polygon, then lay a shade over it. Same two-fill trick the occluder sprites use. */
function facet(
  sink: ShapeSink,
  points: readonly (readonly [number, number])[],
  colour: string,
  shade?: string,
): void {
  if (points.length < 3) return;
  sink.beginPath();
  sink.moveTo(
    (points[0] as readonly [number, number])[0],
    (points[0] as readonly [number, number])[1],
  );
  for (let i = 1; i < points.length; i++) {
    const point = points[i] as readonly [number, number];
    sink.lineTo(point[0], point[1]);
  }
  sink.closePath();
  sink.fillStyle = colour;
  sink.fill();
  if (shade !== undefined) {
    sink.fillStyle = shade;
    sink.fill();
  }
}

/**
 * A hand or a foot: a small disc at the end of a limb, drawn **only when tinted**.
 *
 * docs/05 makes hands and feet parts in their own right -- hands cost fine work, feet cost speed
 * and stealth -- so the condition view has to be able to point at them. At 31 px in the world
 * they are not worth a shape, and drawing one would spend pixels the size budget at the top of
 * this file says are not available.
 *
 * So the marker appears exactly where it is being *asked about*: absent by default, present when
 * the caller supplied a tint for that region. The world sprite is unchanged, byte for byte,
 * because it never supplies one.
 */
function extremity(
  sink: ShapeSink,
  spec: BodySpec,
  region: "hands" | "feet",
  x: number,
  y: number,
  limbWidth: number,
  shade?: string,
): void {
  const colour = spec.tint?.[region];
  if (colour === undefined) return;

  const r = limbWidth * 0.62;
  sink.beginPath();
  sink.ellipse(x, y, r, r * TILE_HEIGHT_RATIO * 0.92, 0, 0, Math.PI * 2);
  sink.fillStyle = colour;
  sink.fill();
  if (shade !== undefined) {
    sink.fillStyle = shade;
    sink.fill();
  }
}

/** A limb: a quad tapering from `width` at the top to two thirds of it at the bottom. */
function limb(
  sink: ShapeSink,
  x0: number,
  y0: number,
  x1: number,
  y1: number,
  width: number,
  colour: string,
  shade?: string,
): void {
  const half = width / 2;
  const narrow = half * 0.68;
  facet(
    sink,
    [
      [x0 - half, y0],
      [x0 + half, y0],
      [x1 + narrow, y1],
      [x1 - narrow, y1],
    ],
    colour,
    shade,
  );
}

/**
 * Draw one cell of one archetype, with the feet at (anchorX, anchorY).
 *
 * Order is back to front within the body: shadow, far leg, far arm, torso, near arm, near leg,
 * head. The head is last because it is the primary facing cue and nothing may cut into it.
 */
export function drawHumanoid(
  sink: ShapeSink,
  spec: BodySpec,
  pose: Pose,
  frame: number,
  octant: number,
  zoom: number,
  anchorX: number,
  anchorY: number,
): void {
  const dir = octantDirection(octant);
  const metre = (m: number): number => metresToRise(m, zoom);
  const across = (m: number): number => m * zoom;

  groundShadow(sink, anchorX, anchorY, zoom, pose);

  if (pose === Pose.Crawl) {
    drawCrawler(sink, spec, frame, dir, zoom, anchorX, anchorY);
    return;
  }

  // How far through a two-beat cycle this frame is, as a signed swing in [-1, 1]. Frames 0 and 2
  // are the passing positions where the feet are together; 1 and 3 are the extremes.
  const swing = cycleSwing(pose, frame);
  const stride = across(spec.strideMetres) * swing;

  // The stoop pitches the whole upper body along the facing.
  //
  // Applied as an offset at shoulder height rather than as a rotation: at 31 px the two are the
  // same handful of pixels, and an offset cannot produce a NaN. The displacement is *forward
  // along the ground*, so it goes through the same projected direction everything else does --
  // which means a body stooping away from the camera moves up-screen, because that is what
  // moving away looks like here.
  //
  // The vertical term is not doubled, and the height uses `cos(stoop)`. Both matter: a stoop
  // lowers a body's head, it does not raise it, and an over-driven lean pushed the head clean
  // out of the cell for the octants facing away. The containment test caught exactly that.
  const forward = spec.heightMetres * Math.sin(spec.stoop);
  const leanX = dir.dx * forward * zoom;
  const leanY = dir.dy * forward * zoom;
  // A crouch is the standing body, shorter. It reuses every proportion below rather than getting
  // a shape of its own -- unlike the crawler, which needed one because a scaled-down standing
  // body genuinely does not read as prone. A crouch does: shoulders unchanged, head lower, legs
  // folded, which is what {@link CROUCH_HEIGHT_FRACTION} produces for free by shortening the one
  // number every vertical below is a fraction of.
  const standingHeight =
    spec.heightMetres * Math.cos(spec.stoop) * (pose === Pose.Crouch ? CROUCH_HEIGHT_FRACTION : 1);

  const hipY = anchorY - metre(standingHeight * 0.47);
  // The neck: the head's lean is measured from the shoulder rather than from the ground, so a
  // leaning body keeps its head on top of its shoulders instead of beside them.
  const shoulderY = anchorY - metre(standingHeight * 0.83) + Math.abs(leanY) * 0.25;
  const headY = anchorY - metre(standingHeight) + metre(spec.headMetres);
  const halfShoulder = across(spec.shoulderMetres) / 2;
  const legWidth = across(spec.shoulderMetres * 0.3);
  const armWidth = across(spec.shoulderMetres * 0.22);

  // Which side of the body is nearer the camera. The near shoulder draws wider and unshaded,
  // which is the second of the three facing cues -- the others are the head notch and the
  // stride axis. Any one alone fails at this size; stacked, they read.
  const nearSign = dir.dy >= 0 ? 1 : -1;
  const perpX = -dir.dy;
  const perpY = dir.dx;

  // Feet, swung along the facing rather than along the screen.
  const farFootX = anchorX - dir.dx * stride;
  const farFootY = anchorY - dir.dy * stride * 0.5;
  const nearFootX = anchorX + dir.dx * stride;
  const nearFootY = anchorY + dir.dy * stride * 0.5;

  // The lean is distributed up the body: the hips barely move, the shoulders carry most of it,
  // and the head goes a little further still. The head multiplier is small on purpose -- it is
  // the difference between a head leading the shoulders and a head detached from them.
  const hipX = anchorX + leanX * 0.2;
  const shoulderX = anchorX + leanX;
  const headX = anchorX + leanX * 1.12;
  const headTopY = headY + leanY;

  // Far leg, then far arm: both shaded, both behind the torso.
  limb(
    sink,
    hipX - perpX * halfShoulder * 0.4,
    hipY,
    farFootX,
    farFootY,
    legWidth,
    regionColour(spec, "legs"),
    SHADE.away,
  );
  extremity(sink, spec, "feet", farFootX, farFootY, legWidth, SHADE.away);
  drawArm(
    sink,
    spec,
    -nearSign,
    swing,
    dir,
    {
      shoulderX,
      shoulderY,
      perpX,
      perpY,
      halfShoulder,
      armWidth,
      pose,
      zoom,
      metre,
      across,
    },
    SHADE.away,
  );

  // Torso: a trapezoid from hip to shoulder, plus a shaded side quad for volume.
  const hipHalf = halfShoulder * 0.72;
  facet(
    sink,
    [
      [shoulderX - halfShoulder, shoulderY],
      [shoulderX + halfShoulder, shoulderY],
      [hipX + hipHalf, hipY],
      [hipX - hipHalf, hipY],
    ],
    regionColour(spec, "torso"),
    SHADE.near,
  );
  // The lit face: the near half of the chest, catching the same light the wall caps do.
  facet(
    sink,
    [
      [shoulderX + perpX * halfShoulder * nearSign * 0.15, shoulderY],
      [shoulderX + perpX * halfShoulder * nearSign + halfShoulder * 0.1, shoulderY],
      [hipX + perpX * hipHalf * nearSign + hipHalf * 0.1, hipY],
      [hipX + perpX * hipHalf * nearSign * 0.15, hipY],
    ],
    regionColour(spec, "torso"),
    SHADE.cap,
  );

  // Near arm and near leg, unshaded, in front.
  drawArm(sink, spec, nearSign, -swing, dir, {
    shoulderX,
    shoulderY,
    perpX,
    perpY,
    halfShoulder,
    armWidth,
    pose,
    zoom,
    metre,
    across,
  });
  limb(
    sink,
    hipX + perpX * halfShoulder * 0.4,
    hipY,
    nearFootX,
    nearFootY,
    legWidth,
    regionColour(spec, "legs"),
  );
  extremity(sink, spec, "feet", nearFootX, nearFootY, legWidth);

  // The head, last. A disc, with a notch of shade on the back of the skull -- the primary
  // facing cue, and the only one that works on a body standing perfectly still.
  const headR = across(spec.headMetres);
  sink.beginPath();
  sink.ellipse(headX, headTopY, headR, headR * TILE_HEIGHT_RATIO * 0.92, 0, 0, Math.PI * 2);
  sink.fillStyle = regionColour(spec, "head");
  sink.fill();
  sink.beginPath();
  sink.ellipse(
    headX - dir.dx * headR * 0.6,
    headTopY - dir.dy * headR * 0.6,
    headR * 0.72,
    headR * 0.66,
    0,
    0,
    Math.PI * 2,
  );
  sink.fillStyle = SHADE.away;
  sink.fill();
}

type ArmContext = {
  shoulderX: number;
  shoulderY: number;
  perpX: number;
  perpY: number;
  halfShoulder: number;
  armWidth: number;
  pose: Pose;
  zoom: number;
  metre: (m: number) => number;
  across: (m: number) => number;
};

/**
 * One arm.
 *
 * Skipped entirely for a survivor at rest: at 31 px an arm hanging against the torso adds pixels
 * and no information, and the silhouette is cleaner without it. It is drawn whenever it leaves
 * the body's outline -- a zombie reaching, or anybody swinging.
 */
function drawArm(
  sink: ShapeSink,
  spec: BodySpec,
  side: number,
  swing: number,
  dir: { dx: number; dy: number },
  ctx: ArmContext,
  shade?: string,
): void {
  const { shoulderX, shoulderY, perpX, perpY, halfShoulder, armWidth, pose, metre, across } = ctx;
  const rootX = shoulderX + perpX * halfShoulder * side * 0.85;
  const rootY = shoulderY + perpY * halfShoulder * side * 0.85;
  const armLength = metre(spec.heightMetres * 0.36);

  if (pose === Pose.WindUp) {
    // Both arms up and back, weapon cocked. The one frame whose job is to be legible before it
    // lands, so it is the most exaggerated shape in the sheet.
    const backX = rootX - dir.dx * across(0.34);
    const backY = rootY - dir.dy * across(0.34) - armLength * 0.85;
    limb(sink, rootX, rootY, backX, backY, armWidth, regionColour(spec, "arms"), shade);
    extremity(sink, spec, "hands", backX, backY, armWidth, shade);
    return;
  }
  if (pose === Pose.Recover) {
    // Followed through: arms low and across, on the far side of the body from the wind-up.
    const throughX = rootX + dir.dx * across(0.42);
    const throughY = rootY + dir.dy * across(0.42) + armLength * 0.35;
    limb(sink, rootX, rootY, throughX, throughY, armWidth, regionColour(spec, "arms"), shade);
    extremity(sink, spec, "hands", throughX, throughY, armWidth, shade);
    return;
  }
  if (pose === Pose.Staggered) {
    // Flailing: arms out wide, which is what "knocked off balance" looks like from above.
    const outX = rootX + perpX * across(0.34) * side;
    const outY = rootY + perpY * across(0.34) * side - armLength * 0.2;
    limb(sink, rootX, rootY, outX, outY, armWidth, regionColour(spec, "arms"), shade);
    extremity(sink, spec, "hands", outX, outY, armWidth, shade);
    return;
  }

  if (spec.armsForward) {
    // docs/14's shambler, reaching. Ahead and slightly down, swinging a little with the shuffle.
    const reach = across(0.44);
    const handX = rootX + dir.dx * reach;
    const handY = rootY + dir.dy * reach + armLength * (0.28 + swing * 0.12);
    limb(sink, rootX, rootY, handX, handY, armWidth, regionColour(spec, "arms"), shade);
    extremity(sink, spec, "hands", handX, handY, armWidth, shade);
    return;
  }

  // A survivor. Arms swing counter to the legs, and only draw once the swing takes them clear
  // of the torso.
  if (pose === Pose.Idle) return;
  const swingOut = across(spec.strideMetres * 0.55) * swing;
  if (Math.abs(swingOut) < armWidth * 0.6) return;
  limb(
    sink,
    rootX,
    rootY,
    rootX + dir.dx * swingOut,
    rootY + dir.dy * swingOut + armLength,
    armWidth,
    regionColour(spec, "arms"),
    shade,
  );
  extremity(
    sink,
    spec,
    "hands",
    rootX + dir.dx * swingOut,
    rootY + dir.dy * swingOut + armLength,
    armWidth,
    shade,
  );
}

/**
 * A crawler.
 *
 * A distinct shape rather than a scaled-down standing one. docs/14 wants a body with its
 * locomotion destroyed to be "easy to miss in a dark breach" -- half a square is smaller without
 * being harder to spot, whereas a long low shape lying in the diamond genuinely disappears
 * against the ground until you are looking at it, and is unambiguous once you are.
 */
function drawCrawler(
  sink: ShapeSink,
  spec: BodySpec,
  frame: number,
  dir: { dx: number; dy: number },
  zoom: number,
  anchorX: number,
  anchorY: number,
): void {
  const across = (m: number): number => m * zoom;
  const lift = metresToRise(spec.heightMetres * CRAWL_HEIGHT_FRACTION, zoom);
  const half = across(CRAWL_LENGTH_METRES) / 2;
  const width = across(spec.shoulderMetres * 0.8);
  const perpX = -dir.dy;
  const perpY = dir.dx;

  // The drag: the body hauls forward, then the legs follow.
  const pull = frame === 0 ? 0.12 : -0.06;
  const headX = anchorX + dir.dx * half * (1 + pull);
  const headY = anchorY + dir.dy * half * (1 + pull) - lift;
  const tailX = anchorX - dir.dx * half;
  const tailY = anchorY - dir.dy * half * 0.6;

  // Trunk.
  facet(
    sink,
    [
      [headX + perpX * width * 0.35, headY + perpY * width * 0.35],
      [headX - perpX * width * 0.35, headY - perpY * width * 0.35],
      [tailX - perpX * width * 0.22, tailY - perpY * width * 0.22],
      [tailX + perpX * width * 0.22, tailY + perpY * width * 0.22],
    ],
    regionColour(spec, "torso"),
    SHADE.near,
  );

  // The arms it is pulling with, reaching ahead of the head.
  const reachX = headX + dir.dx * across(0.32);
  const reachY = headY + dir.dy * across(0.32);
  const armWidth = across(spec.shoulderMetres * 0.18);
  limb(
    sink,
    headX,
    headY,
    reachX + perpX * width * 0.3,
    reachY + perpY * width * 0.3,
    armWidth,
    regionColour(spec, "arms"),
    SHADE.away,
  );
  extremity(
    sink,
    spec,
    "hands",
    reachX + perpX * width * 0.3,
    reachY + perpY * width * 0.3,
    armWidth,
    SHADE.away,
  );
  limb(
    sink,
    headX,
    headY,
    reachX - perpX * width * 0.3,
    reachY - perpY * width * 0.3,
    armWidth,
    regionColour(spec, "arms"),
  );
  extremity(
    sink,
    spec,
    "hands",
    reachX - perpX * width * 0.3,
    reachY - perpY * width * 0.3,
    armWidth,
  );

  // Head: smaller than standing, because it is close to the ground and mostly foreshortened.
  const headR = across(spec.headMetres * 0.85);
  sink.beginPath();
  sink.ellipse(
    headX,
    headY - headR * 0.3,
    headR,
    headR * TILE_HEIGHT_RATIO * 0.9,
    0,
    0,
    Math.PI * 2,
  );
  sink.fillStyle = regionColour(spec, "head");
  sink.fill();
}

/** Where in the two-beat cycle a frame sits, as a signed swing in [-1, 1]. */
function cycleSwing(pose: Pose, frame: number): number {
  // A crouch shuffles: two frames, and a stride short enough that the feet stay under the hips.
  // Without this the pose would be a held shape and crouch-walking would read as sliding.
  if (pose === Pose.Crouch) return frame % 2 === 0 ? 0.35 : -0.35;
  if (pose !== Pose.Walk && pose !== Pose.Sprint) return 0;
  // 0 and 2 are the passing positions, 1 and 3 the extremes of opposite steps.
  const swing = [0, 1, 0, -1][frame % 4] as number;
  // A sprint reaches further than a walk on the same four frames.
  return pose === Pose.Sprint ? swing * 1.55 : swing;
}

/**
 * The ellipse under a body's feet.
 *
 * See the palette's note: without it a foot-anchored sprite floats, and the eye has no other cue
 * for which tile a body is standing on once the body stops being a mark drawn on that tile.
 */
function groundShadow(
  sink: ShapeSink,
  anchorX: number,
  anchorY: number,
  zoom: number,
  pose: Pose,
): void {
  const rx = SHADOW_RADIUS_METRES * zoom * (pose === Pose.Crawl ? CRAWL_SHADOW_SCALE : 1);
  sink.beginPath();
  sink.ellipse(
    anchorX,
    anchorY,
    rx,
    (rx * TILE_HEIGHT_RATIO) / TILE_WIDTH_RATIO,
    0,
    0,
    Math.PI * 2,
  );
  sink.fillStyle = `rgba(${SHADOW}, ${pose === Pose.Crawl ? 0.28 : 0.38})`;
  sink.fill();
}

/**
 * The anonymous silhouette peripheral vision and memory both use.
 *
 * docs/28-visibility-and-sightlines.md is explicit that the peripheral arc notices movement and
 * withholds *identity*. A real model would hand that identity over by silhouette alone -- you
 * would read the stoop and know it was a shambler, from an arc that is not supposed to tell you
 * that. So this is one shape for all three archetypes, with no posture, no limbs, no head notch,
 * and **no facing**: a body that turns tells you which way it is looking, which the arc did not
 * earn either.
 *
 * Person-sized, because that much is honest. You noticed something the size of a person move.
 */
export function drawSilhouette(
  sink: ShapeSink,
  colour: string,
  zoom: number,
  anchorX: number,
  anchorY: number,
): void {
  const height = metresToRise(1.7, zoom);
  const halfWidth = (0.42 * zoom) / 2;
  const shoulderY = anchorY - height * 0.82;

  groundShadow(sink, anchorX, anchorY, zoom, Pose.Idle);

  facet(
    sink,
    [
      [anchorX - halfWidth * 0.85, shoulderY],
      [anchorX + halfWidth * 0.85, shoulderY],
      [anchorX + halfWidth * 0.55, anchorY],
      [anchorX - halfWidth * 0.55, anchorY],
    ],
    colour,
  );
  const headR = halfWidth * 0.62;
  sink.beginPath();
  sink.ellipse(
    anchorX,
    shoulderY - headR * 0.8,
    headR,
    headR * TILE_HEIGHT_RATIO * 0.92,
    0,
    0,
    Math.PI * 2,
  );
  sink.fillStyle = colour;
  sink.fill();
}
