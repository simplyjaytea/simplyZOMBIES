# First-person profile, drawn (docs/40 slice 1)

Slice 1 of [docs/40](../40-first-person-spatial-contract.md#the-slices): the height profile the sim
will trace against, and the first-person district and bodies drawn from it. Nothing in the sim calls
the profile yet. Slice 2 is the first caller.

## What landed

- `godot/sim/space/space.gd` (`class_name SimSpace`), pure and static:
  - `PROFILE`: for each tile class, overlay kind and stage, the height bands the tile occupies, in
    integer millimetres over a full-tile footprint. Each band is `[from, to, stops]`, with `stops` a
    bit set of `MOVE`, `SIGHT`, `SHOT` and `REACH`. An overlay takes precedence over its tile's class,
    as `SimTileMap.is_solid` and `opacity_at` already read it.
  - `profile_key(map, tx, ty)`: the key a tile reads as.
  - `body_of(world, entity)`: `{radius: 300, height: mm}`, from the stance rung for a survivor and from
    the zombie's legs for a zombie.
  - `eye_of(world, entity)`: the eye height in mm, from the same read.
- `godot/presentation/first_person/district_view.gd`: every tile is drawn from `PROFILE` through
  `tile_boxes`. The ground stays one mesh. The opaque bands are one mesh (`SolidTiles`). The wire
  fence is one see-through mesh (`FenceTiles`), so it is drawn but does not hide what is behind it.
- `godot/presentation/first_person/body_view.gd`: each body is a `CylinderMesh` of the hit radius and
  the height `body_of` gives. The height is re-read every frame, so a stance change or a lost leg
  shows at once.
- `godot/check_fp_geometry.gd`, the gate. Wired as `godot:check:fp_geometry` (the script, a
  `run-godot.mjs` mode, a `package.json` script, the `godot:m2:chain` list, and shard 1 of
  `scripts/m2-shards.mjs`), plus a routing row in CLAUDE.md's "By system" table.

## Readings of docs/40's table

The table is a starting point and is ambiguous in places. Each reading below makes the rule the table
states true on screen.

- **Stage-3 board.** Its bands are `0-1100` (stops everything) and `2100-2550` (stops movement only).
  The table's sight and shot columns pass everything above 1100, so the top band must not stop sight
  or a shot. A top band that stopped sight would contradict the row.
- **Window.** Two bands: the sill `0-1000` and the lintel `2100-2550`, both stopping every purpose.
  The aperture `1000-2100` passes sight, a shot and a reach, which is the row's "through 1000-2100".
- **Open door.** One band, the lintel `2200-2550`, which stops sight, a shot and a reach but not
  movement, the row's "open". A doorway with no door takes the same key, because a Door tile with no
  overlay is an open doorway (`docs/37`'s door note).
- **Screen.** `0-2550`, stops sight and a shot, not a reach and not movement.
- **Low.** `0-1100`, stops sight, a shot and a reach. Movement is not stopped, which is the row's
  "open today"; docs/40 question 4 is still open.
- **Wire fence.** `0-2000`, stops movement and a reach, and passes sight and a shot. It is drawn in the
  see-through mesh.
- **Deep water.** No bands. It draws its surface below the floor and no solid.
- **Bodies.** The survivor rungs are walk (Walk, Jog, Sprint), crouch and crawl, with the eye and the
  cylinder heights of the body table. A zombie is the shambler's `1450 / 1650`, and a zombie whose legs
  are gone (docs/14's crawler) is `300 / 450`. Screamers and bloaters are drawn with the shambler's
  volume: the contract gives no other height for them.

## Gate

`npm run godot:check:fp_geometry` prints `FP_GEOMETRY_OK` on a fixture holding every tile class,
overlay kind and board and door stage. Its lanes:

- **FIXTURE.** Every `PROFILE` key is reached by some fixture tile.
- **BANDS.** Each tile's built mesh has exactly the height levels its bands give, to the millimetre,
  and fills its full footprint. The built district's `SolidTiles` and `FenceTiles` meshes hold exactly
  the opaque and fence levels. Water draws no solid.
- **OLD WAY.** The foundation's drawing, a window as one box and a Low tile not drawn, is refused by the
  same comparison.
- **BODIES.** A standing, crouched and crawling survivor, and a whole and a crawling zombie, each have
  a cylinder of the height `body_of` gives, with its centre at half that height, and the cylinder
  follows a stance change between frames. A capsule is refused.

Mutation tests, each reverted after the run:

| Change to the builder | Result |
|---|---|
| A window drawn as its sill only | `FP_GEOMETRY_FAIL BANDS: tile 2 (window) draws levels [0, 1000], its bands give [0, 1000, 2100, 2550]` |
| A Low tile not drawn | `FP_GEOMETRY_FAIL BANDS: tile 4 (low) draws levels [], its bands give [0, 1100]` |
| Bodies as capsules | `FP_GEOMETRY_FAIL BODIES: a standing survivor draws a cylinder that is not 1.750 m high ...` |

## Verified

- `npm run godot:check:fp_geometry`: `FP_GEOMETRY_OK`.
- `npm run godot:check:first_person`: `FIRST_PERSON_OK`.
- `npm run godot:smoke`: exits 0.
- `npm run check:routing`: `ROUTING_OK`.
- `npm run check:shards`: `SHARDS_OK`.

The full `godot:m2` chain was not run. Slice 1 touches no shared sim module: `godot/sim/space/space.gd`
is a new file that nothing in the sim calls, and the presentation files are not read by any sim gate.

## Limits

- Movement is `SimTileMap.is_solid`, so a body still walks through a car (docs/40 question 4, slice 9).
- The camera's eye is not `SimSpace.eye_of`; the foundation still uses its fixed 1.62 m (slice 7).
- No sim module reads `PROFILE` (slice 2 onwards), so nothing yet proves the sight line and the
  drawn wall agree. The gate proves only that the drawing matches the table.
- Band footprints are full tiles, so adjacent solids meet at their faces. The old `Low` and `Tree`
  insets are gone, because docs/40 says a tree is a full-tile column and the view must not show gaps the
  sim treats as opaque.
