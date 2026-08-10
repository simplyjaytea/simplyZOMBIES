// Who can see what: the observer half of the visibility primitive.
//
// docs/28-visibility-and-sightlines.md#one-primitive-three-consumers states the rule this
// file exists to enforce: **one visibility computation per observer per tick, at most, and no
// consumer computes its own.** A renderer that runs a second, cheaper line-of-sight check
// "just for drawing" will disagree with the host's filter somewhere, and the place they
// disagree is the exploit. So the shadowcast happens here, once, and the renderer -- and
// later the light channel and the multiplayer view filter -- read the answer.
//
// Three things are deliberately separated:
//
//   1. **Geometry** (shadowcast.ts) -- is there a sightline. Symmetric, integer, cacheable.
//   2. **Arcs** (here) -- is the observer looking that way. Cheap, exact, evaluated per query.
//   3. **Detail** (here) -- focal identifies, peripheral only notices movement.
//
// The split is what makes "recompute on change" affordable. Turning on the spot changes what
// you are looking at but not what has a sightline to you, so it costs nothing at all; the
// shadowcast is redone only when an observer crosses into a new tile, changes range, or the
// map itself changes underneath it.

import { defineComponent, Facing, Position } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import { Eye, TILE_METRES, type TileMap } from "../map/tilemap";
import { ambientLightAt } from "../time/clock";
import { shadowcast, VisibleTiles } from "./shadowcast";

/**
 * How well an observer sees a point.
 *
 * The two live levels are docs/28's two arcs, and the difference between them is the whole
 * reason there are two: the focal cone answers *"a shambler, eleven metres, bearing
 * north-east"* and the peripheral one answers *"something moved"*. Collapsing them into a
 * boolean would throw away the more interesting half.
 */
export const enum Detail {
  /** No sightline, out of range, or behind. */
  Unseen = 0,
  /** Movement is noticed. Identity is not. */
  Peripheral = 1,
  /** Seen properly. */
  Focal = 2,
}

/**
 * An entity that can see.
 *
 * Survivors, NPCs and -- with a much worse profile -- zombies. Carried as a component rather
 * than assumed of everything with a `Position`, because per-observer visibility is the first
 * cost in this project that does not amortise across the horde
 * ([the cost shape](../../../docs/22-performance.md#visibility-is-a-different-cost-shape)),
 * and a component is how the tiering docs/22 asks for gets expressed: an entity that does not
 * need a sightline does not carry one.
 *
 * The angles are stored per observer rather than as module constants because they are the
 * first thing that will be tuned, and because a screamer and a survivor will not share them.
 * docs/28 deliberately declines to name numbers; the defaults below are a starting point, not
 * a decision -- see {@link DAYLIGHT_EYES}.
 */
export type Observer = {
  /** How far this observer can see, in metres. */
  rangeMetres: number;
  /** Half-angle of the focal cone, radians. Detail here is reliable. */
  focalHalfAngle: number;
  /** Half-angle of the peripheral cone, radians. Movement here is noticed; identity is not. */
  peripheralHalfAngle: number;
  /** Eye level. {@link Eye.Crouched} is blocked by low cover; nothing sets it yet. */
  eye: Eye;
};

export const Observer = defineComponent<Observer>("Observer");

/**
 * A survivor's eyes, in daylight.
 *
 * **Range is a property of light, not of eyes** (docs/28#what-an-observer-is): daylight sees
 * to the map edge and a dark interior sees as far as whatever the survivor is carrying. Until
 * the [light channel](../../../docs/03-attention.md#light) and day/night exist there is
 * nothing to derive a range *from*, so this is daylight, clamped to something a little wider
 * than the viewport. When light lands, this number stops being a constant and becomes a
 * lookup -- which is a change to one field, not to the primitive.
 *
 * The arcs: a 60-degree focal cone and a 190-degree total field of view. Both are guesses
 * with a shape rather than measurements, and the shape is the part that matters -- there is
 * detail ahead, awareness to the sides, and **nothing behind**. Being flanked is a real state
 * and not a difficulty setting.
 */
export const DAYLIGHT_EYES: Observer = {
  rangeMetres: 48,
  focalHalfAngle: Math.PI / 6,
  peripheralHalfAngle: (95 * Math.PI) / 180,
  eye: Eye.Standing,
};

/**
 * A shambler's eyes.
 *
 * Short, and almost all of it peripheral -- a shambler notices that something is there rather
 * than what it is, which is the same distinction its
 * [sensory profile](../../../docs/14-zombies.md#sensory-profiles) already makes between the
 * channels. Nothing in the simulation reads this yet: zombies get sight when the light channel
 * does, because docs/14's first design rule is that sight must not make them tactical, and the
 * safe way to honour that is to give them sight and a single new stimulus at the same time.
 */
export const SHAMBLER_EYES: Observer = {
  rangeMetres: 12,
  focalHalfAngle: Math.PI / 8,
  peripheralHalfAngle: (110 * Math.PI) / 180,
  eye: Eye.Standing,
};

/** One observer's cached view. */
type View = {
  /** What the shadowcast was computed for. A change here is what forces a recompute. */
  key: string;
  tiles: VisibleTiles;
  /** Observer position and heading as of the last refresh, for the arc test. */
  x: number;
  y: number;
  facingX: number;
  facingY: number;
  cosFocal: number;
  cosPeripheral: number;
  rangeSquared: number;
};

/**
 * Every observer's view, kept current.
 *
 * Derived state, exactly like the tile map: it is a pure function of positions, facings and
 * the map, so it is **not** in the snapshot. Putting it there would mean a save could
 * disagree with the world it was taken in, and would make the save grow by a kilobyte per
 * observer for something recomputed in microseconds.
 */
export class VisibilityIndex {
  private readonly views = new Map<EntityId, View>();

  /**
   * Shadowcasts performed. The guard behind "recompute on change, not on tick" -- a test
   * watches this stay flat while an observer stands still, which is the only way to
   * distinguish a cache that works from one that recomputes and gets the same answer.
   */
  recomputes = 0;

  /** Bumped when the map changes, which invalidates every cached view at once. */
  private generation = 0;

  /**
   * Call when tiles change. Nothing does yet -- the map is static until
   * [structures](../../../docs/15-base-building.md) arrive in Milestone 2 -- and it exists
   * now because the alternative is a stale sightline through a wall that was just built,
   * which is a bug that looks exactly like a cheat.
   */
  invalidate(): void {
    this.generation++;
  }

  /**
   * Bring every observer's view up to date. Registered as a kernel system by `boot`.
   *
   * Kernel rather than a module for the same reason field decay is: a module that can be
   * switched off must not be what decides whether the game draws through walls. "Disable the
   * shambler module" must not mean "re-enable the wallhack".
   */
  refresh(world: World, map: TileMap): void {
    const seen = new Set<EntityId>();

    for (const entity of world.components.query(Position, Observer)) {
      const position = world.components.getOrThrow(entity, Position);
      const observer = world.components.getOrThrow(entity, Observer);
      const facing = world.components.get(entity, Facing)?.radians ?? 0;

      const tileX = Math.floor(position.x / TILE_METRES);
      const tileY = Math.floor(position.y / TILE_METRES);

      // Night is not a filter over the same view: it is a smaller view. Range is a property
      // of light (docs/28#what-an-observer-is), and this is the ambient half of it.
      //
      // The rounding up to whole tiles is what keeps this affordable, and it is worth saying
      // out loud because it looks like a detail. Ambient light changes every tick through
      // dawn and dusk; the *integer tile radius* changes about thirty-six times across a
      // thirty-minute transition, and the cache key is built from that integer. So the sun
      // coming up costs thirty-six shadowcasts spread over half an hour, not one per tick.
      const metres = observer.rangeMetres * ambientLightAt(world.tick);
      const range = Math.max(1, Math.ceil(metres / TILE_METRES));
      const key = `${tileX},${tileY},${range},${observer.eye},${this.generation}`;

      let view = this.views.get(entity);
      if (view === undefined) {
        view = {
          key: "",
          tiles: new VisibleTiles(),
          x: position.x,
          y: position.y,
          facingX: 1,
          facingY: 0,
          cosFocal: 1,
          cosPeripheral: 1,
          rangeSquared: 0,
        };
        this.views.set(entity, view);
      }

      // The expensive half, and the half that is usually skipped. A survivor who has not
      // left the tile they were standing in sees what they saw, however far they have
      // turned -- turning changes the arcs below, and the arcs are not cached.
      if (view.key !== key) {
        shadowcast(map, tileX, tileY, range, view.tiles, observer.eye);
        view.key = key;
        this.recomputes++;
      }

      view.x = position.x;
      view.y = position.y;
      view.facingX = Math.cos(facing);
      view.facingY = Math.sin(facing);
      view.cosFocal = Math.cos(observer.focalHalfAngle);
      view.cosPeripheral = Math.cos(observer.peripheralHalfAngle);
      // The arc test rejects on distance too, and it has to agree with the geometry above or
      // an entity in the corner of a shrinking view would linger a tile longer than the
      // tiles do.
      view.rangeSquared = metres * metres;
      seen.add(entity);
    }

    // Otherwise a despawned observer's view outlives it, and a recycled entity id inherits
    // somebody else's eyes.
    for (const entity of this.views.keys()) {
      if (!seen.has(entity)) this.views.delete(entity);
    }
  }

  /** The raw sightline set for an observer, or `undefined` if it has none. Debug and light. */
  tilesFor(observer: EntityId): VisibleTiles | undefined {
    return this.views.get(observer)?.tiles;
  }

  /**
   * How well `observer` sees the point (x, y), in world metres.
   *
   * Geometry first, then range, then arcs -- cheapest rejection last is deliberate, because
   * the array lookup is one index and the arc test is two multiplications. An observer with
   * no view sees nothing, which is the safe direction to fail: a missing view hides the
   * world rather than revealing it.
   */
  detail(observer: EntityId, x: number, y: number): Detail {
    const view = this.views.get(observer);
    if (view === undefined) return Detail.Unseen;

    if (!view.tiles.has(Math.floor(x / TILE_METRES), Math.floor(y / TILE_METRES))) {
      return Detail.Unseen;
    }

    const dx = x - view.x;
    const dy = y - view.y;
    const distanceSquared = dx * dx + dy * dy;
    if (distanceSquared > view.rangeSquared) return Detail.Unseen;
    // Standing on it. No direction to compare against, and no sense in which it is behind you.
    if (distanceSquared === 0) return Detail.Focal;

    // The arc test, as a dot product against the heading rather than an angle difference:
    // `cos` of the angle between them, with no `atan2`, no branch on which side of pi the
    // difference landed, and no wrap-around case to get wrong.
    const cosine = (dx * view.facingX + dy * view.facingY) / Math.sqrt(distanceSquared);
    if (cosine >= view.cosFocal) return Detail.Focal;
    if (cosine >= view.cosPeripheral) return Detail.Peripheral;
    return Detail.Unseen;
  }

  /** Convenience for the common "may this be shown at all" question. */
  canSee(observer: EntityId, x: number, y: number): boolean {
    return this.detail(observer, x, y) !== Detail.Unseen;
  }

  /** Observers with a live view. */
  get observerCount(): number {
    return this.views.size;
  }
}
