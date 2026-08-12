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
// parity contract. **Melee's only cost is still stamina, so the parity contract is still not
// satisfied** -- saying so here is cheaper than rediscovering it during balance work.
//
// What changed, and did not change it: a survivor now has a body that can be hurt in six places
// (docs/05's parts, in `combat.ts`), and a blow that lands on one rolls against that table rather
// than a zombie's three. So half of what grabs were waiting on exists. The other half does not:
// there are no located *injuries* -- no scratch, no laceration, no fracture -- and no infection
// module, which is what a bite has to turn into to be worth being afraid of. A grab that could
// only reduce a number would be the health bar this design refuses.

import {
  BODY_PARTS,
  COS_SWING_HALF_ANGLE,
  HEAD_DAMAGE_MULTIPLIER,
  HIT_LOCATION_WEIGHTS,
  MELEE_CONNECT_NOISE,
  recoverTicks,
  SURVIVOR_BODY_PARTS,
  SURVIVOR_HIT_LOCATION_WEIGHTS,
  swingStamina,
  WEAPONS,
  wielded,
  windupTicks,
  type WeaponProfile,
  type WieldedWeapon,
} from "../combat";
import { defineComponent, Facing, Position } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { RngStream } from "../rng";
import { Body, isAlive, Stamina } from "./health";
import type { Module } from "./index";
import { BODY_RADIUS } from "./movement";
import { meleeProfileOf } from "./items";
import { Controlled } from "./player";
import { capableOf } from "./stance";

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

/**
 * What is held.
 *
 * Derived from the item in the survivor's primary slot when the inventory module is running
 * -- see the `item.equipped` subscriber below -- and set directly by `makeMeleeArmed` when
 * it is not. Both paths produce the same shape, which is what lets melee stay indifferent to
 * whether an inventory exists.
 */
export type MeleeWeapon = WieldedWeapon;

export const MeleeWeapon = defineComponent<MeleeWeapon>("MeleeWeapon");

/** Arm an entity. Mirrors `makeShambler` and `makeEmitter`. */
export function makeMeleeArmed(
  world: World,
  entity: EntityId,
  weapon: WeaponProfile = WEAPONS.bat,
): void {
  world.components.set(entity, MeleeWeapon, wielded(weapon));
  world.components.set(entity, Swing, { state: SwingState.Idle, ticksLeft: 0 });
}

/**
 * Where a blow lands, drawn from the seeded stream.
 *
 * Walks the weights in a **fixed declared order** rather than in key order, so the roll cannot
 * change meaning because someone reordered an object literal -- and so a survivor's six-part
 * table and a zombie's three-part one consume exactly one number from the stream either way.
 * That last property is what keeps the determinism test honest across a change like this: the
 * shape of the distribution moved, the shape of the *stream* did not.
 *
 * Which table applies is a property of the target's body, per docs/05 and docs/14 wanting
 * different vocabularies. A blow that rolls "hands" against a shambler would be discarded by
 * the health module, so the table has to match the thing being hit rather than the thing
 * swinging.
 */
function rollBodyPart(rng: RngStream, body: Body | undefined): string {
  const roll = rng.next();
  const survivor = body !== undefined && body.arms !== undefined;
  const parts: readonly string[] = survivor ? SURVIVOR_BODY_PARTS : BODY_PARTS;
  const weights: Readonly<Record<string, number>> = survivor
    ? SURVIVOR_HIT_LOCATION_WEIGHTS
    : HIT_LOCATION_WEIGHTS;

  let cumulative = 0;
  for (const part of parts) {
    cumulative += weights[part] ?? 0;
    if (roll < cumulative) return part;
  }
  // Floating-point shortfall on the last bucket only. Returning the final part rather than
  // re-rolling keeps the stream consumption at exactly one draw per connect.
  return parts[parts.length - 1] as string;
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

          // You cannot swing from a crawl. docs/29: crawling "costs everything else" -- it is
          // the stance you choose when being unseen is the only thing left that helps, and a
          // crawl that could still swing would be strictly better than a crouch, which is the
          // one thing that document's rule forbids.
          if (!capableOf(w, entity, "canSwing")) continue;

          const weapon = w.components.getOrThrow(entity, MeleeWeapon);
          const cost = swingStamina(weapon.weight, weapon.stamina);
          const stamina = w.components.get(entity, Stamina);
          // Exhaustion stops the swing outright here, and docs/09 wants it to be "slow, weak, and
          // miss" instead. **Still open, and the excuse has expired**: this used to say the
          // scaling needed the stance ladder, which shares this pool -- the ladder has landed, so
          // what remains is a `swing_speed` and `swing_recovery` modifier sourced from how empty
          // the pool is, both stats already registered. It was left out of the ladder's change on
          // purpose rather than forgotten: it is a balance change to the one loop the game has,
          // and it wants its own measurement rather than riding in behind six other things.
          if (stamina !== undefined && stamina.current < cost) continue;

          swing.state = SwingState.WindUp;
          swing.ticksLeft = windupTicks(weapon.weight, weapon.speed);

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
          //
          // It asks the rung rather than a sprint flag now, so it covers the crawl for free:
          // dropping flat mid-wind-up abandons it too, which is the same sentence docs/29
          // writes as "cannot swing or aim" on that row.
          if (swing.state === SwingState.WindUp && !capableOf(w, entity, "canAim")) {
            swing.state = SwingState.Idle;
            swing.ticksLeft = 0;
            continue;
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
          swing.ticksLeft = recoverTicks(weapon.weight, weapon.recovery);
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
    /**
     * What a survivor holds is what is in their primary slot.
     *
     * A subscriber rather than the inventory module writing `MeleeWeapon` directly, because
     * docs/20 says only the owning module writes a component -- and melee owns this one.
     * The inventory module publishes a fact ("this was equipped"); what that means for a
     * swing is melee's business, and neither module imports the other.
     *
     * This is docs/21-extensibility.md's cookbook example 3, and it is what keeps the item
     * system additive: with the inventory module switched off, nothing publishes these
     * events, `makeMeleeArmed` remains the only writer, and the melee loop is exactly what
     * it was before items existed.
     */
    world.events.subscribe({
      id: "melee.equip-weapon",
      type: "item.equipped",
      handler: (event) => {
        if (event.slot !== "primary") return;
        const profile = meleeProfileOf(world, event.item);
        // Equipping a bandage in the primary slot is not an error; it just is not a weapon,
        // and the survivor keeps whatever they had. Bare hands are a separate design
        // question (docs/09) and not one this commit answers.
        if (profile === null) return;
        world.components.set(event.entity, MeleeWeapon, profile);
        // Re-arm the swing window if the survivor was empty-handed. The unequip handler
        // below removes it, and without this a weapon put down and picked back up would
        // never swing again -- the systems query on both components.
        if (!world.components.has(event.entity, Swing)) {
          world.components.set(event.entity, Swing, { state: SwingState.Idle, ticksLeft: 0 });
        }
      },
    });

    world.events.subscribe({
      id: "melee.unequip-weapon",
      type: "item.unequipped",
      handler: (event) => {
        if (event.slot !== "primary") return;
        if (meleeProfileOf(world, event.item) === null) return;
        // Nothing in hand. Removing the component rather than substituting a fist profile,
        // because the swing systems query on `MeleeWeapon` -- so an empty-handed survivor
        // simply does not swing, which is the honest behaviour until docs/09's unarmed
        // option is designed rather than invented here.
        world.components.remove(event.entity, MeleeWeapon);
        world.components.remove(event.entity, Swing);
      },
    });

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

  const bodyPart = rollBodyPart(rng, world.components.get(target, Body));
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
