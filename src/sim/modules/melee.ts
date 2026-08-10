// The melee module.
//
// docs/09-combat.md#the-melee-model, which specifies the loop in one line -- "wind-up ->
// connect or miss -> recovery. All three are interruptible windows, and being caught in
// recovery is how melee kills you."
//
// That sentence is the whole design, and the shape of this file follows from it:
//
//   * A swing is **state that persists across ticks**, not a function call. Pressing the key
//     starts a window; the world keeps moving inside it.
//   * The blow reads position, facing and neighbours **at the moment it lands**, never at the
//     moment the key went down. Turning away mid-wind-up has to be able to miss, or the
//     wind-up is a delay in front of a decision that was already made.
//   * Recovery cannot be cancelled. Everything else can.
//
// What it deliberately does not do: grabs and bite risk, which are the other half of docs/09's
// parity contract. Both need a survivor who can be injured and infected, and neither the
// injury model nor the infection module exists. Until they do, melee's only cost is stamina --
// which means the parity contract is *not* satisfied by this module alone, and saying so here
// is cheaper than rediscovering it during balance work.

import {
  COS_SWING_HALF_ANGLE,
  HEAD_DAMAGE_MULTIPLIER,
  HIT_LOCATION_WEIGHTS,
  MELEE_CONNECT_NOISE,
  recoverTicks,
  swingStamina,
  WEAPONS,
  windupTicks,
  type BodyPart,
  type WeaponProfile,
} from "../combat";
import { defineComponent, Facing, Position } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { RngStream } from "../rng";
import { Body, isAlive, Stamina } from "./health";
import type { Module } from "./index";
import { BODY_RADIUS } from "./movement";
import { Controlled } from "./player";

/**
 * The three windows, as plain numbers.
 *
 * Numbers rather than strings for the reason `ShamblerState` gives: a component is "plain
 * serializable data attached to an entity" (docs/20), and a string costs bytes in every save
 * for no benefit.
 */
export const SwingState = {
  Idle: 0,
  WindUp: 1,
  Recover: 2,
} as const;

export type SwingStateValue = (typeof SwingState)[keyof typeof SwingState];

export type Swing = {
  state: SwingStateValue;
  /** Ticks left in the current window. Zero when idle. */
  ticksLeft: number;
};

export const Swing = defineComponent<Swing>("Swing");

/** What is held. One weapon, no inventory -- docs/10's item system is Milestone 2. */
export type MeleeWeapon = WeaponProfile;

export const MeleeWeapon = defineComponent<MeleeWeapon>("MeleeWeapon");

/** Arm an entity. Mirrors `makeShambler` and `makeEmitter`. */
export function makeMeleeArmed(
  world: World,
  entity: EntityId,
  weapon: WeaponProfile = WEAPONS.bat,
): void {
  world.components.set(entity, MeleeWeapon, { ...weapon });
  world.components.set(entity, Swing, { state: SwingState.Idle, ticksLeft: 0 });
}

/**
 * Where a blow lands, drawn from the seeded stream.
 *
 * Walks {@link HIT_LOCATION_WEIGHTS} in the fixed order `BODY_PARTS` declares rather than in
 * key order, so the roll cannot change meaning because someone reordered an object literal.
 */
function rollBodyPart(rng: RngStream): BodyPart {
  const roll = rng.next();
  let cumulative = 0;
  cumulative += HIT_LOCATION_WEIGHTS.head;
  if (roll < cumulative) return "head";
  cumulative += HIT_LOCATION_WEIGHTS.torso;
  if (roll < cumulative) return "torso";
  return "legs";
}

export const meleeModule: Module = {
  id: "melee",

  register({ world }) {
    const rng = world.rng.stream("melee");
    /** Reused across swings, because a per-swing array is how combat acquires a GC spike. */
    const candidates: EntityId[] = [];

    /**
     * Start a swing, if the survivor is idle, armed, and has the stamina for it.
     *
     * In `input` after the player module (order 0) so a swing and the movement it was pressed
     * with are read from the same tick's commands. It reads `Controlled` -- another module's
     * component, which docs/20 permits reading and forbids writing -- because "who the player
     * is driving" is genuinely the player module's fact, and duplicating it here would be a
     * second answer to it.
     */
    world.systems.register({
      id: "melee.intake",
      phase: "input",
      order: 10,
      run: (w) => {
        if (!w.commands.current.some((c) => c.type === "swing")) return;

        for (const entity of w.components.query(Swing, MeleeWeapon, Controlled)) {
          const swing = w.components.getOrThrow(entity, Swing);
          // Already committed. A second press during a wind-up or a recovery does nothing at
          // all -- no queue, no buffer. docs/09's loop is what you are in, not what you asked
          // for, and an input buffer would let a player pre-pay for a window they have not
          // survived yet.
          if (swing.state !== SwingState.Idle) continue;

          const weapon = w.components.getOrThrow(entity, MeleeWeapon);
          const cost = swingStamina(weapon.weight);
          const stamina = w.components.get(entity, Stamina);
          // Exhaustion stops the swing outright here. docs/09 wants exhausted swings to be
          // "slow, weak, and miss" rather than absent, which needs the modifier pipeline to
          // scale the windows -- that arrives with the stance ladder, which shares this pool.
          if (stamina !== undefined && stamina.current < cost) continue;

          swing.state = SwingState.WindUp;
          swing.ticksLeft = windupTicks(weapon.weight);

          w.events.publish({ type: "stamina.spent", entity, amount: cost });
        }
      },
    });

    /**
     * Advance every open window, and resolve the blow when the wind-up runs out.
     *
     * `query` rather than the cheaper unordered walk, and that is load-bearing: this draws
     * from a seeded stream per connecting swing, so visit order is part of the result. The
     * ordering guarantee is the only thing making two runs of one seed agree.
     */
    world.systems.register({
      id: "melee.resolve",
      phase: "combat",
      run: (w) => {
        for (const entity of w.components.query(Swing, MeleeWeapon, Position, Facing)) {
          const swing = w.components.getOrThrow(entity, Swing);
          if (swing.state === SwingState.Idle) continue;

          // Breaking into a sprint abandons a wind-up -- docs/29's "cannot aim from a
          // sprint", and the same rule read from the other end. The stamina is already gone
          // and is not refunded: that is what makes running away mid-swing a decision.
          //
          // Recovery is untouched by it. Being able to sprint out of a recovery would delete
          // the window docs/09 says is the one that kills you.
          if (swing.state === SwingState.WindUp) {
            const controlled = w.components.get(entity, Controlled);
            if (controlled?.sprinting === true) {
              swing.state = SwingState.Idle;
              swing.ticksLeft = 0;
              continue;
            }
          }

          swing.ticksLeft--;
          if (swing.ticksLeft > 0) continue;

          const weapon = w.components.getOrThrow(entity, MeleeWeapon);
          if (swing.state === SwingState.Recover) {
            swing.state = SwingState.Idle;
            swing.ticksLeft = 0;
            continue;
          }

          resolveStrike(w, entity, weapon, rng, candidates);
          swing.state = SwingState.Recover;
          swing.ticksLeft = recoverTicks(weapon.weight);
        }
      },
    });

    /**
     * Being staggered mid-wind-up loses the swing.
     *
     * Nothing staggers a survivor yet -- zombies have no attack, because grabs are the next
     * change. This is the seam that change plugs into, and it is here now because the rule it
     * encodes is symmetrical: melee staggers zombies out of what they were doing, and the
     * moment anything can stagger back, it has to cost the same thing.
     */
    world.events.subscribe({
      id: "melee.stagger-interrupts",
      type: "entity.staggered",
      handler: (event) => {
        const swing = world.components.get(event.entity, Swing);
        if (swing === undefined || swing.state !== SwingState.WindUp) return;
        swing.state = SwingState.Idle;
        swing.ticksLeft = 0;
      },
    });
  },
};

/**
 * Find what the swing hits, and state what happened.
 *
 * Reach and arc both read the kernel `Facing`, per docs/09#melee-aims-too: "reach and swing
 * arc read from the same facing", which is what makes reach legible as a property rather than
 * a stat on a sheet.
 */
function resolveStrike(
  world: World,
  attacker: EntityId,
  weapon: MeleeWeapon,
  rng: RngStream,
  candidates: EntityId[],
): void {
  const from = world.components.getOrThrow(attacker, Position);
  const facing = world.components.getOrThrow(attacker, Facing).radians;
  const facingX = Math.cos(facing);
  const facingY = Math.sin(facing);

  // Centre-to-centre plus the target's half-width, or a weapon quietly loses that much of
  // the reach its profile claims. The index applies the distance limit itself.
  world.spatial.queryRadius(from.x, from.y, weapon.reachMetres + BODY_RADIUS, candidates);

  let target: EntityId | null = null;
  let nearest = Infinity;

  for (const other of candidates) {
    if (other === attacker) continue;
    const body = world.components.get(other, Body);
    // No body is not a valid target, and neither is one that is already dead -- a corpse is
    // present for one tick after the blow that killed it (see the health module).
    if (body === undefined || !isAlive(body)) continue;

    const there = world.components.get(other, Position);
    if (there === undefined) continue;

    const dx = there.x - from.x;
    const dy = there.y - from.y;
    const distanceSquared = dx * dx + dy * dy;

    if (distanceSquared > 0) {
      // The arc test as a dot product against the heading, the same shape the visibility
      // cone uses: no atan2, no branch on which side of pi the difference landed, and no
      // wrap-around case to get wrong.
      const cosine = (dx * facingX + dy * facingY) / Math.sqrt(distanceSquared);
      if (cosine < COS_SWING_HALF_ANGLE) continue;
    }

    if (distanceSquared < nearest) {
      nearest = distanceSquared;
      target = other;
    }
  }

  // A miss is silent and costs the recovery anyway. docs/03's emitter table prices the
  // *connect*, and a swing that hits nothing has hit nothing to make a noise against.
  if (target === null) return;

  const bodyPart = rollBodyPart(rng);
  const damage = weapon.damage * (bodyPart === "head" ? HEAD_DAMAGE_MULTIPLIER : 1);

  // A fact about the world, not an instruction to the field -- the same route the player
  // module's shout takes, and the reason a trap or a generator reaches the field without
  // knowing it exists.
  world.events.publish({
    type: "noise.emitted",
    x: from.x,
    y: from.y,
    magnitude: MELEE_CONNECT_NOISE,
    source: attacker,
  });

  world.events.publish({ type: "attack.connected", attacker, target, bodyPart, damage });
  world.events.publish({ type: "entity.staggered", entity: target, ticks: weapon.staggerTicks });
}
