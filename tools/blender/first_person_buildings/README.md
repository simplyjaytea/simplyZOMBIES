# First-person building finish prototype

`house_small_finish.glb` is an original presentation-only shell for the existing
`building.house.small` template. It is a visual experiment, not a general building system and not a
change to the simulation. Godot reads the exported GLB directly and does not need Blender.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_buildings/build_house.py
blender --background --factory-startup --python tools/blender/first_person_buildings/build_house.py -- --check
```

The builder reads `godot/content/buildings/house_small.json`, creates the atlas procedurally with
fixed integer hashes, exports the shell, and saves the editable `house.blend`. Rebuilt GLB and atlas
files are byte-identical. `--check` exports into a temporary directory and compares those two files
with the committed assets. It also checks the expected bounds and origin, one single-sided atlas
material, nearest magnification, and the four editable object groups. `house.blend` is a convenience
scene and is not byte-compared.

For a Blender beauty render outside the repository:

```bash
blender --background --factory-startup --python tools/blender/first_person_buildings/build_house.py -- --render-dir /absolute/scratch/folder
```

## Coordinates and contract bands

The source mesh uses Godot-like coordinates internally: X east, Y up, Z south. Blender stores X,
negative Z, Y; the glTF exporter restores +Y-up Godot coordinates. The origin is the template's
north-west floor corner, so the runtime places the asset at the building manifest's `x/y` without a
second offset. All object transforms are applied on export.

The wall, opening, floor, and ceiling dimensions follow `SimSpace.PROFILE` rather than inventing a
second spatial contract:

- Wall and top cap: 0.00–2.55 m.
- Open-door lintel: 2.20–2.55 m.
- Window sill and lintel: 0.00–1.00 m and 2.10–2.55 m.
- Interior floor finish: 0.004 m above the collision floor to avoid z-fighting.
- Ceiling finish: 2.545 m, immediately below the wall top.

The whole shell, including 0.30 m eaves, fascia, barge boards, and chimney, is 9.71 m wide, 4.27 m
high, and 7.61 m deep. Its minimum corner is `(-0.355, 0.000, -0.305)` relative to the template.
Roof geometry is presentation above the one-floor contract, not walkable space.

The prototype deliberately keeps the whole-tile wall footprint. Exterior and interior faces are
separate surfaces, with a top cap over the cavity. Door and window reveals are consequently still
1 m deep; making those reveals 0.10–0.15 m requires a sim spatial migration, not another mesh. The
dark inner opening frames occupy 35 mm at each edge. They are trim, not a claim that the sim's
aperture or movement footprint has changed. Windows remain open apertures: no glass or curtain
blocks a sightline the sim says is clear.

## Atlas and modelling conventions

`buildings_atlas.png` is 512 × 512 px, an 8 × 8 m atlas at **64 texels per metre**. UVs are split at
metre boundaries so every face retains that density and neighbouring patterns do not bleed. The GLB
embeds the same atlas and explicitly requests nearest magnification; the runtime adds mipmapped
nearest filtering for distance. All four object groups share one `BuildingsAtlas` material:

- `walls_and_openings`: two-sided wall finishes, cavity caps, foundation, skirting, and trim.
- `interior_floors`: worn boards in the left room and faded lino in the right room.
- `ceiling`: a separate downward-facing plaster surface.
- `roof_and_gables`: shingle planes, siding gables, fascia, barge boards, and brick chimney.

The palette is deliberately restrained: faded sage siding, warm grey plaster, aged cream trim,
brown floor boards, charcoal-brown shingles, and dark stained opening frames. Wear is sparse and
low contrast; siding courses are 0.125 m and floor boards are 0.125 m wide. The source artwork is
generated from fixed formulae and contains no downloaded or copied texture pixels.
