# First-person starter-kit integration

Docs/23's "First-person starter-kit integration": the playable scene consumes the Blender kit's
GLBs, not only the desk and ledger. This lands after the art (#275) and after the first-person
alpha integration (#289).

## What landed

- `godot/presentation/first_person/district_view.gd`
  - **Walls.** Every `wall` profile tile is drawn by `wall_module.glb`, one instance in a
    `MultiMeshInstance3D` per placement variant, instead of its band box. The wall band is
    `0..2550` over the tile; the module is authored `1.00 x 2.60 x 0.12` with its origin at the
    floor centre, so each instance is scaled on Y to the band's top.
  - **Placement.** The run axis is taken from the tile's wall neighbours (more walls along X than
    Z runs along X; a tie, which is an isolated tile, runs X). The 0.12 m depth is centred on the
    tile edge toward open ground, so the outer face is flush with the tile boundary and the body
    of the module is inside the tile. The perpendicular side is the first open one in the fixed
    order `-y, +y` (or `-x, +x` for a Z run), so a boot is repeatable and a wall row lines up on
    the street side.
  - **Variants.** Two: the module as authored, and turned half a turn about its own centre. The
    choice is `hash(district seed, tile index) % 2`, so a long row does not repeat one face. The
    kit's three plaster variants are baked into the one mesh's atlas and cannot be re-picked per
    instance; the turn is the per-tile variation the geometry offers.
  - **Boards.** A tile whose overlay is `board` (stages 0-3) keeps its band boxes and gains one
    `barricade.glb` instance with its back face flush to the open side and the boards hanging
    outside the tile. The band boxes stay the occlusion authority: the model is 1.10 m tall and is
    in front of a stage-3 board's lower band (0-1100); it cannot open a tile the sim says blocks
    sight.
  - **Window, door, Low, screen, fence, tree, scrap/timber/stone** tiles keep their band geometry.
- `godot/presentation/first_person/container_view.gd`: a sim container whose kind is `shelf`, or a
  qualified shelf such as the district's `stockroom shelf`, is drawn by `shelf.glb` (0.90 x 1.85 x
  0.32, origin floor-centre) with its label above the top shelf. Cupboard, wardrobe, tool chest,
  larder and locker keep the labelled box: the kit has no closed cabinet, and an open shelf would
  describe a closed container wrongly. `shelf_models` counts how many the kit drew (one in the
  shipped district boot).
- `godot/presentation/first_person/assets.gd`: kit materials are
  `TEXTURE_FILTER_NEAREST_WITH_MIPMAPS`. The independent art review's #281 note says minification
  begins at about 7 m at 720p for 64 texels per metre, so nearest without mipmaps shimmers at
  range. `first_mesh()` returns a loaded model's mesh for the MultiMeshes.
- `godot/presentation/first_person/first_person.gd`: passes its district seed as the variant salt
  (`_district.call("build", map, SEED)`). The map is regenerated from that seed and does not carry
  it.

No file under `godot/sim/` changed, no art file changed, and no physics body or collision shape was
added. `tile_boxes` and `tile_mesh` still return the abstract band answer unchanged; the BANDS lane
and the old-way negative still judge them.

## The gate

`npm run godot:check:fp_geometry` gains a KIT lane (`godot/check_fp_geometry.gd`) and prints
`FP_GEOMETRY_OK`:

- True positive: every wall tile of the fixture carries exactly one module instance; an all-wall
  fixture leaves the opaque band mesh empty and draws four instances; every drawn AABB is the wall
  band's `0..2550` height, one tile (1.00 m) along the run and the module's own 0.12 m thickness,
  wholly inside the tile and flush to one edge.
- True negative: a half-width module placed through the same `DistrictView.wall_placement`
  function is refused by the same measurement.
- Without the GLBs the lane prints `FP_GEOMETRY_SKIP KIT: ...` and the band boxes are under test.

The BANDS lane is unchanged in what it asserts. When the view drew walls by module, its built
`SolidTiles` expectation omits the wall key, and the KIT lane measures those tiles more strictly
(exact height, exact width, documented thickness, inside the tile); the per-tile `tile_boxes`
comparison still includes walls. No assertion was deleted or loosened.

`godot:check:first_person`'s ART lane now requires nearest-with-mipmaps on the kit materials and
still refuses a linear-filtered one.

## Measured

Headed, 1280x720, Compatibility renderer, 300 frames after 30 warmup at the spawn of the shipped
256-tile district, same driver both sides (three runs a side):

| Run | Before (ms) | After (ms) |
|---|---:|---:|
| 1 | 1.606 | 1.723 |
| 2 | 1.597 | 1.337 |
| 3 | 1.597 | 1.631 |
| Median | **1.597** | **1.631** |
| Mean | **1.600** | **1.564** |

The after spread (1.337-1.723) is the machine's noise; the medians differ by 0.03 ms and the means
by -0.04 ms, so the kit walls cost no measurable frame time at spawn. They are MultiMesh instances,
not one node per tile: the 256 district adds at most 2 wall MultiMeshes (one barricade MultiMesh
appears only when a board exists), and the wall band boxes leave the opaque mesh at the same time.
Both sides are far below docs/22's 10 ms draw target.

## Captures

Saved outside the repository, 1280x720, the real scene's viewport:

- Street at spawn: `C:/Users/jtf/AppData/Local/Temp/opencode/kit-captures/street.png`
- A wall row seen across open ground:
  `C:/Users/jtf/AppData/Local/Temp/opencode/kit-captures/wall_row.png`
- A boarded window with its barricade:
  `C:/Users/jtf/AppData/Local/Temp/opencode/kit-captures/boarded_window.png`

The boarded-window shot plants a stage-3 board overlay on a window of the boot map so the barricade
is visible; the fortify stage is the sim's, and the driver only stages the shot. The captures come
from `get_viewport().get_texture().get_image()` -- no desktop screenshot and no OS input.

## Not in this piece

- Windows, doors and Low tiles keep their band boxes.
- A cupboard, wardrobe, tool chest, larder or stockroom has no model (the kit has no closed
  cabinet).
- The wall module is one mesh with the atlas's plaster variants baked in; per-instance plaster
  choice would need separate meshes or a shader.
- The barricade is 1.20 m wide, so on a 1.00 m tile it overhangs 0.10 m into each neighbour. It is
  a nailed board, and it is drawn outside the tile by design.
