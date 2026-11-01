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
Any failure exits non-zero and prints `CHARACTER_CHECK_FAIL`, with every failed check tagged.

What the build checks, on the exported GLBs and on the evaluated, skinned mesh frame by frame:

- **Shape and export:** height within 2 cm, feet-centred origins, the 0.30 m idle radius,
  200-1500 triangles, one single-sided atlas material with nearest magnification, an armature,
  exact clip names and durations, seamless loop endpoints, changed non-loop end poses.
- **Texel density (`density`):** every triangle, end caps included, is measured from its real
  UVs and positions (the singular values of its UV mapping), in Blender and again in the
  exported GLB. Both axes must be 64 px/m +/-25%. Nothing is assumed.
- **Floor and feet (`floor`, `feet`):** no penetration over 5 mm; crouch and lunge soles on the
  floor; every stance sole within 5 mm of the floor; stance contact points must travel backward
  at exactly the walking speed, so at speed they hold their spot (under 1 cm per stance).
- **Gait:** pelvis lowest at double support (`bob`); the walk's eye height must stay within
  1.58-1.62 m and its pelvis above 0.82 m (`walk-height`); each hand's measured most-forward
  phase must fall within 0.05 of the opposite foot's measured heel strike, for walk and shamble
  (`arm-phase`).
- **One-shots:** each starts within 2 cm of idle (`start`); crouch eye within 0.95 m +/-5 cm
  (`crouch`).
- **Death:** in the held final pose the head, chest, pelvis and a boot must each have their
  lowest point within 3 cm of the floor (`death-parts`); the mass-weighted centroid must lie at
  least 2 cm inside the convex hull of the floor contacts (`death-centroid`); and no vertex may
  travel more than 3 cm across the floor while it stays in contact through the fall
  (`death-slide`).

Each of these death, density and gait checks has a plant mode. A plant builds with one known
defect and must be refused by the named checks. It prints `CHARACTER_PLANT_REFUSED` and exits 0
when the checks catch it, or `CHARACTER_PLANT_FAIL` and exits 1 when they do not:

```bash
for plant in death-one-boot death-slide cap-density arm-phase walk-crouch; do
  blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py -- --plant $plant
done
```

| Plant | Defect | Refused by |
|---|---|---|
| `death-one-boot` | the round-2 death: a tipped crumple settled onto its lowest vertex | `death-parts`, `death-centroid`, `death-slide` |
| `death-slide` | both planted feet drift 15 cm sideways during the fall | `death-slide` |
| `cap-density` | end caps stretched over a whole 64 px cell, as in round 2 | `density` |
| `arm-phase` | arm swing a quarter cycle late, as in round 2 | `arm-phase` |
| `walk-crouch` | the round-2 crouched walk pelvis (0.775 m) | `walk-height` |

Optional previews, four-view turntables, first-person-range views (0.9 m, 2 m, behind),
eight-frame contact sheets of every clip, side-view strips (locomotion travels at its speed over
a checker floor with the camera following), and side-view foot strips:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py -- --render-dir /absolute/scratch/renders
```

## Proportions and conventions

- glTF 2.0 binary, metres, +Y up, facing Godot -Z, origin between the soles.
- Survivor: 1.75 m crown, approximately 1.62 m eye height, adult work-jacket/trouser/boot
  proportions, and only a few pixels of facial detail.
- Shambler: the same base proportions with a hunched spine, asymmetric shoulders, torn work
  clothes, a bare bitten forearm, an uneven dragging gait, 1.65 m crown, approximately 1.45 m
  eye height, and sickly skin.
- Both idle meshes stay inside the 0.30 m body-cylinder radius. The measured maxima are about
  0.297 m for the survivor and 0.298 m for the shambler. Animation poses may leave that idle
  cylinder, as a lunge or fall naturally does.
- The survivor has 412 triangles and the shambler 424, each with one single-sided
  `CharacterAtlas` material. Tapered heads/torsos, shaped hair, collars, a simple nose/brow, and
  exactly two geometric eyes.
- The trouser legs run down over the boot tops, so the rigid shin never stands proud of the boot
  as the ankle flexes; the boot's toe and laces show in front of the hem.

## Atlas and wear

The 256 x 256 atlas is **64 texels per metre on every face, end caps included**. Each polygon is
projected onto its own plane at that density and packed into its own rectangle, so no texel is
shared between faces or bodies and nothing repeats. Because every texel knows where it sits on
the body in rest space, the wear follows the clothes, not atlas cells:

- stitched seams on real seam lines: shoulders, the jacket's side seams, sleeve and trouser
  outer seams and inseams, pockets, the survivor's front zip;
- worn, thinning fabric at the knees and elbows, with kneeling dirt below the knee;
- grime and fraying at the cuffs and the trouser hems, mud at the soles, scuffed toe caps,
  laces, a stitched welt, weather-faded shoulders, a worn trouser seat;
- a few placed stains: oil on the survivor's jacket, grease on a thigh;
- the shambler dirtier, with a ragged tide line of dirt rising from the ground, torn holes
  showing grey skin, a torn knee, dried blood at the mouth running down the chin and the jacket
  front, and a bite on its bare forearm with blood run down to the wrist.

Base tones are flat with sparse single-texel grain; there is no camouflage noise. Palette ramps
cover workwear, charcoal trousers, dark boots, muted skin, sickly skin, hair, grime, dried
blood, laces and the zip. Use NEAREST or NEAREST_WITH_MIPMAPS filtering. All pixels are
generated by the builder.

## Rig

Each character has an 18-bone armature: root, pelvis, spine, chest, neck, head, and left/right
upper arm, forearm, hand, thigh, shin, and foot (the ankle). Mesh parts have rigid one-bone
weights, which keeps the low-poly silhouette stable and the horde inexpensive. `characters.blend`
preserves both editable rigs and all actions.

## Animation

Clips are sampled at 60 fps, giving exact contract durations. Loop actions explicitly duplicate
their first pose at their last frame. The GLBs preserve the exact clip names; Godot's
name-suffix rule cannot mark these names for automatic looping, so consumers set
`Animation.LOOP_LINEAR` on `idle`, `walk`, `crouch_idle`, and `shamble`.

| Character | Clip | Duration | Intended motion |
|---|---|---:|---|
| survivor | `idle` | 2.0 s | quiet symmetrical breathing |
| survivor | `walk` | 1.0 s loop | **1.4 m/s**, 50% stance per foot, heel-to-toe roll |
| survivor | `crouch_idle` | 2.0 s loop | deep crouch, approximately 0.95 m eye |
| survivor | `death` | 1.5 s | knees buckle, sits down, rolls back, held lying on its back |
| shambler | `idle` | 2.4 s loop | subdued symmetrical breathing |
| shambler | `shamble` | 1.4 s loop | **0.8 m/s**, 60%/45% stance, dragging right swing |
| shambler | `lunge` | 1.0 s | idle-start two-arm lunge, held with foot contact |
| shambler | `death` | 1.7 s | knees buckle, sits down, rolls back, held lying on its back |

The walk stands tall: pelvis 0.83-0.85 m, eye 1.59-1.61 m. Each foot strikes heel first with
the toe up, rolls onto the flat sole, and rises onto the toe. Through all three, the contact edge
or the sole moves backward in body space at exactly the walking speed, so a root moving forward
at 1.4 m/s keeps it planted. The swing returns the foot on a Hermite curve that leaves and lands
at stance speed. The shamble keeps a flat-footed stance under the same planting rule. The pelvis
bob has two equal cycles per stride, lowest at double support. The arms swing with the opposite
leg: each hand is furthest forward at the opposite heel strike.

The death is posed against the skinned mesh. The knees buckle over planted feet, the body sits
down onto the back edge of the pelvis, and it rolls back about that edge until the back lies
flat. Before keying a frame, the builder solves the held pose: the pelvis angle that lays its
back flat, the spine angle that brings the shoulders down, the neck angle that rests the head
(turned to one side), the arm angles that lay the hands on the floor, and the knees fallen
outward. The feet never move, the pelvis edge never slides once down, and the chest, head and
hands land last.
