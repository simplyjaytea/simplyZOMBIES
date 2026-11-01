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
atlas materials and filtering, every wall/roof look, and every template resolution. The editable blend
is arranged as a contact sheet of the 22 source shells and is not byte-compared.

Each negative mode must exit non-zero with `BUILDINGS_CHECK_FAIL`:

```bash
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=bounds
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=coplanar
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=density
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=contact
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=look
blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check --plant=template
```

## Data and runtime

`godot/assets/first_person/buildings.manifest.json` maps each template id to its GLB, wall and roof
look, roof form, interior family, actual interior wall/floor finishes, measured bounds, and three subtle tint variants.
`godot/presentation/first_person/building_view.gd` caches each source model, duplicates it for each
stamped building record, and chooses a tint from a fixed hash of district seed, template id, and stamped
position. It never draws from runtime randomness or writes sim state.

Each GLB has two merged meshes: `spatial_bands` for full-height wall tiles and `finish` for everything
else. The finish mesh has an opaque atlas surface and, where windows exist, a transparent glass surface.
This keeps the district to merged draws per material rather than one node per tile or casing.

Only full wall tiles have their ordinary band boxes replaced. Doors, windows, and boarded windows keep
the dynamic boxes from `district_view.gd`; textured faces and trim sit proud of those boxes. The
`godot:check:fp_geometry` FINISHES lane loads every model and proves wall caps, 0–2.55 m wall bands,
solid-host attachment within 25 mm, transparent glazing, nearest filtering, and real stamped placement.
Its planted open-room and above-wall vertices fail.

## Coordinates and contract bands

Source coordinates are X east, Y up, Z south, with the origin at the template's north-west floor corner.
The runtime adds the building record's `x/y` as Godot `x/z`. All export transforms are applied.

- Full wall and top cap: 0.00–2.55 m.
- Door lintel retained from SimSpace: 2.20–2.55 m.
- Window sill and lintel retained from SimSpace: 0.00–1.00 m and 2.10–2.55 m.
- Interior floor finish: 0.004 m above the floor to avoid z-fighting.
- Ceiling finish: 2.545 m, immediately below the wall top.
- Eaves: 0.30 m on pitched roofs; flat roof overhang: 0.18 m.

Roofs, ceilings, floors, casings, glazing, curtains, foundation, skirting, and corner boards are
presentation only. They do not create a walkable upper level or alter collision, sight, shots, or reach.
Whole-tile wall footprints and 1 m-deep reveals remain: thin edge walls are a separate shared-sim and
owner decision, not something this kit hides.

## Looks, roofs, and interiors

The content uses four exterior wall looks, all covered: `timber`, `render`, `brick`, and `block`. Each
has two or three quiet variants. Roof looks are `shingle`, `tin`, and `tar`. Shingle roofs are gables on
small/narrow templates and hips at 12 × 8 m or larger; tin roofs are gables; tar roofs are flat with a
parapet. Large shingle houses may have a brick chimney. Roof pitch is derived from template size.

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
is faded sage timber, warm grey render, brown brick, charcoal roofs, aged cream trim, and subdued floor
tones. Wear is sparse and surface-specific, with no camouflage-like cloud noise or copied texture pixels.
Siding courses and floor boards are 0.125 m wide; brick courses are 0.125 m and block courses 0.25 m.
All meshes and textures are original procedural work from fixed integer hashes.
