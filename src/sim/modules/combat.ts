// The combat module.
//
// docs/09-combat.md's melee half. The parity contract it exists to serve is that melee and
// ranged both stay good permanently, by paying different and non-convertible currencies:
// melee spends the present -- stamina, injury, and bite risk -- while ranged spends the
// future. Only the melee side is built here; ranged is Milestone 2.
//
// A module, unlike the attention field it writes into. A world with no combat in it is a
// coherent configuration (docs/17's sandbox presets are exactly this), whereas a world
// where nothing can hear anything is not.
//
// What this module does *not* own is as load-bearing as what it does. It never writes to
// another module's components and never reads them. Three couplings that would otherwise
// have forced it to:
//
//   "a grabbed survivor cannot move"   -> a move_speed modifier, which the player module
//                                         already multiplies into its speed without knowing
//                                         who set it or why (docs/21's mechanism 2).
//   "a crawler is slower"              -> the same, on the zombie.
//   "who is prey"                      -> the kernel's Tags component, not a peek at
//                                         Controlled.
//
// That is the modifier pipeline doing the job docs/21 built it for: weather, injuries and
// grabs all move one number without any of them naming the others.

import { defineComponent, Position, SURVIVOR_TAG, Tags, Velocity } from "../kernel/components";
import { entityIndex, type EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { Module } from "./index";

// ---- content ----------------------------------------------------------------

/** A melee weapon, as resolved from `content/weapons/*.json`. */
export type Weapon = {
  readonly id: string;
  /** Metres. Decides both who connects first and how exposed connecting leaves you. */
  readonly reach: number;
  readonly damage: number;
  /** Kilograms. Drives the stamina a swing costs. */
  readonly weight: number;
  readonly staggerPower: number;
  /** Noise on connect. docs/03's table: a melee connect is 8, blunt louder than blade. */
  readonly noise: number;
  readonly windupTicks: number;
  readonly recoverTicks: number;
};

/**
 * Used only when no content has been loaded at all.
 *
 * `boot()` is used by tests and benchmarks that never touch the disk, so the module has to
 * come up without content -- the same accommodation `makeZombie` makes. What it deliberately
 * does *not* do is cover an unknown id while content *is* loaded: a typo'd weapon should
 * fail loudly rather than silently arm the survivor with their fists, which is the rule
 * docs/20-ecs-and-content.md:153 sets for content errors generally.
 */
const FALLBACK_WEAPON: Weapon = {
  id: "weapon.fists",
  reach: 0.7,
  damage: 4,
  weight: 0,
  staggerPower: 2,
  noise: 3,
  windupTicks: 2,
  recoverTicks: 3,
};

export function weaponFor(world: World, id: string): Weapon {
  if (world.content.count("weapon") === 0) return FALLBACK_WEAPON;
  const entry = world.content.getOrThrow("weapon", id);
  return {
    id,
    reach: entry["reach"] as number,
    damage: entry["damage"] as number,
    weight: entry["weight"] as number,
    staggerPower: entry["staggerPower"] as number,
    noise: entry["noise"] as number,
    windupTicks: entry["windupTicks"] as number,
    recoverTicks: entry["recoverTicks"] as number,
  };
}

// ---- components -------------------------------------------------------------

export type SwingState = "ready" | "windup" | "recover";

/**
 * The swing loop from docs/09: wind-up -> connect or miss -> recovery.
 *
 * All three are interruptible windows, and the middle one is not the dangerous one --
 * "being caught in recovery is how melee kills you". So recovery is real time during which
 * a grab lands, not a cosmetic cooldown.
 */
export type Melee = {
  weaponId: string;
  state: SwingState;
  ticksLeft: number;
  stamina: number;
  staminaMax: number;
  /**
   * Whether the swing currently in flight was started on an empty tank.
   *
   * Recorded at commit time rather than read at resolve time, because docs/09's "exhausted
   * swings are slow, weak, and miss" describes the swing you started, not the state you
   * happen to be in a third of a second later.
   */
  weak: boolean;
};

export const Melee = defineComponent<Melee>("Melee");

/**
 * Located condition, per docs/14's damage model: meaningful damage is to the head or to
 * locomotion. Body damage "slows and staggers but doesn't stop them".
 *
 * Three pools rather than a health bar, because docs/01#4 and docs/05 both rule a health
 * bar out -- and because "destroy the legs and it crawls, and is still lethal" is not
 * expressible in one number.
 */
export type Body = {
  head: number;
  torso: number;
  legs: number;
  /** Locomotion destroyed. A crawler: slow, quiet, easy to miss, still bites. */
  crawling: boolean;
  dead: boolean;
};

export const Body = defineComponent<Body>("Body");

/** Something that grabs. docs/14: the primary threat and the primary bite vector. */
export type Grabber = {
  strength: number;
  holding: EntityId | null;
  /** Ticks until this grabber's next bite attempt. */
  biteIn: number;
};

export const Grabber = defineComponent<Grabber>("Grabber");

/**
 * Held. `by` is a list because docs/09 makes the second grab the whole point: "being
 * grabbed by two at once is usually terminal", and that has to fall out of the arithmetic
 * rather than out of a special case for the number two.
 */
export type Grabbed = {
  by: EntityId[];
  /** Work done toward breaking free. Needs `BREAK_FREE_WORK` per grabber. */
  struggle: number;
};

export const Grabbed = defineComponent<Grabbed>("Grabbed");

/** docs/14 rule 4: they never flinch, only stagger. Physics interrupts them; fear doesn't. */
export type Staggered = { ticksLeft: number };

export const Staggered = defineComponent<Staggered>("Staggered");

// ---- constants --------------------------------------------------------------

/** Reach within which a grabber can take hold, in metres. */
const GRAB_METRES = 0.9;
/** Beyond this, a hold is lost -- the victim has been dragged or pulled free. */
const GRAB_BREAK_METRES = 1.4;

/** Stamina a swing costs: a floor plus the weapon's weight. Heavy is not free. */
const SWING_COST_BASE = 4;
const SWING_COST_PER_KG = 8;
/** Regained per tick when not mid-swing. 0.6 at 20 Hz refills a full bar in about 8 s. */
const STAMINA_REGEN = 0.6;

/** An exhausted swing is slow, weak, and misses. docs/09's three words, in that order. */
const EXHAUSTED_WINDUP_MULTIPLIER = 2;
const EXHAUSTED_DAMAGE_MULTIPLIER = 0.5;
const EXHAUSTED_MISS_CHANCE = 0.4;

/** Ticks of stagger per point of the weapon's stagger power. A bat buys about a second. */
const STAGGER_TICKS_PER_POWER = 1.5;

/** Struggle accrued per tick of trying, and the work one grabber's hold costs to shed. */
const STRUGGLE_PER_TICK = 2.5;
const BREAK_FREE_WORK = 20;
/**
 * Breaking free is physical: it costs stamina, so it competes with swinging -- and it is
 * the number that decides how many of them you can afford to let close. See the reasoning
 * at the struggle itself in `combat.swing`.
 */
const STRUGGLE_STAMINA_PER_TICK = 4;
/** How long the thing you shoved off stays shoved. A second to move, or to swing. */
const BREAK_FREE_STAGGER_TICKS = 20;

/** A held survivor is bitten at on this interval, per grabber. */
const BITE_EVERY_TICKS = 20;
const BITE_CHANCE = 0.25;
const BITE_DAMAGE = 6;

/**
 * Bite risk taken by the attacker on a connect, before reach.
 *
 * docs/09: "every melee connect carries a small chance of taking damage back... Reduced by
 * reach, stagger, armor coverage, and Melee-region web nodes." Armor and the web do not
 * exist yet; reach and stagger do, and they are divided into this rather than subtracted so
 * that reach cannot buy immunity outright.
 */
const CONNECT_RISK = 0.09;
const CONNECT_DAMAGE = 4;

/** Where an unaimed swing lands. The head is the small target, which is why it is the prize. */
const HEAD_SHARE = 0.2;
const TORSO_SHARE = 0.5;

/** How much of its speed a crawler keeps once its legs are gone. */
const CRAWL_SPEED_MULTIPLIER = 0.35;

// ---- construction -----------------------------------------------------------

/** Everything needed to be hit. Read from a zombie type's `body`, or a survivor's default. */
export function makeBody(
  world: World,
  entity: EntityId,
  parts: { head: number; torso: number; legs: number },
): void {
  world.components.set(entity, Body, { ...parts, crawling: false, dead: false });
}

/**
 * Everything needed to swing.
 *
 * The id is stored as asked for and resolved at swing time, not resolved here. `boot`
 * builds the world before content is loaded, so resolving now would quietly hand everyone
 * the fallback and discard the weapon they were given -- which is what it did, and what
 * every reach assertion then measured.
 */
export function makeFighter(world: World, entity: EntityId, weaponId: string): void {
  world.components.set(entity, Melee, {
    weaponId,
    state: "ready",
    ticksLeft: 0,
    stamina: 100,
    staminaMax: 100,
    weak: false,
  });
}

/** Everything needed to take hold of someone. */
export function makeGrabber(world: World, entity: EntityId, strength: number): void {
  world.components.set(entity, Grabber, { strength, holding: null, biteIn: BITE_EVERY_TICKS });
}

// ---- helpers ----------------------------------------------------------------

function distance(world: World, a: EntityId, b: EntityId): number {
  const pa = world.components.get(a, Position);
  const pb = world.components.get(b, Position);
  if (pa === undefined || pb === undefined) return Infinity;
  return Math.hypot(pa.x - pb.x, pa.y - pb.y);
}

function isSurvivor(world: World, entity: EntityId): boolean {
  return world.components.get(entity, Tags)?.values.includes(SURVIVOR_TAG) === true;
}

function swingCost(weapon: Weapon): number {
  return SWING_COST_BASE + weapon.weight * SWING_COST_PER_KG;
}

/** Grab sources are per-grabber, so shedding one hold does not shed the other one's. */
function grabSource(grabber: EntityId): string {
  return `combat.grab.${entityIndex(grabber)}`;
}

function release(world: World, grabber: EntityId, victim: EntityId): void {
  const hold = world.components.get(grabber, Grabber);
  if (hold !== undefined) hold.holding = null;

  world.modifiers.removeBySource(grabSource(grabber), victim);

  const grabbed = world.components.get(victim, Grabbed);
  if (grabbed === undefined) return;
  grabbed.by = grabbed.by.filter((e) => e !== grabber);
  if (grabbed.by.length === 0) world.components.remove(victim, Grabbed);
}

/** Apply damage to one part and publish what happened. Returns true if this was killing. */
function wound(
  world: World,
  target: EntityId,
  part: "head" | "torso" | "legs",
  amount: number,
  attacker: EntityId,
): void {
  const body = world.components.get(target, Body);
  if (body === undefined || body.dead) return;

  body[part] = Math.max(0, body[part] - amount);
  world.events.publish({
    type: "injury.sustained",
    entity: target,
    injury: "wound",
    bodyPart: part,
  });

  // docs/14: "meaningful damage is to the head or to locomotion." Torso damage lands in the
  // pool and does nothing else on purpose -- it is the part of the model that says numbers
  // are not what stops them.
  //
  // For the living it is not the same sentence. That asymmetry is the horror of the thing:
  // a shattered ribcage is fatal to a person and an inconvenience to a corpse, which is why
  // trading hits with one is never an even trade. docs/05's blood loss and pain arrive in
  // Milestone 2 to give the dying some duration; for now it is immediate.
  const fatal =
    (part === "head" && body.head <= 0) ||
    (part === "torso" && body.torso <= 0 && isSurvivor(world, target));

  if (fatal) {
    body.dead = true;
    world.events.publish({ type: "entity.killed", entity: target, killer: attacker });
    if (isSurvivor(world, target)) {
      world.events.publish({ type: "survivor.died", entity: target, cause: "killed" });
    }
    return;
  }

  if (part === "legs" && body.legs <= 0 && !body.crawling) {
    body.crawling = true;
    // Expressed as a modifier rather than by reaching into the zombie module's speed:
    // whoever owns locomotion multiplies this in without knowing a fight caused it.
    world.modifiers.add(
      {
        stat: "move_speed",
        op: "mul",
        value: CRAWL_SPEED_MULTIPLIER,
        source: "combat.crawling",
      },
      target,
    );
  }
}

// ---- the module -------------------------------------------------------------

export const combatModule: Module = {
  id: "combat",

  register({ world }) {
    // The spatial hash's first real customer, and so the thing that has to keep it fresh.
    //
    // Rebuilt here rather than in the kernel because nothing else queries it yet: a world
    // with combat switched off should not pay a linear pass per tick to maintain an index
    // no system reads. When render culling or emitter lookup becomes a second customer this
    // moves up into the kernel, and the reason it moved is that it stopped being combat's.
    world.systems.register({
      id: "combat.rebuild-spatial",
      phase: "combat",
      order: -100,
      run: (w) => w.spatial.rebuild(w),
    });

    // ---- stagger ----------------------------------------------------------
    world.systems.register({
      id: "combat.stagger",
      phase: "combat",
      order: 0,
      run: (w) => {
        for (const entity of w.components.query(Staggered)) {
          const staggered = w.components.getOrThrow(entity, Staggered);
          staggered.ticksLeft--;
          if (staggered.ticksLeft <= 0) {
            w.components.remove(entity, Staggered);
            continue;
          }
          // Interrupted, not merely slowed. A staggered zombie is not grabbing you, which
          // docs/09 calls the actual survival mechanic in a crowd.
          const vel = w.components.get(entity, Velocity);
          if (vel !== undefined) {
            vel.dx = 0;
            vel.dy = 0;
          }
        }
      },
    });

    // ---- the swing loop ---------------------------------------------------
    world.systems.register({
      id: "combat.swing",
      phase: "combat",
      order: 1,
      run: (w) => {
        const attacking = w.commands.taken.some((c) => c.type === "attack");
        const rng = w.rng.stream("combat");

        for (const entity of w.components.query(Position, Melee)) {
          const melee = w.components.getOrThrow(entity, Melee);
          const weapon = weaponFor(w, melee.weaponId);
          const body = w.components.get(entity, Body);
          if (body?.dead === true) continue;

          const grabbed = w.components.get(entity, Grabbed);
          const staggered = w.components.has(entity, Staggered);

          // Interruption. docs/09 makes all three windows interruptible, and this is the
          // one that matters: a swing you committed to is lost, not merely delayed, and the
          // stamina is already spent.
          if ((grabbed !== undefined || staggered) && melee.state === "windup") {
            melee.state = "ready";
            melee.ticksLeft = 0;
          }

          // No recovery while something has hold of you: you are not catching your breath,
          // you are being eaten. This is what makes the arithmetic below terminal rather
          // than merely slow -- with it, a survivor could out-wait any number of them.
          if (
            melee.state === "ready" &&
            grabbed === undefined &&
            melee.stamina < melee.staminaMax
          ) {
            melee.stamina = Math.min(melee.staminaMax, melee.stamina + STAMINA_REGEN);
          }

          if (grabbed !== undefined) {
            // Held: the button struggles instead of swinging. "Cannot move or swing until
            // they break free, which costs stamina and takes time."
            //
            // And it takes stamina you have. An exhausted survivor cannot struggle at all,
            // which is the difference between a hold that is expensive and a hold that is
            // the end -- 20 work per grabber at 2.5 a tick against 4 a tick spent means one
            // costs about a third of a full tank, two cost two thirds, and past three there
            // is not enough in the tank to finish no matter how long you hold the button.
            // docs/09's "one is a skill check, three is a check you fail once", as division.
            if (attacking && isSurvivor(w, entity) && melee.stamina >= STRUGGLE_STAMINA_PER_TICK) {
              grabbed.struggle += STRUGGLE_PER_TICK;
              melee.stamina = Math.max(0, melee.stamina - STRUGGLE_STAMINA_PER_TICK);

              // Two holds cost twice the work to shed, which is the whole of "being
              // grabbed by two at once is usually terminal" -- no special case for two.
              if (grabbed.struggle >= BREAK_FREE_WORK * grabbed.by.length) {
                for (const grabber of [...grabbed.by]) {
                  release(w, grabber, entity);
                  // Shoved off, not merely let go. Without this the hold lands again in
                  // the same tick -- the grab check runs a few lines below this one and
                  // the thing is still standing on top of you -- so breaking free bought
                  // nothing and could not even be observed from outside. The window it
                  // buys is what makes the stamina worth spending.
                  w.components.set(grabber, Staggered, { ticksLeft: BREAK_FREE_STAGGER_TICKS });
                  w.events.publish({ type: "entity.staggered", entity: grabber });
                }
              }
            }
            continue;
          }

          switch (melee.state) {
            case "ready": {
              if (!attacking || staggered || !isSurvivor(w, entity)) break;
              const cost = swingCost(weapon);
              melee.weak = melee.stamina < cost;
              melee.stamina = Math.max(0, melee.stamina - cost);
              melee.state = "windup";
              melee.ticksLeft = melee.weak
                ? weapon.windupTicks * EXHAUSTED_WINDUP_MULTIPLIER
                : weapon.windupTicks;
              break;
            }

            case "windup": {
              melee.ticksLeft--;
              if (melee.ticksLeft > 0) break;
              resolveSwing(w, entity, weapon, melee, rng);
              melee.state = "recover";
              melee.ticksLeft = weapon.recoverTicks;
              break;
            }

            case "recover": {
              melee.ticksLeft--;
              if (melee.ticksLeft <= 0) melee.state = "ready";
              break;
            }
          }
        }
      },
    });

    // ---- grabs ------------------------------------------------------------
    world.systems.register({
      id: "combat.grabs",
      phase: "combat",
      order: 2,
      run: (w) => {
        const rng = w.rng.stream("combat");

        // Driven from the survivors rather than from the horde: there are a handful of the
        // former and thousands of the latter, so this is a few neighbour queries per tick
        // instead of one per zombie.
        for (const victim of w.components.query(Position, Tags)) {
          if (!isSurvivor(w, victim)) continue;
          const body = w.components.get(victim, Body);
          if (body?.dead === true) continue;
          const pos = w.components.getOrThrow(victim, Position);

          for (const grabber of w.spatial.withinRadius(w, pos.x, pos.y, GRAB_BREAK_METRES)) {
            const hold = w.components.get(grabber, Grabber);
            if (hold === undefined) continue;
            if (w.components.get(grabber, Body)?.dead === true) {
              if (hold.holding !== null) release(w, grabber, hold.holding);
              continue;
            }

            const gap = distance(w, grabber, victim);

            if (hold.holding === null) {
              if (gap > GRAB_METRES || w.components.has(grabber, Staggered)) continue;
              hold.holding = victim;
              hold.biteIn = BITE_EVERY_TICKS;

              const grabbed = w.components.get(victim, Grabbed);
              if (grabbed === undefined) {
                w.components.set(victim, Grabbed, { by: [grabber], struggle: 0 });
              } else if (!grabbed.by.includes(grabber)) {
                grabbed.by.push(grabber);
              }

              // Immobilised through the pipeline, so whoever owns this entity's locomotion
              // stops it without ever hearing the word "grab".
              w.modifiers.add(
                { stat: "move_speed", op: "set", value: 0, source: grabSource(grabber) },
                victim,
              );
              w.events.publish({ type: "grab.started", victim, source: grabber });
              continue;
            }

            if (hold.holding !== victim) continue;
            if (gap > GRAB_BREAK_METRES) {
              release(w, grabber, victim);
              continue;
            }

            hold.biteIn--;
            if (hold.biteIn > 0) continue;
            hold.biteIn = BITE_EVERY_TICKS;
            if (rng.next() >= BITE_CHANCE) continue;

            // docs/06 owns what a bite becomes; this milestone owns only that it happened.
            // The infection timeline is Milestone 2, so the event is recorded and stops.
            w.events.publish({ type: "bite.landed", victim, source: grabber, bodyPart: "torso" });
            wound(w, victim, "torso", BITE_DAMAGE, grabber);
          }
        }
      },
    });

    // ---- the dead ---------------------------------------------------------
    world.systems.register({
      id: "combat.clear-dead",
      phase: "cleanup",
      run: (w) => {
        for (const entity of w.components.query(Body)) {
          const body = w.components.getOrThrow(entity, Body);
          if (!body.dead) continue;

          const hold = w.components.get(entity, Grabber);
          if (hold?.holding !== null && hold?.holding !== undefined)
            release(w, entity, hold.holding);

          const grabbed = w.components.get(entity, Grabbed);
          if (grabbed !== undefined) {
            for (const grabber of [...grabbed.by]) release(w, grabber, entity);
          }

          // A survivor's body stays on the map. Succession (docs/01) needs procedurally
          // generated survivors to succeed *into*, which is docs/07 and Milestone 2 -- so
          // this milestone stops at "they died", rather than inventing a placeholder person
          // that the generator would then have to replace.
          if (isSurvivor(w, entity)) continue;
          w.despawn(entity);
        }
      },
    });
  },
};

/**
 * Resolve a swing that has finished winding up.
 *
 * Nearest body within reach, with no arc: a swing connects with the thing in front of you.
 * Facing is not modelled yet and pretending otherwise would be a hit chance in disguise,
 * which docs/09's cut list rejects along with damage numbers.
 */
function resolveSwing(
  world: World,
  attacker: EntityId,
  weapon: Weapon,
  melee: Melee,
  rng: { next: () => number },
): void {
  const pos = world.components.getOrThrow(attacker, Position);

  let target: EntityId | null = null;
  let nearest = Infinity;
  for (const candidate of world.spatial.withinRadius(world, pos.x, pos.y, weapon.reach)) {
    if (candidate === attacker) continue;
    const body = world.components.get(candidate, Body);
    if (body === undefined || body.dead) continue;
    const gap = distance(world, attacker, candidate);
    if (gap < nearest) {
      nearest = gap;
      target = candidate;
    }
  }

  // The miss roll is drawn whether or not anything is in reach, so that swinging at air
  // does not silently shift the RNG sequence relative to swinging at a zombie.
  const missed = melee.weak && rng.next() < EXHAUSTED_MISS_CHANCE;
  if (target === null || missed) return;

  const roll = rng.next();
  const part = roll < HEAD_SHARE ? "head" : roll < HEAD_SHARE + TORSO_SHARE ? "torso" : "legs";
  const damage = melee.weak ? weapon.damage * EXHAUSTED_DAMAGE_MULTIPLIER : weapon.damage;

  world.events.publish({ type: "attack.connected", attacker, target, bodyPart: part });

  // Noise before the wound, so a killing blow is still audible: it is the swing that makes
  // the sound, not the survival of the thing hit. Scaled by noise_emission, which is what
  // the shipped `of the Quiet Hand` affix moves (content/affixes/quiet_hand.json).
  const loudness = weapon.noise * world.modifiers.resolve("noise_emission", attacker);
  if (loudness > 0) {
    world.events.publish({
      type: "noise.emitted",
      x: pos.x,
      y: pos.y,
      magnitude: loudness,
      source: attacker,
    });
  }

  const staggered = world.components.has(target, Staggered);
  wound(world, target, part, damage, attacker);

  if (weapon.staggerPower > 0 && world.components.get(target, Body)?.dead !== true) {
    world.components.set(target, Staggered, {
      ticksLeft: Math.max(1, Math.round(weapon.staggerPower * STAGGER_TICKS_PER_POWER)),
    });
    world.events.publish({ type: "entity.staggered", entity: target });
  }

  // Bite risk back. Reach divides it rather than subtracting from it, so a spear is much
  // safer than fists without ever being free -- and hitting something already staggered is
  // free, which is docs/09's "a staggered zombie isn't grabbing you" stated in damage terms.
  if (staggered) return;
  if (world.components.get(target, Grabber) === undefined) return;
  if (rng.next() >= CONNECT_RISK / weapon.reach) return;

  world.events.publish({ type: "bite.landed", victim: attacker, source: target, bodyPart: "arm" });
  wound(world, attacker, "torso", CONNECT_DAMAGE, target);
}
