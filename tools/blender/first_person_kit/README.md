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
patterns and no external inputs, so repeated GLB and atlas exports are byte-identical. The
Python builder is the canonical editable source; Blender's `kit.blend` is a convenience scene,
not a byte-reproducible file. `--check` builds in a temporary directory, checks every exported
bounding box within 1 cm, checks origins, single-sided single-material atlas use, and nearest
magnification filtering, and compares only the GLBs and atlas byte-for-byte with the committed
assets. It deliberately skips `kit.blend`. Any failure exits non-zero.

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
boundaries rather than stretching or crossing into neighbouring cells. Three plaster variants
break up vertical repetition, three oak variants distinguish neighbouring boards, and vertical
members rotate the grain UVs. Use NEAREST filtering; the GLB sampler explicitly requests nearest
magnification.

The standalone PNG is the canonical atlas for review and rebuild comparison. Each GLB embeds a
self-contained copy for its material, so the game reads those embedded textures rather than the
standalone PNG. The atlas contains oak grain, dark timber, edge-chipped sage paint, subdued
plaster wear, ruled paper, paper edges, worn leather, and oxidised metal. Its muted base tones are:

- Oak: `#342d27`, `#4a3c30`, `#62503e`, `#78634b`, `#8b7558`.
- Dark timber: `#242526`, `#34302c`, `#463a30`, `#5b4938`, `#6c5640`.
- Chipped paint: `#303a36`, `#46534a`, `#5c6858`, `#747865`, `#8a8972`.
- Plaster: `#44453f`, `#585950`, `#6b6b60`, `#7d7a6c`, `#8e8877`.
- Paper: `#766e58`, `#94896b`, `#aca17e`, `#c0b38d`, `#cec29c`.
- Leather: `#2b2625`, `#3c302b`, `#513d31`, `#654b39`, `#795a42`.
- Metal: `#25292a`, `#363b3b`, `#4b504d`, `#62665e`, `#7a796b`.

The builder creates the atlas and all wear patterns from integer hashes and fixed formulae.
There is no downloaded, copied, or randomly seeded source artwork.


# First-person character kit

`survivor.glb` and `shambler.glb` are original low-poly people with rigid-weighted armatures,
fluid in-place animation, and one shared pixel-art atlas. The GLBs are runtime assets; Godot
does not need Blender or this source folder.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py -- --check
```

The builder writes both GLBs, `characters_atlas.png`, and the editable `characters.blend`.
Fixed procedural textures and animation formulae make repeated GLB and atlas exports
byte-identical. The Python builder is canonical; the Blender scene is a convenience file and is
not byte-reproducible. `--check` rebuilds in a temporary directory and compares only the GLBs
and atlas byte-for-byte with the committed assets, deliberately skipping `characters.blend`.
It also checks height within 2 cm, feet-centred origins, the 0.30 m idle radius, 200–1500
triangle budgets, one single-sided atlas material with nearest magnification, an armature,
exact animation names and durations, seamless loop endpoints, and changed non-loop end poses.
Every face is held to 64 px/m +/-25%. Per-frame evaluated-skin checks reject stance soles over
5 mm from the floor, any penetration over 5 mm, one-shot starts over 2 cm from idle, inverted
pelvis bob, same-side arm swing, crouch eyes outside 0.95 m +/-5 cm, and a death pose that does
not rest on the floor. Any failure exits non-zero.

Optional previews, four-view turntables, and eight-frame contact sheets for every clip:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py -- --render-dir /absolute/scratch/renders
```

## Proportions and conventions

- glTF 2.0 binary, metres, +Y up, facing Godot -Z, origin between the soles.
- Survivor: 1.75 m crown, approximately 1.62 m eye height, adult work-jacket/trouser/boot
  proportions, and only a few pixels of facial detail.
- Shambler: the same base proportions with a hunched spine, asymmetric shoulders, torn work
  clothes, an uneven dragging gait, 1.65 m crown, approximately 1.45 m eye height, and sickly skin.
- Both idle meshes stay inside the 0.30 m body-cylinder radius. The measured maxima are about
  0.297 m for the survivor and 0.298 m for the shambler. Animation poses may leave that idle
  cylinder, as a lunge or fall naturally does.
- The survivor has 412 triangles and the shambler 424, each with one single-sided
  `CharacterAtlas` material. Tapered heads/torsos, shaped hair, collars, plain fabric, a simple
  nose/brow, and exactly two geometric eyes replace the earlier box construction.

The 256 x 256 atlas uses **64 texels per metre everywhere**, including faces and hands. Every
face is UV-mapped from its physical dimensions and takes a different crop, rather than stretching
one cell or repeating one wear stamp. Palette ramps cover plain workwear, charcoal trousers,
dark boots, muted skin, sickly skin, and hair. Use NEAREST or NEAREST_WITH_MIPMAPS filtering.
All pixels and wear patterns are generated by the builder.

## Rig

Each character has an 18-bone armature: root, pelvis, spine, chest, neck, head, and left/right
upper arm, forearm, hand, thigh, shin, and foot (the ankle). Mesh parts have rigid one-bone
weights, which keeps the low-poly silhouette stable and the horde inexpensive. The ankle
counter-poses the shin so the sole stays flat during stance. `characters.blend` preserves both
editable rigs and all actions.

## Animation

Clips are sampled at 60 fps, giving exact contract durations. Idle uses balanced breathing;
locomotion has its pelvis lowest at double support and arms swinging with the opposite leg.
Loop actions explicitly duplicate their first pose at their last frame. The GLBs preserve the
exact clip names; Godot's name-suffix rule cannot mark these names for automatic looping, so
consumers set `Animation.LOOP_LINEAR` on `idle`, `walk`, `crouch_idle`, and `shamble`.

| Character | Clip | Duration | Intended motion |
|---|---|---:|---|
| survivor | `idle` | 2.0 s | quiet symmetrical breathing |
| survivor | `walk` | 1.0 s loop | **1.4 m/s**, 50% stance per foot |
| survivor | `crouch_idle` | 2.0 s loop | deep crouch, approximately 0.95 m eye |
| survivor | `death` | 1.5 s | knee/hip-folded crumple, held on the floor |
| shambler | `idle` | 2.4 s loop | subdued symmetrical breathing |
| shambler | `shamble` | 1.4 s loop | **0.8 m/s**, 60%/45% stance, dragging right swing |
| shambler | `lunge` | 1.0 s | idle-start two-arm lunge, held with foot contact |
| shambler | `death` | 1.7 s | knee/hip-folded crumple, held on the floor |

Walk and shamble use analytic two-bone leg poses. During each stance the ankle moves backward
in body space at exactly the locomotion speed, so a root moving forward at 1.4 or 0.8 m/s keeps
that foot planted. Swing returns the foot with smoothstep horizontal motion and a sinusoidal
lift. The pelvis bob has two equal cycles per stride.
