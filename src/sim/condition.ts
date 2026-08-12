// The condition view's read model.
//
// docs/05-health-injury.md#the-condition-view, and that section opens by saying why it exists:
// "this is where the design is most likely to be talked into a health bar, so the rules are
// written down here rather than left to the UI work." This file is those rules, in the one place
// both readouts go through.
//
// Three properties, and each one is load-bearing:
//
//   1. **It is a snapshot, not the world.** Same rule as `inventoryView` -- `ui/` and `render/`
//      cannot reach into components if what they are handed is plain data (docs/19#layers), and
//      it is the shape a networked client would receive with nothing left to filter.
//
//   2. **No integrity number crosses this boundary.** Not "hidden", not "available if needed":
//      a `PartState` and a sentence, and nothing a fill percentage could be computed from.
//      docs/01's clause 4 bans "any UI that would collapse this uncertainty into a number", and
//      the cheapest way to keep a bar out of a screen is to make the screen unable to draw one.
//      `condition.test.ts` asserts the absence, so the ban is mechanical rather than a comment.
//
//   3. **The prose is the readout, and it can be wrong.** docs/05: "the paperdoll does not know
//      something the examiner doesn't. It is a layout for uncertainty, not a resolution of it."
//
// Milestone 1 adds only the located bite/scratch presentation needed by grab risk. The wider injury
// vocabulary, four continuous conditions, diagnosis tiers, and treatment remain docs/05's
// Milestone 2 half.

import { SURVIVOR_BODY_PARTS, type SurvivorBodyPart } from "./combat";
import type { EntityId } from "./kernel/entities";
import type { World } from "./kernel/world";
import { Body, Injuries, PartState, partState, type InjuryKind } from "./modules/health";
import { Posture } from "./modules/stance";
import { DEFAULT_STANCE, type Stance } from "./stances";

/** One part of one body, as the screen is allowed to know it. */
export type PartView = {
  readonly part: SurvivorBodyPart;
  readonly state: PartState;
  /**
   * What a examiner would say about it, in words.
   *
   * **Prose rather than a number, and prose is strictly more information than a bar** -- that is
   * docs/05's argument rather than a consolation: a bar answers *how much is left*, and this
   * answers *what is wrong and where*, which is the question the design has always wanted the
   * player to be asking.
   */
  readonly prose: string;
};

export type ConditionView = {
  readonly entity: EntityId;
  readonly parts: readonly PartView[];
  /** The rung the body is on, so the paperdoll stands the way the survivor stands. */
  readonly stance: Stance;
  /** True while a stance change is under way, for a readout that wants to say "getting up". */
  readonly changingStance: boolean;
  /**
   * The worst state on the body.
   *
   * Precomputed because both tiers want it and neither should re-derive it: the glimpse uses it
   * to decide whether it is worth drawing attention to at all, and a `max` taken twice is two
   * places for the answer to differ.
   */
  readonly worst: PartState;
};

/**
 * How each part reads at each state, as the prose docs/05 asks for.
 *
 * **One voice, and the code says which.** docs/05 scales this by the examiner's Medicine skill --
 * an untrained survivor gets "there's a lot of blood, he doesn't look good" where a skilled one
 * gets "deep laceration, sutured and clean, off work five days". There is no
 * [skill web](../../docs/08-skill-web.md) yet, so there is nothing to scale against, and
 * inventing a scale now would be inventing the skill system in a string table.
 *
 * What ships is the **untrained** tier: plain, unspecific, and about how someone *looks* rather
 * than what is wrong with them. That is the honest placeholder rather than a neutral one -- when
 * the web lands, this table gains a tier rather than being rewritten, because the untrained
 * column is one it needed anyway.
 *
 * Per part rather than one set of four strings, because docs/05's whole point is that *which
 * limb* determines what it costs you. "It hurts to hold anything" and "he is limping badly" are
 * the same state on two parts, and collapsing them would throw away the located-ness that makes
 * this a body map rather than four adjectives.
 */
const PROSE: Readonly<Record<SurvivorBodyPart, readonly [string, string, string, string]>> = {
  head: [
    "clear-eyed",
    "a cut on the scalp, bleeding into one eye",
    "concussed -- slow to answer, and the words come out wrong",
    "unresponsive",
  ],
  torso: [
    "breathing easily",
    "bruised across the ribs, and short of breath for it",
    "bleeding through whatever is over it, and grey with it",
    "barely holding on",
  ],
  arms: [
    "steady",
    "a bad cut on one forearm; the grip is weaker than it was",
    "one arm hangs wrong and will not take weight",
    "no use at all",
  ],
  hands: [
    "steady enough for fine work",
    "torn up, and clumsy with it",
    "two fingers are the wrong shape",
    "cannot hold anything",
  ],
  legs: [
    "walking easily",
    "favouring one leg",
    "limping badly, and slow -- and loud with it",
    "not standing up unaided",
  ],
  feet: [
    "sound",
    "blistered raw, and every step lands hard",
    "something is broken in there; the limp is loud",
    "will not bear weight",
  ],
};

/**
 * Untrained wound observations. These describe presentation, never private simulation truth.
 * In particular, a transmitted bite presented as a scratch takes the `scratch` sentence.
 */
const WOUND_PROSE: Readonly<Record<InjuryKind, string>> = {
  scratch: "a ragged scratch; too soon to know whether it is only that",
  laceration: "a deep tear that will not close on its own",
  "deep-wound": "a deep wound, open and bleeding badly",
  bite: "clear teeth marks in torn flesh",
  fracture: "something underneath is broken",
  sprain: "swollen and reluctant to take weight",
  burn: "badly burned skin",
  concussion: "dazed, slow to focus, and unsteady",
};

/**
 * What the screen may know about one survivor.
 *
 * Returns `null` for a body with no survivor parts -- a shambler, which has three parts and no
 * condition view, because docs/05 is a document about people. Callers draw nothing rather than
 * drawing a body with three quarters of it missing.
 */
export function conditionView(world: World, entity: EntityId): ConditionView | null {
  const body = world.components.get(entity, Body);
  if (body === undefined || body.arms === undefined) return null;

  const parts: PartView[] = [];
  let worst = PartState.Unhurt;
  const injuries = world.components.get(entity, Injuries)?.wounds ?? [];

  // In `SURVIVOR_BODY_PARTS` order, which is head-down. The paperdoll reads it as a layout, so
  // the order is part of the answer rather than an implementation detail -- and it is fixed, so
  // two readouts cannot list the same body differently.
  for (const part of SURVIVOR_BODY_PARTS) {
    const state = partState(body, part);
    if (state === undefined) continue;
    let prose = PROSE[part][state];
    // Latest presentation wins until treatment supplies a richer diagnosis in Milestone 2.
    for (let i = injuries.length - 1; i >= 0; i--) {
      const wound = injuries[i];
      if (wound?.bodyPart !== part) continue;
      prose = WOUND_PROSE[wound.presentation];
      break;
    }
    parts.push({ part, state, prose });
    if (state > worst) worst = state;
  }

  const posture = world.components.get(entity, Posture);
  return {
    entity,
    parts,
    stance: posture?.current ?? DEFAULT_STANCE,
    changingStance: posture !== undefined && posture.current !== posture.target,
    worst,
  };
}
