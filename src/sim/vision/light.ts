// The light channel.
//
// The third of docs/03-attention.md's three channels, and the only one that is not a field.
// Noise floods and decays; scent diffuses and lingers; light is a **shadowcast from the
// emitter**, on and then off, with nothing stored between ticks. docs/03:189-191 says so
// outright, and two things in this repo agree with it:
//
//   - The attention field is 4 m cells. A shadowcast is 1 m tiles. Light is the one channel
//     where a wall is an *absolute* rather than a penalty -- noise pays an 18 m-equivalent to
//     cross one, scent ignores them entirely -- and that absoluteness is what makes shutters
//     work *completely* (docs/28#what-blocks-sight). Four-metre cells would round it away.
//   - `AttentionField.liveCells()` is read by three Milestone 1 exit-criterion assertions as
//     "the district is silent". A third channel folded in there would break the noise
//     criterion for no reason.
//
// So light lives here, beside the primitive it is built on, and magnitude *is* range: the
// numbers in docs/03's table are metres, in the same metres as everything else.
//
// Kernel rather than a module, for the reason the visibility index is one and one more
// besides: an observer's range now derives from the light where it stands, and range decides
// the visible set, which decides whether the renderer draws through walls. A light index that
// could be switched off would mean "disable a limb, get the wallhack back at night". A world
// booted with every module disabled still has a dark night -- it just has nothing emitting
// into it.

import { defineComponent, Position } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import { Eye, TILE_METRES, tileRange, type TileMap } from "../map/tilemap";
import { ambientLightAt } from "../time/clock";
import { shadowcast, VisibleTiles } from "./shadowcast";
import type { Observer } from "./visibility";

/**
 * Something that lights the world around it.
 *
 * `magnitude` is reach in metres, straight off docs/03-attention.md#light's table. One field
 * and no brightness unit: a lamp is not "35 bright", it reaches 35 m, and the light at a
 * point is how much of that reach is left when you get there.
 *
 * A kernel component for the reason `Facing` is one -- two systems read it and neither owns
 * the other. `kernel.visibility` reads it through the index to size an observer's view, and
 * the shambler reads it to lean toward what it can see. What is *module*-owned is the half
 * that decides who emits: see `sim/modules/light.ts`.
 */
export type LightSource = { magnitude: number };
export const LightSource = defineComponent<LightSource>("LightSource");

/**
 * docs/03-attention.md#light's emitter table, as code.
 *
 * Here rather than in content because these are the calibration, the way the noise magnitudes
 * are: content authors *which* base carries which reach, and a test pins the content against
 * this table so the two cannot drift. The floodlight has no carryable form on purpose -- see
 * the cost note on `refresh`.
 */
export const LIGHT_TABLE = {
  candle: 3,
  campfire: 20,
  lamp: 35,
  floodlight: 90,
} as const;

/** One source's cast, cached exactly the way an observer's view is. */
type Cast = {
  /** What the shadowcast was computed for. A change here is what forces a recompute. */
  key: string;
  tiles: VisibleTiles;
  /** Where the light is coming from, in metres, for the distance falloff. */
  x: number;
  y: number;
  magnitude: number;
};

/**
 * Every light source's reach, kept current.
 *
 * Derived state, exactly like the visibility index and for the same reasons: it is a pure
 * function of positions, magnitudes and the tile map, all of which the snapshot already holds,
 * so storing it would be a second copy of a fact and a way for a save to disagree with itself.
 */
export class LightIndex {
  private readonly casts = new Map<EntityId, Cast>();

  /**
   * Source entities, in the order `refresh` found them -- which is slot order, because
   * `ComponentStore.query` sorts by entity index and this list inherits that.
   *
   * Recorded rather than re-derived, and the ordering is not tidiness. The shambler's light
   * stimulus picks the *brightest* source it can see, and a winner-pick that walked these in
   * insertion order would make the horde's behaviour depend on which lamp spawned first -- a
   * determinism bug that only shows up once two lights are visible at once. There is
   * deliberately no second sort here: one guarantee, in `query`, is harder to break than two
   * that have to agree. The test that proves it fails when `query`'s sort is removed.
   */
  private orderedSources: EntityId[] = [];

  /**
   * Shadowcasts performed. The guard behind "recompute on change, not on tick", mirroring
   * `VisibilityIndex.recomputes` -- a test watches this stay flat for a lamp standing on the
   * floor, which is the only way to tell a cache that works from one that recomputes and gets
   * the same answer.
   */
  recomputes = 0;

  /**
   * Bring every source's cast up to date. Registered as a kernel system by `boot`.
   *
   * Cost, because it is the thing that decides what content may exist. A cast's window is
   * `2r+1` on a side (`VisibleTiles`), so: a candle at 3 m is 49 cells, a campfire at 20 m is
   * 1,681, a lamp at 35 m is 5,041, a floodlight at 90 m is 32,761. Buffers are retained per
   * source across ticks and `reset()` reuses them at unchanged range, so a *stationary* source
   * costs one cast ever and steady state allocates nothing.
   *
   * A **carried** source is the expensive shape: the key includes the tile, and a survivor
   * walking 1.4 m/s crosses about 1.4 tiles a second. At a lamp's 5,041 cells that is fine. At
   * a floodlight's 32,761 it is not, which is why the floodlight is authored with no
   * `equipSlot` -- the budget is defended in content rather than by a check here, because a
   * check here would be a rule nobody reads until it fires.
   */
  refresh(world: World, map: TileMap): void {
    const seen = new Set<EntityId>();
    this.orderedSources = [];

    for (const entity of world.components.query(Position, LightSource)) {
      const position = world.components.getOrThrow(entity, Position);
      const source = world.components.getOrThrow(entity, LightSource);

      // A source with no reach is not a source. Guarded rather than cast at range 1, because
      // `tileRange` floors at one tile and would otherwise light the emitter's own cell for a
      // lamp that is switched off.
      if (!(source.magnitude > 0)) continue;

      const tileX = Math.floor(position.x / TILE_METRES);
      const tileY = Math.floor(position.y / TILE_METRES);
      const range = tileRange(source.magnitude);

      // The same key shape as `VisibilityIndex`, including the eye level it will never vary:
      // a lamp does not crouch. Kept so the two caches are visibly the same object, and so
      // `world.mapGeneration` is the one thing that invalidates both.
      const key = `${tileX},${tileY},${range},${Eye.Standing},${world.mapGeneration}`;

      let cast = this.casts.get(entity);
      if (cast === undefined) {
        cast = { key: "", tiles: new VisibleTiles(), x: position.x, y: position.y, magnitude: 0 };
        this.casts.set(entity, cast);
      }

      if (cast.key !== key) {
        shadowcast(map, tileX, tileY, range, cast.tiles, Eye.Standing);
        cast.key = key;
        this.recomputes++;
      }

      // Position and magnitude are read every query for the falloff, so they track the
      // carrier even on the ticks the geometry is reused. A lamp carried across a tile is
      // brighter on the near side of it before the cast is redone.
      cast.x = position.x;
      cast.y = position.y;
      cast.magnitude = source.magnitude;
      seen.add(entity);
      this.orderedSources.push(entity);
    }

    // Otherwise a snuffed-out source keeps lighting, and a recycled entity id inherits
    // somebody else's lamp.
    for (const entity of this.casts.keys()) {
      if (!seen.has(entity)) this.casts.delete(entity);
    }
  }

  /**
   * How much light reaches this point, in metres of usable reach. Zero is dark.
   *
   * **The maximum across sources, never the sum.** Magnitude is *range*, and ranges do not
   * add: two candles in the same spot do not make a lamp, and no number of candles ever does.
   * This is the same `max` the noise channel commits with and deliberately not scent's sum --
   * scent sums because a crowd genuinely smells more than one body, and light does not work
   * that way.
   *
   * Walked per source rather than read out of a dense per-tile array, on two counts: a
   * 256x256 brightness layer would be 65,536 writes on every tick a lamp is carried, and it
   * would erase source identity -- which the shambler's stimulus needs, because the question
   * there is "can I see the source", not "am I standing somewhere bright".
   */
  litMetres(x: number, y: number): number {
    const tileX = Math.floor(x / TILE_METRES);
    const tileY = Math.floor(y / TILE_METRES);

    let best = 0;
    for (const entity of this.orderedSources) {
      const cast = this.casts.get(entity);
      if (cast === undefined) continue;
      // The wall test, and the whole reason light is a shadowcast: no sightline from the
      // emitter, no light, however close and however bright.
      if (!cast.tiles.has(tileX, tileY)) continue;

      const remaining = cast.magnitude - Math.hypot(x - cast.x, y - cast.y);
      if (remaining > best) best = remaining;
    }
    return best;
  }

  /** The raw lit set for one source, or `undefined` if it has none. For the overlay. */
  tilesFor(source: EntityId): VisibleTiles | undefined {
    return this.casts.get(source)?.tiles;
  }

  /** Every source, in the deterministic order the stimulus must walk them in. */
  get sources(): readonly EntityId[] {
    return this.orderedSources;
  }

  /** How many sources are lit. For the HUD and the budgets. */
  get sourceCount(): number {
    return this.orderedSources.length;
  }

  /** Where a source is and how far it reaches, for the renderer's falloff. */
  sourceAt(entity: EntityId): { x: number; y: number; magnitude: number } | undefined {
    const cast = this.casts.get(entity);
    return cast === undefined ? undefined : { x: cast.x, y: cast.y, magnitude: cast.magnitude };
  }
}

/**
 * How far this observer can see from where it stands, in metres.
 *
 * The one function `visibility.ts` imports from here, and the join between the two halves of
 * the channel: ambient light is the sun, emitted light is everything in docs/03's table, and
 * an observer gets whichever is better where it is standing.
 *
 * Everything is metres, so there is no brightness unit to invent and nothing to calibrate.
 *
 * - `max` of ambient and emitted, because a torch at noon should change nothing -- daylight
 *   already reaches further than any carryable.
 * - `min` with the observer's own range, because eyes are the ceiling. A floodlight does not
 *   give a survivor better than daylight vision, and a shambler's 12 m stays 12 m however
 *   bright the street is. Light removes a penalty; it does not grant an ability.
 */
export function sightMetres(world: World, observer: Observer, x: number, y: number): number {
  const ambient = observer.rangeMetres * ambientLightAt(world.tick);
  return Math.min(observer.rangeMetres, Math.max(ambient, world.light.litMetres(x, y)));
}
