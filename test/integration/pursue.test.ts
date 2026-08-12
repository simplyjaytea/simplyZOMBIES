// Pursuit on direct contact.
//
// docs/14-zombies.md rule 4: zombies "pursue on direct contact, without pathfinding cleverness --
// they'll grind against a wall between them and you". This is the **first stimulus that persists**:
// noise commits for twenty seconds and then fades, scent and light end the tick they stop being
// sensed, and contact holds until the survivor gets clear. So most of what is worth asserting here
// is what pursuit must *not* become -- a search, a memory, or a route.
//
// The other reason this file is mostly negative controls: contact is the one stimulus that does not
// need to be sensed at all, so it must keep working in the dark and without eyes, and must not be
// breakable by going quiet.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Position, Velocity } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { applySave, createSave } from "../../src/sim/kernel/save";
import { step, stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import {
  defaultShamblerSpeeds,
  Shambler,
  ShamblerState,
  SHAMBLER_TUNING,
} from "../../src/sim/modules/shambler";
import { Tile } from "../../src/sim/map/tilemap";

const SEED = 606060;
/** Deep in the night phase, so "does darkness break it" is a real question. */
const NIGHT = 0.8;

/**
 * A district with one shambler placed at a chosen distance from the survivor.
 *
 * On the shipped boot path, so the state machine under test is the one the game runs. `attention`
 * and `field-memory` are off: the survivor emits scent permanently, and a shambler drifting up that
 * gradient would confound every heading measured here.
 */
function standoff(metres: number, options: { disabled?: string[]; wall?: boolean } = {}) {
  const { world, map, player } = boot({
    seed: SEED,
    wanderers: 0,
    mapSize: 96,
    startTimeOfDay: NIGHT,
    disabled: ["attention", "field-memory", ...(options.disabled ?? [])],
  });
  const survivor = player as EntityId;
  const here = world.components.getOrThrow(survivor, Position);

  const zombie = world.spawn();
  world.components.set(zombie, Position, { x: here.x + metres, y: here.y });
  // Walking due north, so any turn toward the survivor (due west of it) is a change.
  world.components.set(zombie, Velocity, { dx: 0, dy: -0.5 });
  world.components.set(zombie, Shambler, {
    ...defaultShamblerSpeeds(),
    state: ShamblerState.Wander,
    // Long enough that the random re-aim never fires inside a test.
    ticksToTurn: 100000,
    ticksCommitted: 0,
    ticksMilling: 0,
    ticksStaggered: 0,
    bias: 0,
  });

  if (options.wall === true) {
    // A full-height wall between the two, so there is genuinely no way round within reach.
    const column = Math.floor(here.x) + 1;
    for (let ty = 0; ty < map.h; ty++) map.tiles[ty * map.w + column] = Tile.Wall;
    world.invalidateMap();
  }

  return { world, map, zombie, survivor };
}

function stateOf(world: World, zombie: EntityId): number {
  return world.components.getOrThrow(zombie, Shambler).state;
}

/** Distance from the zombie to the survivor, in metres. */
function gap(world: World, zombie: EntityId, survivor: EntityId): number {
  const a = world.components.getOrThrow(zombie, Position);
  const b = world.components.getOrThrow(survivor, Position);
  return Math.hypot(a.x - b.x, a.y - b.y);
}

describe("contact starts it", () => {
  it("takes hold on the first tick a survivor is within reach", () => {
    const { world, zombie } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Wander);

    step(world);

    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
  });

  it("leaves a shambler alone at arm's length plus a bit", () => {
    // The negative control on the radius itself: just outside contact is not contact.
    const { world, zombie } = standoff(SHAMBLER_TUNING.releaseMetres * 1.5);
    stepN(world, 20);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Wander);
  });

  it("closes the distance once it has hold", () => {
    const { world, zombie, survivor } = standoff(SHAMBLER_TUNING.contactMetres * 0.9);
    const before = gap(world, zombie, survivor);
    stepN(world, 20);
    expect(gap(world, zombie, survivor)).toBeLessThan(before);
  });
});

describe("what pursuit must not become", () => {
  it("does not path around a wall -- it grinds against it", () => {
    // docs/14 rule 4's sentence, asserted. A full-height wall stands between the two, so the only
    // way to reach the survivor is around it -- and it must not find one.
    const { world, zombie } = standoff(SHAMBLER_TUNING.contactMetres * 0.9, { wall: true });
    step(world);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);

    const start = { ...world.components.getOrThrow(zombie, Position) };
    stepN(world, 200);
    const end = world.components.getOrThrow(zombie, Position);

    // It pressed *at* the survivor -- westward, into the wall -- and got stuck there.
    expect(end.x).toBeLessThanOrEqual(start.x);
    // And it did not go around: ten seconds of walking has not moved it appreciably along the
    // wall, because nothing ever steers it anywhere but straight at the target.
    expect(Math.abs(end.y - start.y)).toBeLessThan(1);
    // Still held, and still on the far side.
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
  });

  it("lets go when the survivor gets clear, and forgets them", () => {
    // MUTATION CHECK: delete the release test in the Pursue branch and this never returns to
    // Wander -- pursuit becomes a one-way latch, which is the literal reading of "indefinitely"
    // that docs/14 was corrected away from.
    const { world, zombie, survivor } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    step(world);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);

    // Teleport the survivor well clear, the way running away eventually does.
    const at = world.components.getOrThrow(survivor, Position);
    at.x += SHAMBLER_TUNING.releaseMetres * 6;
    step(world);

    expect(stateOf(world, zombie)).toBe(ShamblerState.Wander);
    // And it does not head after them: no last-known position, so no search.
    const heading = world.components.getOrThrow(zombie, Velocity);
    stepN(world, 20);
    const later = world.components.getOrThrow(zombie, Velocity);
    expect(Math.atan2(later.dy, later.dx)).toBeCloseTo(Math.atan2(heading.dy, heading.dx), 6);
  });

  it("does not let go of a survivor dancing across the contact edge", () => {
    // The reason there are two radii rather than one, and it has to be tested by *crossing* the
    // edge rather than sitting on it. The first version of this parked a body at exactly
    // `contactMetres` with its velocity pinned, and passed with `RELEASE_METRES` set equal to
    // `CONTACT_METRES` -- because a distance that never changes cannot oscillate. Mutation caught
    // it.
    //
    // MUTATION CHECK: set `RELEASE_METRES` to `CONTACT_METRES` and this fails. A survivor stepping
    // an inch beyond arm's reach and back would shake a zombie off every other tick.
    const { world, zombie, survivor } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    step(world);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);

    const at = world.components.getOrThrow(survivor, Position);
    const held = world.components.getOrThrow(zombie, Position);
    const inside = SHAMBLER_TUNING.contactMetres * 0.9;
    // Just outside contact, and comfortably inside release: the gap itself.
    const outside = (SHAMBLER_TUNING.contactMetres + SHAMBLER_TUNING.releaseMetres) / 2;

    let changes = 0;
    let previous = stateOf(world, zombie);
    for (let i = 0; i < 60; i++) {
      // Re-place the survivor each tick, alternating either side of the contact edge, and hold the
      // zombie still so only the survivor's position decides.
      const distance = i % 2 === 0 ? outside : inside;
      at.x = held.x - distance;
      at.y = held.y;
      step(world);
      at.x = held.x - distance;
      at.y = held.y;
      const now = stateOf(world, zombie);
      if (now !== previous) changes++;
      previous = now;
    }

    expect(changes).toBe(0);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
  });

  it("stops pursuing while staggered, because that is what a stagger buys", () => {
    // docs/09-combat.md: "Stagger is the actual survival mechanic in a crowd, because a staggered
    // zombie isn't grabbing you." Pursuit is persistent and stagger is the only interrupt, so this
    // is the one place the two have to be checked against each other.
    //
    // MUTATION CHECK: add a contact test to the `Staggered` branch and this fails. Nothing else in
    // the suite catches it -- 46 tests across stagger, swing, melee and pursue all passed with a
    // staggered zombie grabbing, which is why this test exists.
    const { world, zombie } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    step(world);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);

    world.events.publish({ type: "entity.staggered", entity: zombie, ticks: 40 });
    world.events.drain();
    step(world);

    expect(stateOf(world, zombie)).toBe(ShamblerState.Staggered);
    // And it is not moving, however close the survivor is.
    const vel = world.components.getOrThrow(zombie, Velocity);
    expect(Math.hypot(vel.dx, vel.dy)).toBe(0);

    // It comes back to pursuit once the stagger runs out, because the survivor never left.
    stepN(world, 60);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
  });
});

describe("contact is distance, so nothing sensory can break it", () => {
  it("holds in the dark", () => {
    const { world, zombie } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    stepN(world, 40);
    // Night, with no emitters anywhere, and it still has hold.
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
  });

  it("holds for a shambler with no eyes at all", () => {
    // `boot({ observers: 0 })` is the default, so this zombie has no `Observer`. Sight is not what
    // contact is made of.
    const { world, zombie } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    stepN(world, 40);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
  });

  it("holds while the survivor stands perfectly still and silent", () => {
    // The decision docs/14 was corrected on. Its rule 4 said both "indefinitely" and "for as long
    // as you're audible"; those are different mechanics, and this asserts the one chosen. A zombie
    // with its hands on you has not been *hearing* you for a while.
    const { world, zombie } = standoff(SHAMBLER_TUNING.contactMetres * 0.5);
    step(world);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);

    // No commands at all: no movement, no shout, nothing emitted.
    stepN(world, 200);
    expect(stateOf(world, zombie)).toBe(ShamblerState.Pursue);
    expect(world.field.liveCells()).toBe(0);
  });
});

describe("the Milestone 1 exit criterion still means what it says", () => {
  it("puts nobody in Pursue in a quiet district with nobody near the survivor", () => {
    // Contact cannot make silence meaningless, because it requires the zombie to already be next to
    // you. If this ever fails, the contact radius has grown into a sensing range.
    const { world } = boot({
      seed: SEED,
      wanderers: 200,
      mapSize: 128,
      startTimeOfDay: NIGHT,
    });
    stepN(world, 200);

    let pursuing = 0;
    for (const entity of world.components.query(Shambler)) {
      if (world.components.getOrThrow(entity, Shambler).state === ShamblerState.Pursue) pursuing++;
    }
    // Two hundred bodies drifting at random across a 128 m district will occasionally brush the
    // survivor, which is correct -- what must not happen is a crowd of them arriving.
    expect(pursuing).toBeLessThan(4);
  });
});

describe("pursuit survives a save", () => {
  it("reproduces byte-identically across a fresh boot and a load", () => {
    // The guard that contact reads only *saved* state. The first version of this used
    // `world.spatial.queryRadius`, and the spatial hash is derived and deliberately not in the
    // snapshot -- so a freshly booted world had an empty index where a continuous run had a
    // populated one, and the first tick after a load found no contact. `melee.test.ts`'s
    // mid-wind-up save assertion is what caught it.
    const opts = {
      seed: SEED,
      wanderers: 0,
      mapSize: 96,
      startTimeOfDay: NIGHT,
      disabled: ["attention", "field-memory"],
    };
    const a = boot(opts);
    const survivor = a.world.components.getOrThrow(a.player as EntityId, Position);
    const zombie = a.world.spawn();
    a.world.components.set(zombie, Position, { x: survivor.x + 1, y: survivor.y });
    a.world.components.set(zombie, Velocity, { dx: 0, dy: -0.5 });
    a.world.components.set(zombie, Shambler, {
      ...defaultShamblerSpeeds(),
      state: ShamblerState.Wander,
      ticksToTurn: 100000,
      ticksCommitted: 0,
      ticksMilling: 0,
      ticksStaggered: 0,
      bias: 0,
    });
    stepN(a.world, 10);
    expect(stateOf(a.world, zombie)).toBe(ShamblerState.Pursue);

    const saved = createSave(a.world);
    const b = boot(opts);
    applySave(b.world, saved);
    expect(b.world.serialize()).toBe(a.world.serialize());

    step(a.world);
    step(b.world);
    expect(b.world.serialize()).toBe(a.world.serialize());
  });
});

describe("survivors are what it pursues", () => {
  it("does not pursue another shambler", () => {
    // The filter on `Controlled`. Without it a district is a mob of zombies chasing each other.
    const { world } = boot({
      seed: SEED,
      wanderers: 0,
      mapSize: 96,
      startTimeOfDay: NIGHT,
      disabled: ["attention", "field-memory", "player"],
    });
    // Two shamblers touching each other, well away from the map centre -- `boot` sets `Controlled`
    // on the survivor entity whether or not the player *module* is registered, so a pair parked at
    // the centre would be in contact with a survivor and pursue it correctly. That is what the
    // first version of this test measured.
    const ids: EntityId[] = [];
    for (const offset of [0, 0.4]) {
      const z = world.spawn();
      world.components.set(z, Position, { x: 20.5 + offset, y: 20.5 });
      world.components.set(z, Velocity, { dx: 0, dy: -0.5 });
      world.components.set(z, Shambler, {
        ...defaultShamblerSpeeds(),
        state: ShamblerState.Wander,
        ticksToTurn: 100000,
        ticksCommitted: 0,
        ticksMilling: 0,
        ticksStaggered: 0,
        bias: 0,
      });
      ids.push(z);
    }
    stepN(world, 20);

    for (const z of ids) expect(stateOf(world, z)).toBe(ShamblerState.Wander);
  });
});
