# First-person view-model arms

The player's own arms for the first-person view: the hands, the wrists and the base top's
sleeves, rigged and animated for every hold class. This is art piece 8 of docs/41 ("view-model
arms, grips, idle, sway, raise, lower, inspect").

## Contract

The base layer is bare hands; gloves are a separate layer only when the survivor wears them.
Presentation repeats the inspect clip while the player holds `L`. The view model has its own 75
degree vertical field of view, a 0.06 m near limit and must not clip through a nearby wall. Arms
and survivor bodies use 128 px/m. The 23 clips and their lengths are listed below.

The presentation code that plays the kit (`arms_view.gd`, the `ARMS` lane of
`check_first_person.gd`) is a later piece; nothing in the game on this branch reads these files
yet.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py
blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --check
blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --plant <name>
blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --render-dir <dir> --uv-layout-dir <dir>
blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --render-dir <round-2> --compare-dir <round-1>
```

The rebuild writes `godot/assets/first_person/arms/arms_base.glb`, `arms_atlas.png` and
`arms.json`, then runs every check below on what it wrote and prints each result. `--out <dir>`
builds elsewhere. `--check` builds into a temporary folder, runs the checks there, and compares
the three outputs byte for byte with the committed ones; it prints `ARMS_CHECK_OK`, or
`ARMS_CHECK_FAIL: <check>: <reason>` and exits 1. `--plant <name>` builds with one known defect and
prints `ARMS_PLANT_REFUSED` when the named checks catch it, or `ARMS_PLANT_FAIL` and exits 1.
`--render-dir` writes the review renders and five-frame idle, sway, raise, lower and inspect strips;
`--compare-dir <round-1>` adds per-class sheets with round 1 left and the new render right.
`--uv-layout-dir` writes the atlas layout. No `.blend` is kept. CI has no Blender, so these run by
hand, as the other kits' do.

The outputs live under `arms/`, not beside the `*.manifest.json` files, so `Models.manifests()`
never mistakes the arms for a loot model.

## What is in the GLB

- **Frame.** glTF binary, metres, +Y up, -Z forward. The origin is the eye: presentation parents
  the scene under `Eye` with an identity transform. A number here is a camera-space number.
- **Rest pose.** The accepted survivor's own rest arm, moved so the survivor's eye is the origin
  (the view sits 1 cm behind the painted eyes, 1.622 m up). Shoulder, elbow and wrist joints are
  read from `survivor.glb`, not chosen: the right shoulder joint is at (0.178, -0.222, 0.070).
- **Skeleton, 43 bones.** `view` (identity at the origin); per side `shoulder`, `upper_arm`,
  `forearm`, `forearm_twist` (half the wrist's roll, as the clips key it), `hand`, and
  `thumb/index/middle/ring/pinky_01..03`; and the non-deforming leaves `grip_r` (under `hand.R`)
  and `grip_l` (under `hand.L`). Arm bone names match the survivor rig, so a clothing layer weights
  by the same names. The exported `grip_r` node is the weapon frame (bore -Z, sights +Y), so a
  weapon GLB parented under it with an identity transform sits in the hand; `grip_l` matches the
  weapon's `grip_l` node.
- **Meshes.** `arms_skin` (both hands and wrists, about 1,040 triangles a hand) and `arms_sleeve`
  (the base top's sleeve, cuff to deltoid, 24 segments a ring), skinned to the one skeleton with at
  most four normalized influences. The skin reaches 35 mm up inside the sleeve. 3,712 triangles in
  all (budget 4,000). One material, `ArmsAtlas`, single-sided. The GLB sampler uses nearest
  magnification and minification (`magFilter` 9728, `minFilter` 9984), with no mipmaps.
- **Hands.** Five separately jointed digits, a thumb whose metacarpal sits in a thenar pad, a
  hypothenar pad, knuckle ridges and a wrist, fused into one surface by a voxel remesh, relaxed and
  decimated to budget. The hand is scaled so its length is the survivor's.
- **Sleeves.** Lofted through cross-sections cut from the survivor's own arm surface (wrist to
  0.40 m up the arm), so their girth is the body's. An inner lip and a bridged rim keep the cuff
  from disappearing under backface culling.

### Hold classes and anchors

| Class | Reference weapon | Hands | `grip_r` at idle (camera space) |
|---|---|---|---|
| `unarmed` | none | both low in the bottom corners, relaxed, a little open | frozen in `anchors.json` |
| `pistol` | `pistol_service.glb` | right hand high on the raked grip, index along the frame; left hand cupping the right | (0.22, -0.20, -0.45), (-6, 14, 0) deg, the contract's |
| `long` | `jig_long` (below) | right hand on the raked grip; left hand under the handguard at `grip_l` | frozen in `anchors.json` |
| `melee1` | `knife_kitchen.glb` | right fist on the handle, blade forward; the left hand below the frame | as the pistol, the contract's |
| `melee2` | `bat_wood.glb` | both fists on the haft at `grip_r` and `grip_l`, carried diagonally, striking end up and left | frozen in `anchors.json` |

The hands are solved against each reference weapon's own mesh: the palm is set on the grip and
backed off along its normal until it clears by 0.8 mm, then each finger closes joint by joint
until it meets the surface. The pistol's support wrist and wrapping-finger offsets are measured
against the right hand and grip, with its index and thumb closed against those obstacles. The arm
reaches the wrist with a two-bone solve whose elbow hangs down and out, the shoulder swinging
forward for two-handed holds. `jig_long` is the authoring-only long gun the contract asks for: grip to
foregrip 0.25 m, grip to butt 0.30 m, sight 0.07 m over the bore, with `grip_r`, `grip_l` and
`sight` points. It is never shipped; every long-gun check reruns on the real receivers when they
land. The pistol's sight is its rear sight, the highest rear point of the slide.

### Clips (60 fps, one AnimationPlayer)

| Clip | Classes | Length | Loop |
|---|---|---:|---|
| `idle_<h>` | all five | 4.0 s | yes |
| `aim_<h>` | pistol, long | 4.0 s | yes |
| `raise_<h>` | pistol, long | 0.40 s | no |
| `lower_<h>` | all five | 0.30 s | no |
| `draw_<h>` | all five | 0.50 s | no |
| `inspect_<h>` | all but unarmed | 3.0 s | no |

23 clips. Loops repeat their first pose on their last frame; consumers set `LOOP_LINEAR`. One-shots
ease with a quintic, so they start and end at rest and a phase the sim scrubs never pops. Sway is
not a clip (it follows the sim's `coneHalf`, in code).

## The atlas

`arms_atlas.png` is 256 x 256 at 128 px/m on every triangle. The sleeves are unwrapped as the
survivor's arm is (one cylinder an arm, one rear-inner seam), with separate small bands for the inner
cuff and rim. Their final paint uses charcoal texels sampled from the survivor's front and sleeve
islands, with broad normal-driven form shading and a darker cuff; it never uses the warm back or
atlas-cell noise. The hands use seam-guided anatomical palm, edge, wrist and digit charts, unwrapped
with LSCM and measured at 128 px/m +/- 25%; there is no angle-limited projection. A continuous
hand-space field paints broad dorsal, turning-edge and palm zones in the survivor's skin ramp, with
the dark tone reserved for creases and the palm edge. Conservative rasterisation fills every texel a
triangle touches, including texels whose centres lie outside it. A four-texel margin and bounded
four-texel dilation, including diagonal neighbours, keep every chart off the atlas edges without
wrapping. The layout (`uv_layout.png`, `uv_position.png`, `uv_layout.json` with islands, the fingertip
direction in each, and landmarks: knuckles, nails, thumb tips, wrist backs, cuff edges) is written by
`--uv-layout-dir`.

## What `--check` holds

Measured on the exported GLB, frame by frame at 60 fps, against the committed weapon GLBs and
`survivor.glb`.

| Check | Holds | Plant refused |
|---|---|---|
| `bytes` | GLB, atlas and `arms.json` rebuild byte-identical | `flip-byte` |
| `names` | the 43 bones, the 23 clips and their lengths; loop seams within 0.1 mm / 0.01 deg | `clip-rename`, `seam` |
| `anchor` | `grip_r` at idle frame 0 within 5 mm / 1 deg of each class's anchor, on the exported node | `bone-roll` |
| `bone-length` | upper-arm and forearm joint distances within 0.5 mm of rest on every frame; no disconnected wrist from an unreachable target | `stretch-arm` |
| `grip-land` | `grip_l` within 5 mm of the reference weapon's `grip_l` at every key pose of melee2 and long; the pistol's support hand within 5 mm of its cup pose relative to `hand.R` | `grip-off` |
| `wrap` | no hand vertex over 2 mm inside the weapon; gripping middle, ring and pinky pads within 4 mm of the grip, the pistol's right index within 4 mm of the frame, and its support pads within 4 mm of the right fingers or grip | `finger-through`, `support-wrap` |
| `sight-line` | at the end of `raise_*` and on every `aim_*` frame, the sight within 3 mm of the camera axis, the bore within 1 deg of -Z | `sight-off` |
| `near-plane` | every visible vertex (vertical 75 deg, up to 21:9) at least 0.06 m deep, every frame | `near-clip` |
| `stump` | the sleeve's open end out of view at 21:9, every frame | `short-arm` |
| `in-frame` | at idle and aim, 80% of the right hand in the 4:3 frame (both hands for melee2, long, unarmed); at `draw` frame 0 and the end of `lower`, both hands below the bottom edge | `hand-out` |
| `chain` | each one-shot's joined poses agree in position and rotation, and it starts and ends at translational and rotational rest | `pop`, `rotation-pop` |
| `smooth` | no joint's angular speed jumps more than 3x between frames | `pop` |
| `weights` | four normalized influences at most; every vertex within 3 cm of the elbow or wrist has two; a 60 deg wrist twist keeps 70% of the forearm's section | `rigid-wrist` |
| `cuff` | the sleeve overlaps the skin by 3 mm at every frame, and the inner lip has a measured, non-empty skin band with no gap over 3.5 mm | `cuff-gap` |
| `density` | every triangle has a finite UV Jacobian at 128 px/m +/- 25% on both axes, in Blender and in the GLB; degenerates fail | `squash-uv` |
| `background` | no skin or sleeve triangle's complete UV footprint touches an atlas-background texel | `subtexel-island` |
| `paint-match` | sleeves use only the survivor's charcoal front/sleeve ramp; skin uses only the survivor's skin ramp; no dark atlas-cell checker; every island has 4 px of non-background padding | `repaint`, `paint-cells`, `short-padding` |
| `body-match` | hand length, wrist and forearm girth and shoulder-to-wrist within 3 mm of `survivor.glb` in rest | `fat-wrist` |
| `budget` | at most 4,000 triangles, 1,100 a hand; one single-sided, nearest-filtered material | `second-material`, `linear` |

How the contract's wording is read, where it needed a number:

- **"Zero velocity at the ends"** (`chain`): the first and last translation steps are under 5% of
  the clip's largest step, and rotation steps under 10% (the two-bone solve amplifies the quintic's
  start a little). Joined poses agree within 1 mm and 0.2 deg. A pop at the end of a clip fails it.
- **"3x jump"** (`smooth`): judged against speeds that matter. A joint easing in or out of rest,
  below a quarter of its own peak speed in the clip or 0.3 rad/s, may change speed faster; a quintic
  ease otherwise changes speed 7x across its last two frames by construction.
- **"Pads"** (`wrap`): the distal phalanx of the middle, ring and pinky fingers of every hand that
  holds the weapon. The pistol's support pads are measured against the actual right-finger surface
  or the grip, not exempted by the cup pose. The right trigger finger's distal phalanx is measured
  against the frame above the trigger guard.
- **The wrist twist** (`weights`): the hand turned 60 deg about the forearm with the twist bone
  carrying half, as the clips key it; the sleeve's section 1.2 cm and 3 cm above the wrist.
- **Wrist girth** (`body-match`) is measured 2 mm above the cuff edge, where both surfaces are the
  sleeve's; forearm girth 15.4 cm above the wrist.
