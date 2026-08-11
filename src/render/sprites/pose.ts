// What pose a body is in, and which way it is facing.
//
// Every decision here is arithmetic rather than drawing, which is the whole reason the file
// exists: Vitest runs in node, there is no canvas, and `renderer.ts` has no test for that
// reason. Splitting the choices out from the shapes is what makes the choices provable --
// the precedence order below is a design commitment, and a design commitment with no test on
// it is a comment.
//
// **This module imports nothing.** Not from `sim/`, not from `render/`. The swing state
// arrives as a bare number rather than as `SwingState` so that a test can exercise the whole
// precedence table without constructing a world, and so that nothing here can drift into
// depending on the simulation it is only allowed to read.

/**
 * Who a body is, for drawing purposes only.
 *
 * A presentation classification, not a simulation one -- see `archetypeFor`. The three differ
 * by posture first and colour second, because at the size a body draws (roughly 31 px at the
 * shipped zoom) posture is what survives the night wash and colour is not.
 */
export const enum Archetype {
  Player = 0,
  /** Somebody else's survivor. Nothing carries this yet; survivors are Milestone 2. */
  Survivor = 1,
  Zombie = 2,
}

export const ARCHETYPES: readonly Archetype[] = [
  Archetype.Player,
  Archetype.Survivor,
  Archetype.Zombie,
];

/**
 * What a body is doing, as the drawing understands it.
 *
 * Deliberately not a mirror of any one simulation enum. It is the join of several -- locomotion
 * speed, `SwingState`, `ShamblerState.Staggered`, and `isCrawling` -- collapsed into the single
 * question the atlas needs answered. The collapse is `selectPose`, and its order is the
 * interesting part.
 *
 * docs/29-movement-and-stances.md's five stances (crawl, crouch, walk, jog, sprint) are the
 * obvious next occupants. When a `Stance` component lands it becomes another input to
 * `selectPose` and more entries here; nothing in the draw path moves.
 */
export const enum Pose {
  Idle = 0,
  Walk = 1,
  Sprint = 2,
  WindUp = 3,
  Recover = 4,
  Staggered = 5,
  Crawl = 6,
}

export const POSES: readonly Pose[] = [
  Pose.Idle,
  Pose.Walk,
  Pose.Sprint,
  Pose.WindUp,
  Pose.Recover,
  Pose.Staggered,
  Pose.Crawl,
];

/**
 * Frames in each pose's cycle, indexed by {@link Pose}.
 *
 * Only the cyclic poses have more than one. A stagger is a single held shape because it is over
 * in a handful of ticks and an animation nobody can finish watching is just a shimmer; a
 * wind-up and a recovery are single shapes because the *wedge* on the ground already carries
 * their progress (docs/09-combat.md's cut list makes that wedge the readout), and a second
 * animated channel for the same fact would be the thing being displayed twice that
 * TODO.md warns against.
 */
export const POSE_FRAMES: readonly number[] = [
  1, // Idle
  4, // Walk
  4, // Sprint
  1, // WindUp
  1, // Recover
  1, // Staggered
  2, // Crawl
];

/** Total frames one archetype's sheet holds, across every pose. */
export const FRAMES_PER_ARCHETYPE = POSE_FRAMES.reduce((sum, n) => sum + n, 0);

/** Row a pose's first frame occupies on the sheet. */
export const POSE_ROW: readonly number[] = POSE_FRAMES.reduce<number[]>((rows, _frames, pose) => {
  rows.push(pose === 0 ? 0 : (rows[pose - 1] as number) + (POSE_FRAMES[pose - 1] as number));
  return rows;
}, []);

/**
 * How many directions a body is drawn in.
 *
 * Eight, and not sixteen. The projection compresses the north-south axis by half, so the
 * difference between two 22.5-degree-apart headings is a couple of pixels of shoulder at the
 * size these draw -- sixteen would double the sheet to buy something nobody can see.
 */
export const OCTANTS = 8;

/** Radians one octant spans. */
const OCTANT_RADIANS = (Math.PI * 2) / OCTANTS;

/**
 * A heading as one of eight sectors. 0 is +x, increasing the way `Facing` increases.
 *
 * Rounds rather than floors, so each octant is *centred* on its cardinal or diagonal heading
 * instead of starting at it. Facing due east should draw the east sprite, not the sprite for
 * the sector that begins at east -- the floored version is off by half a sector everywhere and
 * reads as a body that never quite looks where it is going.
 *
 * Total over all reals, including the negative zero `Math.atan2` can produce for a due-east
 * heading (`Facing`'s doc warns about it specifically) and both ends of the +/-pi wrap.
 */
export function octantOf(radians: number): number {
  if (!Number.isFinite(radians)) return 0;
  const octant = Math.round(radians / OCTANT_RADIANS) % OCTANTS;
  // `%` keeps the sign of the dividend, so a negative heading lands in [-7, 0]. The `+ 0`
  // collapses the negative zero that a due-east heading reaches -- `Facing`'s doc warns about
  // it, `canonicalize` rejects it outright, and an index of -0 would silently miss a Map key.
  return (octant < 0 ? octant + OCTANTS : octant) + 0;
}

/**
 * Everything the pose depends on, as plain numbers.
 *
 * Sim-shaped but not sim-typed: `swing` is `SwingState`'s value passed as a number. See the
 * header for why this module refuses the import.
 */
export type PoseInput = {
  /** Metres per second, from `Velocity`. Not from the frame delta -- see `selectPose`. */
  speedMetresPerSecond: number;
  /** `isCrawling(Body)`: locomotion is destroyed. */
  crawling: boolean;
  /** `ShamblerState.Staggered`: knocked off balance. */
  staggered: boolean;
  /** `SwingState`: 0 idle, 1 winding up, 2 recovering. */
  swing: number;
  /** Above this speed the body is sprinting. `SPRINT_THRESHOLD`, passed in. */
  sprintThreshold: number;
  /** Walk-cycle phase, in [0, 1). See {@link advancePhase}. */
  phase: number;
};

/** `SwingState`, restated as the numbers this module is handed. */
const SWING_IDLE = 0;
const SWING_WINDUP = 1;

/**
 * The pose a body is in, and which frame of it.
 *
 * **The precedence order is the design, not a convenience.** Each rung outranks the next for a
 * reason the simulation already commits to:
 *
 *  1. **Crawling** wins outright. It is a fact about the body rather than about what the body is
 *     doing -- `isCrawling` is true in *every* shambler state (shambler.ts treats it as an
 *     orthogonal modifier), and docs/29-movement-and-stances.md says you cannot swing from a
 *     crawl. So no swing pose may outrank it, or the picture would claim an attack the
 *     simulation will not deliver.
 *  2. **Staggered** next. shambler.ts: stagger "is the *only* thing that interrupts this state
 *     machine". The drawing interrupts for exactly the same one thing and nothing else, which is
 *     what stops the screen and the simulation disagreeing about whether a body is currently
 *     harmless -- docs/09-combat.md calls stagger "the actual survival mechanic in a crowd".
 *  3. **A committed swing** outranks locomotion, because the commitment *is* the mechanic: you
 *     are locked in whether or not your feet are still moving, and docs/09's cut list makes that
 *     lock the only readout there is.
 *  4. Then **sprint**, **walk**, **idle**, by speed.
 *
 * Speed comes from `Velocity` rather than from the distance moved between frames, because the
 * frame delta is interpolation: it reads zero on a tick boundary and would flicker a walking
 * body to idle sixty times a second.
 */
export function selectPose(input: PoseInput): { pose: Pose; frame: number } {
  const pose = poseOf(input);
  return { pose, frame: frameOf(pose, input.phase) };
}

function poseOf(input: PoseInput): Pose {
  if (input.crawling) return Pose.Crawl;
  if (input.staggered) return Pose.Staggered;
  if (input.swing !== SWING_IDLE) {
    return input.swing === SWING_WINDUP ? Pose.WindUp : Pose.Recover;
  }
  if (input.speedMetresPerSecond >= input.sprintThreshold) return Pose.Sprint;
  if (input.speedMetresPerSecond > 0) return Pose.Walk;
  return Pose.Idle;
}

/**
 * Which frame of a pose a phase lands on.
 *
 * Clamped at the top rather than wrapped, so a phase of exactly 1 -- which floating-point
 * accumulation can reach even though {@link advancePhase} works modulo 1 -- returns the last
 * frame instead of an index off the end of the row.
 */
export function frameOf(pose: Pose, phase: number): number {
  const frames = POSE_FRAMES[pose] as number;
  if (frames <= 1 || !Number.isFinite(phase)) return 0;
  const frame = Math.floor(phase * frames);
  return frame < 0 ? 0 : frame > frames - 1 ? frames - 1 : frame;
}

/**
 * Metres of ground one full walk cycle covers.
 *
 * A stride is about 0.75 m and the four-frame cycle is two of them. It is the one number that
 * decides whether the feet skate, and it is in *metres* rather than seconds on purpose -- see
 * {@link advancePhase}.
 */
export const STRIDE_METRES = 1.5;

/** A crawl covers far less ground per cycle, because it is dragging rather than stepping. */
export const CRAWL_STRIDE_METRES = 0.6;

/**
 * Advance the walk cycle by a distance travelled.
 *
 * **By distance, never by a clock.** This is what makes the cycle correct rather than
 * approximately correct: a body moving at a third of walk speed advances the phase at a third
 * of the rate because it covered a third of the ground, and no code anywhere has to know what
 * speed it is going. Sprinting reads as faster because it *is* faster. Feet cannot skate,
 * because skating is precisely the disagreement between a time-driven cycle and a
 * distance-driven body.
 *
 * It also makes a paused game right for free. `main.ts` redraws with `alpha = 0` while paused;
 * a stopped body covers no ground, so the pose holds instead of running an idle animation over
 * a world that is not moving.
 *
 * Non-cyclic poses keep their phase rather than resetting it, so a body that staggers mid-stride
 * resumes the cycle where it left off instead of snapping to the start.
 */
export function advancePhase(phase: number, metresTravelled: number, pose: Pose): number {
  if ((POSE_FRAMES[pose] as number) <= 1) return phase;
  if (!(metresTravelled > 0) || !Number.isFinite(metresTravelled)) return phase;
  const stride = pose === Pose.Crawl ? CRAWL_STRIDE_METRES : STRIDE_METRES;
  const next = (phase + metresTravelled / stride) % 1;
  // Guards against a non-finite phase arriving from a corrupted caller, and against the -0
  // that `%` yields for a negative dividend.
  return Number.isFinite(next) && next >= 0 ? next : 0;
}
