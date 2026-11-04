# First-person building finishes

This is the production architectural kit for all 22 templates in `godot/content/buildings/`. The
builder creates one GLB per template, a shared pixel atlas, `buildings.manifest.json`, and the editable
`buildings.blend`. Godot reads the exported files directly; Blender is not a runtime dependency.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check
```

`--check` rebuilds into a temporary directory, compares every GLB, the atlas, and the manifest with the
committed bytes, and prints `BUILDINGS_CHECK_OK`. It checks export bounds against the committed
manifest, wall-band heights and tile ownership, floor contact, coplanar overlap, measured UV density,
atlas materials and filtering, every wall/roof look, and every template resolution. The manifest is
written with LF; a checkout that holds it with CRLF (`core.autocrlf`) is folded back before the compare.
The editable blend is arranged as a contact sheet of the 22 source shells and is not byte-compared.

Two checks judge what Godot will draw. Every roof face must be wound to face up, and every eave,
fascia, parapet and gable end to face away from the building: the material is back-face culled, so a
face wound the other way vanishes from the street. And every per-tile piece (below) is assembled in
three states, every openable wall standing, every one opened, and alternating, and each drawn window
is crossed by rays from each open face: at 1.25 and 1.85 m they must pass every opaque face, at 0.5 and
2.3 m they must hit the sill or lintel.

Each negative mode must exit non-zero with `BUILDINGS_CHECK_FAIL`:

```bash
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=bounds
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=coplanar
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=density
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=contact
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=look
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=template
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=winding
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=aperture
```

`winding` reverses one hip-roof face; `aperture` draws a wall across house_small's first window.

## Data and runtime

`godot/assets/first_person/buildings.manifest.json` maps each template id to its GLB, wall and roof
look, roof form, interior family, actual interior wall/floor finishes, measured bounds, and three subtle tint variants.
`godot/presentation/first_person/building_view.gd` caches each source model, duplicates it for each
stamped building record, and chooses a tint from a fixed hash of district seed, template id, and stamped
position. It never draws from runtime randomness or writes sim state.

Worldgen's occluder pass turns some template walls into windows after the stamp
(`SimWorldgen._dress_occluders`: a wall with open ground on both sides along one axis, one time in
three). The template alone cannot say which, so each GLB carries what every instance draws and, apart,
what depends on the stamped map:

- `spatial_bands`: the walls that can never open, merged. `finish`: floors, ceilings, plinth, cornice,
  skirting, door casings and the roof, merged, with a transparent glass surface where needed.
- `<slug>-wall-X-Y`: a wall the occluder pass may open (the builder's `window_candidate`, the same rule
  read off the template), drawn while the stamped tile is a wall.
- `<slug>-window-X-Y`: a window's textured sill (0–1.00 m) and lintel (2.10–2.55 m), casing, glazing
  and curtains, for every template window and every wall that may open; drawn while the tile is a window.
- `<slug>-jamb-X-Y-SIDE`: wall X,Y's face into a neighbouring opening, drawn while X,Y is a wall and the
  neighbour a window.

X and Y are template tiles. `building_view.gd` reads `SimSpace.profile_key` at each stamped tile, picks
the pieces, and merges them into one `Openings` mesh per instance (cached across instances that open the
same tiles), so a building costs a handful of draws rather than one per tile. It records what it drew in
`drawn`; `district_view.gd` drops a tile's band boxes only where that matches the sim, so a finished
window has no leftover sill and lintel boxes and a mismatch would still show the sim's bands. Doors and
boarded windows keep the dynamic boxes from `district_view.gd`; door casings sit proud of them.

The `godot:check:fp_geometry` FINISHES lane loads every model and proves wall caps (each wall capped
exactly once, by `spatial_bands` or its own wall piece), the manifest's piece counts against the nodes
the view parses, 0–2.55 m wall bands, solid-host attachment within 25 mm, transparent glazing, nearest
filtering, and real stamped placement. Its WORLDGEN lane builds all four districts through
`SimBoot.bare` and casts the same window rays through every sim window of every finished building,
holds every sim wall to a drawn wall, and counts band boxes left under drawn tiles. A wall planted over
a window worldgen opened, and a baseline that keeps its band boxes, are both refused.

## Coordinates and contract bands

Source coordinates are X east, Y up, Z south, with the origin at the template's north-west floor corner.
The runtime adds the building record's `x/y` as Godot `x/z`. All export transforms are applied.

- Full wall and top cap: 0.00–2.55 m.
- Door lintel retained from SimSpace: 2.20–2.55 m.
- Window sill and lintel retained from SimSpace: 0.00–1.00 m and 2.10–2.55 m.
- Interior floor finish: 0.004 m above the floor to avoid z-fighting.
- Ceiling finish: 2.545 m, immediately below the wall top, over every indoor tile, counters,
  shelves and partitions included.
- Eaves: 0.30 m on pitched roofs, deepened to 0.45 m for batch A's two houses; flat roof
  overhang: 0.18 m. The gabled house's decorative upper façade and lifted roof are finish geometry,
  not another sim floor.

Roofs, ceilings, floors, casings, glazing, curtains, foundation, skirting, and corner boards are
presentation only. They do not create a walkable upper level or alter collision, sight, shots, or reach.
Whole-tile wall footprints and 1 m-deep reveals remain: thin edge walls are a separate shared-sim and
owner decision, not something this kit hides.

## Looks, roofs, and interiors

The content uses four exterior wall looks, all covered: `timber`, `render`, `brick`, and `block`.
The kit also provides `siding` for the later schema/tag piece. Roof looks are `shingle`, `tin`, and
`tar`, plus `kawara`. Shingle and kawara roofs are gables on small/narrow templates and hips at
12 × 8 m or larger; tin roofs are gables; tar roofs are flat with a parapet. Large shingle houses may
have a brick chimney. Roof pitch is derived from template size, with the gabled house's pitch chosen
to keep its lifted roof legible from the street.

### Batch A: materials and houses

- **Kawara** uses cool grey glazed-clay courses (`#262a2b` through `#505653`), with alternating
  tile offsets, a curved-tile highlight and sparse chips. Its atlas styles are `kawara` and
  `kawara_alt`.
- **Siding** uses vertical, weathered boards in a restrained cedar-grey ramp. Its atlas styles are
  `siding_vertical` and `siding_vertical_alt`. The regular board and tile structure never uses cloud
  noise or chooses a colour patch from an atlas cell.
- `house_small` keeps its 9 × 7 m footprint, timber walls, door and windows, with a kawara roof,
  0.45 m eaves and a 0.12 m-high genkan step outside the south door.
- `house_gable` keeps its 11 × 8 m footprint, both doors and every window. It uses siding and
  kawara, 0.45 m eaves and genkan steps. A decorative upper façade carries regular sash stations;
  its roof is lifted 1.90 m and has a 2.00 m rise above the eave. The interior remains the sim's
  ground floor, with no new collision, sight or walkable level.
- These two overrides live in the builder and their manifest entries. The template JSON, schema enum
  and `street.json` do not change here; R4 can retag the content after the materials have landed.
- Each genkan step's exact bounds are declared as a `finishVolumes` entry. `check_fp_geometry.gd`
  accepts a finish vertex inside that declared exterior attachment, but rejects the same point when
  the declaration is absent; its open-tile negative remains in force.

The templates have no room-tag field, so interiors resolve by the first recognised building tag:

- `residential`: faded wallpaper and worn boards; a fixed template hash selects carpet for whole houses.
- `cabin`: timber panelling and boards.
- `commercial`: plaster and lino/tile.
- `civic`: pale plaster and tile.
- `industrial`: block and concrete.
- `shed`: panelling and concrete.

If room tags are added to content later, the manifest is the place to refine this mapping.

## Windows

Windows remain open for sim sight and shots. The glass is a 20%-alpha dark tint with 34%-alpha grime at
its edges, low roughness, and a slight metallic response; it is not an opaque blue panel. Two sashes and
a thin centre muntin make the glazing legible. Residential and cabin casings leave about 0.72 m of the
1 m tile glazed, industrial/shed casings about 0.80 m, and commercial shopfronts keep the broad opening.
Some interior residential windows have side curtains, selected by a fixed template/tile/side hash. The
curtains do not cover the central aperture. Template window counts are unchanged.

## Atlas and modelling conventions

`buildings_atlas.png` is 512 × 512 px: 8 × 8 one-metre cells at **64 texels per metre**. UVs are clipped
at metre boundaries, including sloped hip-roof polygons, so no face samples a neighbouring cell. The
builder measures every polygon edge and requires 48–80 texels/m; the generated assets measure 64. GLBs
request nearest magnification and Godot applies nearest-with-mipmaps filtering for distance.

The opaque `BuildingsAtlas` and transparent `WindowGlass` materials reference the same atlas. The palette
is faded sage timber, warm grey render, brown brick, charcoal roofs, cool grey kawara, cedar-grey
siding, aged cream trim, and subdued floor tones. Wear is sparse and surface-specific, with no
camouflage-like cloud noise or copied texture pixels. Siding and floor boards are 0.125 m wide;
brick courses are 0.125 m and block courses 0.25 m.
All meshes and textures are original procedural work from fixed integer hashes.
