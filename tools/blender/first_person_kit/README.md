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

`survivor.glb` is an organic, smooth-skinned woman under a painted pixel atlas
(`survivor_atlas.png`); `shambler.glb` is still the low-poly rigid-weighted box body on
`characters_atlas.png`. Both have fluid in-place animation. The GLBs are runtime assets; Godot
does not need Blender or this source folder. The survivor is built by `organic_survivor.py`,
called from `build_characters.py`.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py -- --check
```

The builder writes both GLBs, `characters_atlas.png`, `survivor_atlas.png` and the editable
`characters.blend`.
Fixed procedural textures and animation formulae make repeated GLB and atlas exports
byte-identical. The Python builder is canonical; the Blender scene is a convenience file and is
not byte-reproducible. `--check` rebuilds in a temporary directory and compares only the GLBs
and atlas byte-for-byte with the committed assets, deliberately skipping `characters.blend`.
Any failure exits non-zero and prints `CHARACTER_CHECK_FAIL`, with every failed check tagged.

What the build checks, on the exported GLBs and on the evaluated, skinned mesh frame by frame:

- **Shape and export:** height within 2 cm, feet-centred origins, the 0.30 m idle radius,
  200-1500 triangles for the shambler and 1000-8000 for the survivor, one single-sided atlas
  material with nearest magnification, an armature, exact clip names and durations, seamless
  loop endpoints, changed non-loop end poses. The survivor must also have blended (two or more
  bone) weights on at least 25% of its vertices.
- **Texel density (`density`):** every triangle is measured from its real UVs and positions (the
  singular values of its UV mapping) in the exported GLB. Shambler: both axes 64 px/m +/-25% on
  every triangle, end caps included. Survivor (revised, see below): at least 85% of the surface
  area within 0.6-1.67x its island's authored density on both axes, with the 128 px/m body and
  256 px/m head bands both present.
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
| `cap-density` | end caps stretched over a whole 64 px cell, as in round 2; the survivor's islands drawn at 0.35x density | `density` |
| `arm-phase` | arm swing a quarter cycle late, as in round 2 | `arm-phase` |
| `walk-crouch` | the round-2 crouched walk pelvis (0.775 m) | `walk-height` |

Optional previews, four-view turntables, first-person-range views (0.9 m, 2 m, behind),
eight-frame contact sheets of every clip, side-view strips (locomotion travels at its speed over
a checker floor with the camera following), and side-view foot strips:

```bash
blender --background --factory-startup --python tools/blender/first_person_kit/build_characters.py -- --render-dir /absolute/scratch/renders
```

### Checks revised for the organic survivor

The box survivor's checks assumed rigid weights, box end caps and a 1500-triangle cap. These
were revised in the open, for the survivor only; the shambler keeps every original check.

- **Triangle budget:** 1000-8000 (the owner's budget for the organic body), was 200-1500.
- **Height:** the 1.75 m contract is the survivor's skull crown (the head with its hair mass),
  checked within 2 cm in the build (`[height]`); the bun and loose locks may rise up to 9 cm
  above it, so the exported total height is allowed 1.73-1.84 m. The eye stays at about 1.62 m
  (the walk's eye check, 1.58-1.62 m, is unchanged), and nothing is rescaled.
- **Texel density:** the per-triangle 64 px/m +/-25% rule cannot hold on a smooth body painted
  on cylindrical islands: the islands pinch at their poles (the crown under the hair, boot
  soles, finger ends). The rule is now area-weighted against each island's own authored density
  (above), so a global drop is still refused: drawn at 0.35x, the survivor has under 20% of its
  surface at density and is refused. (In the `cap-density` plant run, the shambler's atlas
  check, which runs earlier in the same build, refuses first.)
- **Weights:** rigid one-bone weights are replaced by blended weights across every joint, and
  the export checks that they are blended.
- **Death:** the survivor's seat and back are round, so rolling about a fixed box edge dug 2 cm
  into the floor and slid. Its held pose now lies back a fixed 86 degrees (`SURVIVOR_LIE`) with
  spine, neck and arms solved after the body settles onto its lowest point, and each frame is
  settled onto the floor and pivots on the vertex already touching it (`roll_death_frame`). The
  knees finish falling out before the seat lands. The `death-parts`, `death-centroid`,
  `death-slide` and `floor` checks themselves are unchanged and pass.

## Proportions and conventions

- glTF 2.0 binary, metres, +Y up, facing Godot -Z, origin between the soles.
- Survivor: 1.75 m skull crown with the bun rising to about 1.83 m, approximately 1.62 m eye height, an adult woman about
  7.5 heads tall in a fitted base layer (long-sleeve top, work trousers, boots) close to the body
  so clothing can sit over it later. The face, freckles and scar are painted, not modelled.
- Shambler: the same base proportions with a hunched spine, asymmetric shoulders, torn work
  clothes, a bare bitten forearm, an uneven dragging gait, 1.65 m crown, approximately 1.45 m
  eye height, and sickly skin.
- Both idle meshes stay inside the 0.30 m body-cylinder radius. The measured maxima are about
  0.297 m for the survivor and 0.298 m for the shambler. Animation poses may leave that idle
  cylinder, as a lunge or fall naturally does.
- The survivor has about 7,500 triangles and one single-sided `SurvivorAtlas` material; the
  shambler has 424 and one `CharacterAtlas` material, with tapered head/torso, shaped hair,
  collar, a simple nose/brow, and exactly two geometric eyes.
- The trouser legs run down over the boot tops, so the rigid shin never stands proud of the boot
  as the ankle flexes; the boot's toe and laces show in front of the hem.

## The survivor's body, hair and atlas

The body is a union of labelled anatomical primitives (a lofted torso with hips, waist, ribcage
and sloped shoulders; a head loft from chin to crown with nose, brow, lips, chin and ears; tubes
for neck and limbs; ellipsoids for deltoids, bust, seat, hands and thumbs; lofted boots). A voxel
remesh fuses them into one closed surface, which is relaxed, given eye sockets and decimated to
budget. The neckline, jaw, waist hem, seat line, cuffs and boot tops are then cut as edge loops,
so a painted material border is a straight line. Each face is assigned to the primitive it came
from, which keeps hands, hips and arms apart where they nearly touch. Smooth normals throughout.

Hair is broad, chunky clumps laid on the head surface with volume off the scalp, their normals
leaning out from the head so each shades as one soft mass (bangs swept
across the forehead from a part on her left, face-framing clumps past the cheekbones, the crown
swept back, the back gathered up from the nape, a few thin flyaways) and a big messy bun high on
the crown-back (a core, five loops and two escaping strands), all weighted to the head.

`survivor_atlas.png` is 512 x 512: head and neck at 256 px/m, body at 128 px/m, hair locks at
their own tapered density. The island rectangles are frozen from UV layout v2
(`organic_survivor.FROZEN`), so the painted source keeps its registration while the mesh changes;
an island whose new extent no longer fits is refitted into its rectangle and reported in the build
log. The paint is authored separately and committed as `survivor_paint.png`; the builder writes
it into the atlas unchanged and byte-reproducibly. With no paint present, flat placeholder
colours are used. `--uv-layout-dir` writes `uv_layout.png`/`.json` (wireframe, rectangles, face
landmarks) and `uv_position.png` for the painter. `--render-dir` writes the review views (full
body front, back, three-quarter and profile, four head views, first-person ranges at 0.9, 2 and
5 m) and a sheet beside the owner's concept, which is read only for that sheet and never enters an
asset; add `--clay` for untextured grey renders.

## The shambler's atlas and wear

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
upper arm, forearm, hand, thigh, shin, and foot (the ankle). The shambler's mesh parts have rigid
one-bone weights, which keeps the low-poly silhouette stable and the horde inexpensive. The
survivor's weights blend two or three bones across every joint (shoulder, elbow, wrist, spine,
neck, hip, knee, ankle), set from each vertex's anatomical part and height; the seat is shared
between both thighs at the midline. The survivor's arms are longer than the box body's, with
the hands at mid-thigh. `characters.blend`
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
