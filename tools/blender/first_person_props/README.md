# First-person prop kit A

Original street dressing for the Kagase valley: two vending-machine liveries, a utility pole,
four concrete-block wall pieces, two guard-rail pieces, a portable bus stop, a noren, a wall-hung
fire-extinguisher box and a mamachari bicycle. The 13 GLBs share one 512 x 512 procedural pixel
atlas. They are review assets only until the district prop placer lands; this kit adds no game
code, collision, entities or loot.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_props/build_props.py
blender --background --factory-startup --python tools/blender/first_person_props/build_props.py -- --check
```

The builder writes:

- `godot/assets/first_person/props/*.glb`;
- `godot/assets/first_person/props/props_atlas.png`;
- `godot/assets/first_person/props.manifest.json`;
- `props.blend`, an editable convenience scene that is not byte-reproducible.

`--check` rebuilds in a temporary directory and judges the exported GLBs. It prints one measured
`PROP` line per model and ends with `PROPS_CHECK_OK 13 models`. GLBs, the atlas and the manifest
must be byte-identical to the committed outputs. Any failure exits non-zero.

The exported-GLB checks cover measured bounds against the manifest within 1 cm, floor and wall
contact, run length and matching end-profile vertices, the noren's 1.80 m minimum hem, triangle
budgets, one single-sided `PropsAtlas` material, NEAREST magnification, identity node transforms,
64 texels per metre on every triangle, and UVs confined to their 64 px atlas cells.

Every planted defect must be refused with `PROPS_PLANT_REFUSED`:

```bash
for plant in float sink size_lie run_gap noren_low tri_over two_materials; do
  blender --background --factory-startup --python tools/blender/first_person_props/build_props.py -- --plant "$plant"
done
```

The plants lift a vending machine 2 cm, sink the pole 2 cm, lie about size by 5 cm, shorten a wall
to 0.98 m, lower the noren hem to 1.60 m, put the bicycle over budget, and add a second material.

Optional 640 px front three-quarter and detail renders:

```bash
blender --background --factory-startup --python tools/blender/first_person_props/build_props.py -- --render-dir /absolute/scratch/renders
```

## Spatial and manifest conventions

- glTF 2.0 binary, metres, +Y up, Godot forward -Z. The authored front is Blender -Y.
- Mesh vertices carry final dimensions. Every exported node transform is identity.
- `kerb` and `run` models have minimum y = 0. `wall` models have their back at z = 0 and project
  toward +Z. The noren uses floor-referenced door-head coordinates.
- Wall pieces are 1 m long and guard-rail pieces 2 m, with run ends at +/-0.50 m and +/-1.00 m.
- The manifest's `size` is measured x/y/z from the exported GLB. `anchors` are named x/y/z points
  in that same space. The pole declares `wire_a`, `wire_b` and `wire_c`; no wire span is baked.
- Each model has exactly one opaque, single-sided material. Every GLB embeds the atlas, so a clean
  checkout needs no Blender installation or external texture path.

## Atlas and lettering

The atlas has 64 px cells at 64 texels per metre. Long planar surfaces split at metre boundaries;
tapered pole panels use per-triangle metric UVs. The material uses no emission. Painted wear is
restrained and deterministic: block courses are 390 x 190 mm, the wall caps are grey tile, the pole
base has a faded yellow/black sleeve, and the extinguisher box is muted red rather than a saturated
accent.

The builder embeds its small Japanese glyph masks, so rebuilding needs no font or image input.
Invented signage reads 青谷飲料 and 川灯飲料 on the vending machines, 加瀬バス at the bus stop,
加瀬電 on the pole, 風庵 on the noren, and 消火器 on the extinguisher box. No real maker or logo is
used.

## Measured models

| GLB | Placement | Size x/y/z (m) | Triangles | Budget |
|---|---|---|---:|---:|
| `vending_ao` | kerb | 1.000 x 1.830 x 0.816 | 700 | 700 |
| `vending_kawa` | kerb | 1.000 x 1.830 x 0.816 | 700 | 700 |
| `utility_pole` | kerb | 1.400 x 10.000 x 0.480 | 496 | 500 |
| `wall_block_1m` | run | 1.000 x 1.200 x 0.120 | 32 | 120 |
| `wall_block_end` | run | 1.000 x 1.200 x 0.120 | 52 | 120 |
| `wall_block_corner` | run | 1.000 x 1.200 x 0.560 | 64 | 120 |
| `wall_block_gate` | run | 1.000 x 1.200 x 0.120 | 112 | 120 |
| `guard_rail_2m` | run | 2.000 x 0.800 x 0.160 | 80 | 120 |
| `guard_rail_end` | run | 2.000 x 0.800 x 0.320 | 96 | 120 |
| `bus_stop` | kerb | 0.500 x 2.300 x 0.360 | 168 | 200 |
| `noren` | door_head | 1.000 x 0.298 x 0.036 | 52 | 80 |
| `extinguisher_box` | wall | 0.300 x 0.600 x 0.237 | 72 | 100 |
| `bicycle` | kerb | 1.846 x 0.972 x 0.480 | 868 | 900 |

The vending fronts include recessed drink dummies, a glass frame and reflection treatment, price
strip, buttons, coin slot and take-out flap. The bicycle has open tyre rings with eight thin spokes
per wheel, a front basket, rear carrier, chain guard, mudguards and a deployed stand.
