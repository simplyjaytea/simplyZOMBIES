# First-person weapon kit

The service pistol's receiver with a socket for each of its ten slots, its six default parts
and three alternatives, and four whole melee weapons with a socket line for later parts. All
of it shares one pixel atlas. The builder is the source. The GLBs, the atlas and the manifest
are its outputs, and the game reads only those outputs.

This is art piece 1 of the weapon plan: the socket contract, and the first models built to
it. Nothing in the game reads these files yet. The assembler that reads the manifest is a
separate code piece.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py
blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py -- --check
blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py -- --prove
```

**The rebuild** writes these files:

- `godot/assets/first_person/weapons.manifest.json`
- `godot/assets/first_person/weapons/weapons_atlas.png`
- 14 GLBs in the same folder.

It then runs the checks on what it wrote. Every pattern comes from integer hashes, fixed seeds
and fixed formulae, so the rebuild is byte-identical. `-- --out <folder>` builds somewhere
else, for a look without touching the repository. No `.blend` file is kept, because a `.blend`
is not byte-reproducible.

**`--check`** builds into a temporary folder and judges every file there. It prints
`WEAPONS_CHECK_OK`, or `WEAPONS_CHECK_FAIL: <reason>` and exits 1. It checks:

- **Bounds.** Each model's mesh bounds are within 1 cm of the `sizeM` the manifest declares. The
  declared sizes are real-world sizes, written by hand in `MODELS`. They are not read back from
  the geometry.
- **Sockets.** Every socket the manifest names exists in the GLB as an empty node, inside the
  model's bounds (1 mm of slack). The GLB holds no `socket_*` node the manifest does not name,
  and no grip node but `grip_r` and `grip_l`.
- **Content.**
  - An item that declares `slots` in `godot/content/items` has exactly one socket per slot, no
    more and no fewer.
  - Every `match` id is a real item.
  - Each part fits the slot it is assembled into (`attachment.fits`).
  - The receiver's default assembly equals the item's `defaultParts`.
- **Origins.**
  - A held model's `grip_r` sits at its origin.
  - A part's origin is its attach point: it lies on the part, within 1 mm of the part's bounds.
- **Material.** Each model has one material, which is single-sided, samples only
  `weapons_atlas`, and uses NEAREST magnification with nearest mipmaps.
- **Winding.** Every triangle agrees with its exported normal, and no edge is wound the same way
  by both of its faces.
- **No coplanar faces.** No two same-facing triangles lie within 0.2 mm of one plane with
  overlapping area. This is checked within each model, and also across every assembly: the
  receiver plus each part placed at its socket.
- **Texel density.** Every triangle is within 25% of its model's declared density. Every
  triangle samples exactly one atlas region, and every region is sampled by some model.
- **Assembly.**
  - Each part placed at its socket touches a piece of the receiver (1 mm of slack). No part
    floats.
  - The barrel's own `socket_muzzle`, carried through `socket_barrel`, lands within 1 mm of the
    receiver's `socket_muzzle`.
- **Shading.** Each triangle in the GLB is traced to the built face that holds its corners, and
  its normals are judged as the file stores them.
  - A lathe's faces are smooth round each ring: at every ring vertex, the corners of the faces
    of one band agree within 0.5 degrees, and neighbouring vertices round a ring turn by no
    more than the ring step (30 degrees at 12 segments) or, on the axe's oval haft, by no more
    than the facets beside them turn, with 0.5 degrees of slack. Where the profile turns by
    more than 30 degrees (a shoulder, a cap, a muzzle face), the builder keeps a hard edge.
  - Every other face is flat: its corners agree within 0.05 degrees. A box, a slide or a
    magazine exports exactly the normals it had before lathes were smoothed.
- **Bytes.** All 16 outputs rebuild byte-identical to the committed files.

**`--prove`** shows that each check can fail. It plants one error per build: a size 2 cm off, a
misnamed socket, a slot with no socket, a misspelt id, a part shifted off its origin, an optic
lifted off the slide, a muzzle socket 3 mm out, a second material, a double-sided material,
linear filtering, one face wound backwards, a coplanar decal face, a flush extractor, a squashed
unwrap, lathes exported with their face normals (`flat_lathe`), the barrel's hood smoothed
(`smooth_box`), and a flipped byte. It prints `PLANT <name> CAUGHT: <message>` for each, then
`WEAPONS_PROVE_OK`. If any planted error passes, it prints `WEAPONS_CHECK_FAIL` instead.

CI has no Blender, so these checks run by hand, as the starter kit's do.

## Spatial conventions

- glTF 2.0 binary, in metres, +Y up, forward -Z. A barrel points -Z.
- The builder writes every coordinate in the game's frame (+X right, +Y up, -Z forward) and
  converts to Blender's Z-up frame only when it makes the objects. A number in the builder is the
  number Godot sees.
- Mesh vertices carry the final geometry. Each GLB has one mesh node with an identity transform,
  and its sockets and grips are child nodes.
- **Held pose** (every model in this kit):
  - The origin is `grip_r`, where the right hand closes.
  - A firearm's bore runs along -Z with the sights on +Y.
  - A melee weapon's haft runs along Z, with the striking end toward -Z and the working edge
    toward -Y.
  - A two-handed weapon also carries `grip_l` for the support hand.
- **World pose** (`"pose": "world"`, used by world props in other kits): the model lies on the
  floor with its origin at its bottom centre. To put a held model on the floor, roll it onto a
  side and lift it by its lowest point. A later piece may add world-pose GLBs.

## The socket contract

- **Names.** A socket is an empty node named exactly `socket_<slot>`, where `<slot>` is the slot
  name the sim uses (`optic`, `barrel`, `muzzle`, `magazine`, `furniture`, `internal`, `spring`,
  `sear`, `extractor`, `underbarrel`; for melee, `head`, `edge`, `haft`, `wrap`, `stud`, `guard`,
  `weight`). The hands are `grip_r` and `grip_l`. The art lead's draft spelled sockets
  `socket.optic`, but Godot does not allow `.` in a node name, so the underscore form is the
  contract.
- **A socket is a transform.** Its position is the attach point. Its rotation is the frame the
  part is authored in.
  - Most sockets have an identity rotation.
  - `socket_magazine` and `socket_furniture` on the pistol, and `grip_r`, carry the grip's
    20° rake. A magazine is therefore modelled straight, with +Y up into the well and -Z toward
    the front.
- **A part's origin is its attach point.** Parent the part's scene under the socket node with an
  identity transform, and it fits. The check holds every part this way:
  - its origin on its own geometry;
  - touching the receiver once placed;
  - no face coplanar with the receiver or another part.
- **A part can carry sockets.** The barrel carries `socket_muzzle` at its crown. An assembler
  puts a muzzle device on the installed barrel's `socket_muzzle` when there is one, and on the
  receiver's otherwise. With the standard barrel the two are the same point, which the check
  proves. A longer or shorter barrel moves its muzzle device with it.
- **Absent is absent.** The assembler draws only the parts the sim has installed. A missing part
  is not replaced by its default model. Internal parts (`internal`, `spring`, `sear`) sit inside
  the receiver's shell, out of sight, ready for a bench cutaway. The extractor is visible on the
  slide's right side.
- **Melee sockets mark stations.** A socket on the haft line (`socket_head`, `socket_edge`,
  `socket_haft`, `socket_wrap`, `socket_stud`, `socket_weight`) lies on the weapon's axis at the
  point where that part goes. The melee models here are whole. The fire axe's model already draws
  its default head and haft, so an assembler must not add the `defaultParts` head and haft on
  top of it. Separate melee part models are art piece 6.

### The manifest

`godot/assets/first_person/weapons.manifest.json` uses the format the loot-item kits share:

```json
{"kit": "weapons", "models": [{"match": {"id": "<item id>"}, "glb": "res://assets/first_person/weapons/<file>.glb",
  "pose": "held", "sockets": {"<slot>": "socket_<slot>"}, "grip": "grip_r", "sizeM": [x, y, z]}]}
```

- Receivers and melee weapons list a socket for every slot the item declares.
- Parts list only the sockets they carry (the barrel lists `muzzle`).
- `grip` appears on held weapons and is left out on parts.

**One limit of the format.** `match` is an item id or class, and the sim's standard parts
(`item.part.barrel.standard` and the rest) are shared by every receiver. The part GLBs here
are drawn at pistol scale, which is why their file names start with `pistol_`. When a second
receiver lands (art piece 2), the manifest needs a match keyed by receiver as well as part id.
Which key is the coordinator's call, because the format is shared.

## The models

| File | Item | Size X x Y x Z (m) | Sockets |
|---|---|---|---|
| `pistol_service` | `item.pistol.service` | 0.029 x 0.138 x 0.192 | all ten slots, `grip_r` |
| `pistol_barrel_standard` | `item.part.barrel.standard` | 0.016 x 0.0195 x 0.1145 | `socket_muzzle` |
| `pistol_magazine_standard` | `item.part.magazine.standard` | 0.0256 x 0.100 x 0.0375 | |
| `pistol_action_standard` | `item.part.action.standard` | 0.011 x 0.0105 x 0.055 | |
| `pistol_spring_standard` | `item.part.spring.standard` | 0.0056 x 0.0056 x 0.082 | |
| `pistol_sear_standard` | `item.part.sear.standard` | 0.006 x 0.0085 x 0.013 | |
| `pistol_extractor_standard` | `item.part.extractor.standard` | 0.001 x 0.0044 x 0.019 | |
| `pistol_suppressor` | `item.attach.suppressor` (muzzle) | 0.0324 x 0.0324 x 0.149 | |
| `pistol_optic_red_dot` | `item.attach.optic.red_dot` (optic) | 0.022 x 0.0215 x 0.032 | |
| `pistol_magazine_extended` | `item.attach.magazine.extended` (magazine) | 0.0256 x 0.1345 x 0.0375 | |
| `bat_wood` | `item.bat.wood` | 0.066 x 0.066 x 0.840 | stud, weight, wrap; `grip_r`, `grip_l` |
| `knife_kitchen` | `item.knife.kitchen` | 0.019 x 0.046 x 0.322 | edge, wrap; `grip_r` |
| `crowbar_steel` | `item.crowbar.steel` | 0.0275 x 0.102 x 0.600 | weight, wrap; `grip_r` |
| `axe_fire` | `item.axe.fire` | 0.034 x 0.334 x 0.910 | head, haft, wrap; `grip_r`, `grip_l` |

**The pistol.**

- It is a generic polymer-framed service pistol, 192 mm long.
- The slide is built in three sections so that the ejection port is a real opening. The
  barrel's hood shows through it.
- The frame has an open trigger guard, a short accessory rail, and slide-stop, takedown and
  magazine-release tabs.
- The default assembly is 1,430 triangles. 1,106 of them are in the receiver, barrel, magazine
  and extractor. The other 324 are hidden internals, 276 of them the recoil spring (212 in its
  coil, 64 in its guide rod), which is kept for a bench cutaway. With the suppressor, red dot
  and extended magazine the assembly is 2,002 triangles.

**The melee weapons.**

- The bat is an ash lathe with a knob and a cupped end.
- The knife has a ground bevel, a full tang and riveted scales.
- The crowbar is a hexagonal bar swept into a gooseneck. Its chisel end and claw are flattened.
- The fire axe has an oval hickory haft, a red head with a ground edge, and a pick.

**Shading.** Every lathe (the bat, the axe's haft, the barrel's tube, the suppressor, the
recoil spring's guide rod, the optic's battery cap and the knife's rivets) carries smoothed
corner normals, so it reads round at 8 or 12 segments. Everything else is flat-shaded. The
smoothed normals are written as Blender's `custom_normal` corner attribute, which the glTF
exporter carries into the file; the triangle and vertex counts are unchanged by them.

## What horde use costs

Measured on the rebuilt GLBs (the `MODEL` and `ASSEMBLY` lines `--check` prints). Every GLB is
one mesh with one primitive, so each model is one draw.

- A default pistol is 1,430 triangles in 7 meshes: the receiver, barrel, standard magazine,
  action, recoil spring, sear and extractor. 324 of those triangles are hidden inside the
  receiver: the recoil spring's 276 (212 in its coil), the action's 24 and the sear's 24.
- The alternate assembly, with the suppressor, red dot and extended magazine, is 2,002
  triangles in 9 meshes.
- The melee weapons are one mesh each: the bat 408 triangles, the knife 540, the crowbar 260 and
  the axe 420.

A pistol is cheap for the player's hands and dear for a crowd. An NPC that carries one in
numbers, such as a raider band, should skip the hidden internals outside a bench view, which
saves 324 triangles and 3 draws a pistol, or use a merged world LOD of one mesh and one draw.
That LOD is not built yet.

## Atlas, densities and look

`weapons/weapons_atlas.png` is 512 x 512 px. Its layout:

- Fifteen regions of 128 px square, each one metre at 128 texels per metre.
- Four regions of 64 px: glass, bore, and two end grains.

Every region is sampled by some model, and the check fails if one is not. Each GLB embeds its
own copy of the atlas, which is the starter kit's arrangement. The PNG is 84 to 115 KB: its
pixels are fixed, but its deflate stream depends on the zlib Blender is linked against (stock
zlib or zlib-ng), so the byte check holds on one machine's Blender, not across builds of it.

**Densities.**

- **128 texels per metre** is the plan's allowance for close-up hand-held surfaces. This kit uses
  it on every surface a held weapon shows: the receiver, barrel, magazines, extractor,
  suppressor, optic and all four melee weapons.
- **64 texels per metre** is the world density. It is used on the three parts the receiver
  hides: the action, the recoil spring and the sear.
- One texel is 7.8 mm at 128 per metre. The pistol's side is about 24 x 17 texels, so geometry
  carries the detail and the texture carries the material.

**Unwrapping.**

- A flat face is projected onto its own plane at the exact density.
- An extruded side unwraps continuously around its profile.
- A lathe (bat, haft, barrel, suppressor) gives each facet its own column, so a taper never
  shears the grain.
- A face that the continuous unwrap would stretch by more than 15% is mapped on its own, with v
  kept along the part's length.
- Each group of faces samples its region at an offset hashed from its model and name. So no two
  parts show the same patch, and nothing repeats at a mesh or cell boundary.

**Wear follows the geometry, not the atlas cells.**

- On the slide, the chamfers, the end bevels and the inside of the ejection port are mapped to a
  lighter worn-edge steel.
- The axe's edge bevel and the knife's ground bevel are bright ground steel.
- The crowbar's chisel end is bare steel, and its claw is rusted.
- The bat's handle is the paler, grimed ash "worn pale where the hands go" from its description.
  Its barrel carries dents and dark dried stains.

**The texture.** The regions are smooth value noise thresholded into three tones of a five-tone
ramp. That gives soft blobs, not blocks. On top of the noise sit sparse scratches, chips and
pits. Wood grain runs along each part's length, bent by smooth warp noise. It never steps by
columns, and it never forms a figure.

**The palette.** Muted ramps, a few tones each:

- Blued steel: `#262a2f`, `#2e3338`, `#373c41`, `#42474b`, `#555a5b`.
- Polymer: `#242527`, `#2b2c2e`, `#333436`, `#3c3d3f`, `#48494a`.
- Fire-axe red: `#3f1814`, `#55201a`, `#6a2a20`, `#7e3628`, `#8e4533`.
- Ash: `#5f5444`, `#736755`, `#877a65`, `#9a8c74`, `#ab9c83`.
- Hickory: `#3f2c1d`, `#533b28`, `#684b33`, `#7c5c40`, `#8e6d4e`.

The full set is `PALETTE` in the builder. Everything is original: there is no downloaded,
copied or traced source.

## Adding a receiver or a part

1. **Write a builder function** that returns a `Model`, at the density it is drawn at. Use the
   helpers:
   - `cbox`: a chamfered box;
   - `xbox` / `extrude`: a profile swept along an axis, with end bevels;
   - `lathe`: a turned part;
   - `sweep`: a bar along a path;
   - `slab`: a flat, tapered blade.

   A receiver may be drawn in any convenient frame. It ends with `m.finish(-grip)`, so that
   `grip_r` lands on the origin. A part is drawn with its attach point at the origin, in its
   socket's frame.
2. **Declare the sockets** in `m.sockets`, one `socket_<slot>` per slot the content gives the
   item. Rotate a socket only when the part's natural frame is rotated, as a raked magazine well
   is.
3. **Add a row to `MODELS`.** Give it the file stem, the builder, the `match`, its kind
   (`receiver`, `part` or `melee`), its real-world size, and its slot-to-socket map. Name hidden
   internals in `DENSITY` if they use 64.
4. **Add the assemblies** to `ASSEMBLIES`, if it is a receiver: its content `defaultParts` as
   `default`, plus whatever alternates you need to prove. Each part is placed, contact-tested and
   checked for coplanar faces in each assembly.
5. **Keep pieces apart.** Overlapping pieces must not share a face plane. Sink an attached piece
   0.5 mm into what it sits on. Inset or proud a face by at least 0.4 mm from any face it would
   otherwise lie on.
6. **Rebuild, then run `-- --check` and `-- --prove`, and commit the outputs with the builder.**
