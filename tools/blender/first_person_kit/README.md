# First-person Blender starter kit

Five original low-poly props share one procedural pixel-art atlas. The exported GLBs are
runtime assets; Godot does not need Blender or this source folder.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_kit.py
blender --background --factory-startup --python tools/blender/first_person_kit/build_kit.py -- --check
```

The rebuild writes `kit.blend`, `kit_atlas.png`, and all five GLBs. It uses fixed procedural
patterns and no external inputs, so repeated exports are byte-identical. `--check` builds in
a temporary directory, checks every exported bounding box within 1 cm, checks origins and
single-material atlas use, requires nearest magnification filtering, and compares the GLBs
and atlas byte-for-byte with the committed assets. It exits non-zero on any failure.

Optional 512 px preview renders:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_kit.py -- --render-dir /absolute/scratch/renders
```

## Spatial conventions

- glTF 2.0 binary, metres, +Y up, Godot forward -Z.
- Blender authors X width, Y depth, Z height; the exporter performs the +Y-up conversion.
- Mesh vertices carry the final dimensions and every exported object transform is identity.
- Desk, shelf, barricade, and wall origins are floor-centre. The ledger origin is bottom-centre
  for direct placement on the 0.78 m desk top.
- Wall side faces are at X = +/-0.50 m, so copies at one-metre X intervals tile without overlap.

| Prop | X width (m) | Y height (m) | Z depth (m) |
|---|---:|---:|---:|
| desk | 1.20 | 0.78 | 0.62 |
| ledger | 0.30 | 0.026 | 0.22 |
| shelf | 0.90 | 1.85 | 0.32 |
| barricade | 1.20 | 1.10 | 0.18 |
| wall_module | 1.00 | 2.60 | 0.12 |

Each prop is one mesh with one `KitAtlas` material. `kit.blend` keeps the five meshes separate
and editable, arranged in a row. The GLBs are exported before that presentation offset.

## Atlas and palette

`godot/assets/first_person/kit_atlas.png` is 256 x 256 px, representing 4 x 4 m at **64 texels
per metre**. UVs preserve that density on every face. One-metre atlas cells repeat at mesh
boundaries rather than stretching or crossing into neighbouring cells. Use NEAREST filtering;
the GLB sampler explicitly requests nearest magnification.

The atlas contains horizontal oak grain, dark timber, chipped sage paint, stained cracked
plaster, ruled paper, paper edges, worn leather, and oxidised metal. Its muted base tones are:

- Oak: `#342d27`, `#4a3c30`, `#62503e`, `#78634b`, `#8b7558`.
- Dark timber: `#242526`, `#34302c`, `#463a30`, `#5b4938`, `#6c5640`.
- Chipped paint: `#303a36`, `#46534a`, `#5c6858`, `#747865`, `#8a8972`.
- Plaster: `#44453f`, `#585950`, `#6b6b60`, `#7d7a6c`, `#8e8877`.
- Paper: `#766e58`, `#94896b`, `#aca17e`, `#c0b38d`, `#cec29c`.
- Leather: `#2b2625`, `#3c302b`, `#513d31`, `#654b39`, `#795a42`.
- Metal: `#25292a`, `#363b3b`, `#4b504d`, `#62665e`, `#7a796b`.

The builder creates the atlas and all wear patterns from integer hashes and fixed formulae.
There is no downloaded, copied, or randomly seeded source artwork.
