// The palette, and the light it implies.
//
// Extracted from renderer.ts when character models landed, for a structural reason rather than a
// tidiness one: `sprites/` draws bodies and `renderer.ts` draws everything else, and both need
// these values. Left where it was, `sprites/* -> renderer.ts -> sprites/*` would be a cycle.
//
// It is a palette and not a theme. docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable
// forbids the readouts a theme would be for, so nothing here is user-facing configuration -- these
// are the colours the district is, and the reason each one is the value it is lives beside it.

export const COLOURS = {
  floor: "#1a1c1f",
  /** The ground, by surface. Paved is `floor` -- it is the baseline the rest read against. */
  dirt: "#282219",
  grass: "#1b2a1b",
  rubble: "#26242a",
  /** A tree: solid and opaque like a wall, and green so it does not read as one. */
  tree: "#2e4a2c",
  wall: "#3b4048",
  /** Transparent: stops a body, not a sightline. Drawn as a gap in the wall it sits in. */
  window: "#2a3f4c",
  /** Screening: stops a sightline, not a body. */
  screen: "#25382a",
  /** Low: stops neither, until somebody crouches. */
  low: "#2c2e33",
  player: "#e8d7a0",
  /**
   * Somebody else's survivor.
   *
   * The player's colour, darkened and slightly desaturated -- deliberately the *same family*
   * rather than a fourth hue. docs/07-survivors.md's survivors are people of exactly the kind
   * the player is, so "human" should read as one colour against the wanderer green, and "not me"
   * should read as a difference in brightness within it. You are the lightest member of your own
   * species, which is a convention nobody has to be taught.
   *
   * Nothing in the simulation carries this component yet -- survivors are Milestone 2. It is here
   * so that the day they spawn they are people rather than green squares.
   */
  survivor: "#b9a97f",
  /** The arc a swing is about to cover. Warm, and brief. */
  swing: "232, 215, 160",
  wanderer: "#6f8f6a",
  /** Peripheral: something moved, and that is all you get. */
  glimpse: "#4a5a48",

  /**
   * A thing lying on the ground, and its outline.
   *
   * Warm and light against the district's greys, because the one job this marker has is to
   * be findable while you walk past. It says "something is here" and nothing about what --
   * see the note on ITEM_MARK_W in renderer.ts.
   */
  groundItem: "#d8c07a",
  groundItemEdge: "#4a3f22",
  /**
   * The paperdoll's line, and the only colour an unhurt body is drawn in.
   *
   * Cool and unsaturated on purpose: it must not compete with any of the four
   * {@link CONDITION_TINTS}, because the whole of what the figure says is *which part is not this
   * colour*. Bright enough to read over the night wash, since the glimpse draws on top of it.
   */
  outline: "#8b93a0",
  /** Last known position, fading. Never moves -- see `remembered`. */
  memory: "#3d4a3c",
  background: "#0d0e10",
  /** Night. Blue rather than black, because a black wash reads as a broken renderer. */
  night: "6, 10, 26",
} as const;

/**
 * The three overlay values that turn a flat colour into a lit surface.
 *
 * Promoted out of `buildOccluderSprites`, where they were literals, so that **a person and a wall
 * are lit by the same imaginary sun**. That agreement is most of what makes a model look like it is
 * standing in the district rather than pasted over it, and it costs nothing: shading stays an
 * overlay on the base colour, so a new occluder class or a new archetype needs one palette entry
 * rather than three.
 *
 * The direction is fixed by the camera: the south-east face catches more light than the south-west
 * one, and the other two faces are never visible at all -- the one economy a fixed camera angle
 * buys for free.
 */
export const SHADE = {
  /** South-west: the face turned furthest from the light. */
  away: "rgba(0, 0, 0, 0.34)",
  /** South-east: angled into it. */
  near: "rgba(0, 0, 0, 0.16)",
  /** The top, catching it square. */
  cap: "rgba(255, 255, 255, 0.10)",
} as const;

/**
 * The four tints a body part reads in on the [condition view](../../docs/05-health-injury.md).
 *
 * **Colour, never fill** -- that is docs/05's own heading, and this array is the whole of what it
 * permits. Four entries because four is how many distinctions the prose supports, and there is no
 * fifth for "89%" because there is no percentage anywhere in this feature to have one.
 *
 * Indexed by `PartState`, so the order is the ordering: unhurt, hurt, badly hurt, unusable.
 *
 * Chosen to survive two things. The first is the night wash, which takes 80% of the frame -- so the
 * hurt states are *brighter* than unhurt rather than merely different, and a bad limb draws
 * attention by being lighter in a dark picture. The second is colour blindness: the three hurt
 * states differ in **lightness** as well as hue, so the reading survives losing the red-green axis.
 * Unusable is the darkest thing on the body, which reads as absence rather than as damage.
 */
export const CONDITION_TINTS: readonly string[] = [
  /** Unhurt: the body's own colour, so an unhurt survivor is not a coloured diagram. */
  "#c9c4b8",
  /** Hurt: warm and slightly brighter. Something happened here. */
  "#d9a253",
  /** Badly hurt: brighter still, and unmistakably wrong. */
  "#c9564a",
  /** Unusable: gone dark. Not a colour a working limb ever is. */
  "#4a3b3a",
];

/**
 * The contact shadow under a standing body, as an rgb triple.
 *
 * Not decoration. A foot-anchored sprite with nothing under it *floats*, and floating is the
 * characteristic failure of standing sprites over an isometric ground -- the eye has no other cue
 * for which tile a body is on once the body stops being a mark drawn on that tile.
 */
export const SHADOW = "0, 0, 0";
