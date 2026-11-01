# First-person loot-item kit

The everyday things a player picks up, as world-pose GLBs that share one pixel atlas.

- **Hand-chosen models.** 24 specific models carry 80 hand-chosen item ids.
- **Size-laddered models.** Every other item of class `consumable`, `material`, `tool`,
  `container`, `armor` or `attachment` in `godot/content/items/*.json` is routed by id to the
  neutral model of its class whose size is nearest its own. That is 284 more ids.
- **Class fallbacks.** One class entry per class stays in the manifest for items added after the
  last rebuild.

Weapons (`weapon.melee`, `weapon.ranged`) belong to the weapon kit, which uses the same
manifest format.

`build_items.py` is the canonical source. `items.blend` is a convenience scene that the builder
writes. It is not byte-reproducible and `--check` does not read it. Godot needs neither file at
runtime.

## Rebuild and check

Use Blender 5.2 from the repository root:

```bash
blender --background --factory-startup --python tools/blender/first_person_items/build_items.py
blender --background --factory-startup --python tools/blender/first_person_items/build_items.py -- --check
```

A rebuild writes these files:

- `godot/assets/first_person/items/*.glb`: 32 models.
- `godot/assets/first_person/items/items_atlas.png`: the shared atlas.
- `godot/assets/first_person/items.manifest.json`: the manifest.
- `items.blend`: the convenience scene.

A rebuild runs every check below on what it wrote and prints `ITEMS_BUILD_OK`.

The manifest is generated from the item content. A new or resized item therefore changes the
rebuilt manifest, and `--check`'s `bytes` check asks for a rebuild.

`--check` rebuilds into a temporary folder and judges the exported files. The `floor` check is
the exception: it reads the builder's own parts, because a GLB is one merged mesh. `--check`
prints one line per check and ends with `ITEMS_CHECK_OK`, or with `ITEMS_CHECK_FAIL` naming the
failed checks; a failure exits 1. CI has no Blender, so this check is run by hand, like the
starter kit's.

| Check | What fails it |
|---|---|
| `bounds` | A GLB whose measured size differs from its manifest `sizeM` by more than 1 cm on any axis. |
| `origin` | An origin that is not bottom-centre (min y = 0, x and z centred), or a node carrying a transform. |
| `floor` | A model whose main body (the first part it builds) rests more than 2 mm above the floor. A strap, handle or loose part cannot hold the body up; `bounds` alone cannot see that. |
| `ids` | A manifest `id` that is not an item id in `godot/content/items/*.json` (a typo fails), or a `class` that is not one of the six. |
| `coverage` | A class with no class entry, or an item of those six classes that resolves to no model. |
| `scale` | An item drawn by a model whose largest dimension is outside 2x of the item's expected size (below), or outside 4x for a hand-chosen shared model such as a penlight drawn as the torch. |
| `material` | More than one material, any image other than `items_atlas`, a primitive off the sole material, or a sampler that is not nearest with nearest mipmaps. |
| `single_sided` | A double-sided material, a triangle wound against its normal, or a mesh that is not closed (an unmatched edge). |
| `coplanar` | Two same-facing triangles within 0.5 mm of one plane whose projections overlap. These are the z-fighting faces from the starter kit's review. The message gives their location. |
| `density` | Any triangle whose UV mapping stretches either axis outside its target density ±25%. Both singular values of the UV Jacobian are judged, so non-square texels fail too. |
| `manifest` | A malformed entry, a GLB outside `res://assets/first_person/items/`, or a GLB on disk that the manifest does not name (and the reverse). |
| `bytes` | A rebuilt GLB, atlas or manifest that is not byte-identical to the committed file. |

Every check has a planted error that turns it red. `-- --check --plant=<name>` applies the
mutation during the temporary rebuild:

| Plant | Mutation | Checks that go red |
|---|---|---|
| `bounds` | The plank scaled ×1.15 before its UVs are cut. | bounds, bytes |
| `float` | The duffel's body lifted 18 mm onto its strap (the first review's finding). | floor, bytes |
| `id` | `item.food.canned` misspelt as `item.food.caned`. | ids, bytes |
| `scale` | The sack of flour drawn as the 8 cm tin (the first review's finding). | scale, bytes |
| `material` | A second material on one medkit face. | material, bytes |
| `doublesided` | Back-face culling off on the material. | single_sided, bytes |
| `winding` | One battery face reversed. | single_sided, bytes |
| `coplanar` | A disk added 0.1 mm above the can's lid. | coplanar, bytes |
| `density` | One toolbox face's UVs stretched ×1.6. | density, bytes |
| `bytes` | One atlas texel changed. | bytes |

## The manifest

```json
{"kit": "items", "models": [{"match": {"id": "item.food.canned"}, "glb": "res://assets/first_person/items/food_canned.glb", "pose": "world", "sizeM": [0.0756, 0.11, 0.0756]}]}
```

- An `id` match beats a `class` match. Several ids may share one GLB; for example, every tin of
  food draws `food_canned.glb`.
- `sizeM` is the model's measured size in Godot axes: x width, y height, z depth, in metres.
- In the `world` pose the item lies or stands as it would on a floor or shelf. Units are metres,
  +Y is up, and the origin is at the bottom centre.
- The order is the hand-chosen ids, then the laddered ids sorted by id, then the six class
  entries.

## Facing

Every item faces -Z: the can's label, the torch's head, the backpack's pocket and the ammo box's
end label. That is Godot's forward, so a node turned with `look_at` toward the viewer shows the
viewer the front.

A placer must turn items to face whoever looks at them. The starter kit's shelf opens to +Z (its
back panel is at z = -0.151), so an item set on it as authored shows the room its back. Rotate it
180° about Y.

## The models

The hand-chosen ids are the things a player meets most: food and water, the first medical
items, the three cartridge families, light and fire, and the materials every barricade and repair
uses. Close variants share a model.

| GLB | Ids (first is the model's own) | Why |
|---|---|---|
| `food_canned` | `item.food.canned`, `.beans.tin`, `.soup.tin`, `.fruit.tin`, `.dogfood.tin`, `.fish.tin` | The staple. It is a dented tin with a torn label. |
| `soda_can` | `item.soda.can`, `item.drink.beer.can`, `item.drink.energy` | Common drink cans. |
| `water_bottle` | `item.water.bottle`, `.untreated`, `.empty` | Water is the first need. |
| `pill_bottle` | `item.painkillers.strong`, `.blister`, `item.antibiotics.veterinary`, `.course`, `.expired` | An amber bottle with a pharmacy label. |
| `bandage_roll` | `item.bandage.cloth`, `item.wrap.elastic`, `item.gauze.sterile` | The first wound item: gauze with a blue selvedge thread and a long loose tail. |
| `antiseptic` | `item.antiseptic.bottle`, `item.peroxide.bottle`, `item.sanitiser.gel` | A flat flask with a flip cap. |
| `medkit` | `item.medkit.field` | The first-aid kit: a zipped, padded case with a pale cross. |
| `ration_pack` | `item.food.ration` | A sealed pouch with crimped ends. |
| `ammo_pistol_box` | `item.ammo.9mm` and its variants, plus `.38`, `.45` and `.22` and their variants | A single round is under 3 cm, so this is a plain card box with an end label and three loose rounds in front. |
| `ammo_shotshells` | `item.ammo.12g`, `.slug`, `.bird`, `.handload` | Three loose shells. Each is 7 cm long, so they read loose. |
| `ammo_rifle_clip` | `item.ammo.rifle`, `.match`, `.surplus`, `.handload` | Five rifle rounds in a stripper clip. |
| `lighter` | `item.lighter.disposable` | Fire. There is no match item. |
| `torch` | `item.torch.handheld`, `.steel`, `.penlight` | Light is the attention system's other half. |
| `battery` | `item.battery` | It feeds the torch. |
| `scrap_metal` | `item.scrap.metal` | The repair and barricade material. |
| `plank` | `item.plank.sawn`, `.pallet`, `item.wood.salvaged` | The building material. |
| `nails_box` | `item.fixings.nails`, `.screws`, `.bolts` | An open card box: a heaped pile of nails, three on top, two loose in front, the back flap folded open. A jar could not show its nails through opaque single-material glass. |
| `duct_tape` | `item.tape.duct` | A half-used roll. |
| `rope_coil` | `item.cordage.rope`, `.paracord`, `.twine` | A coil with a loose end. |
| `hiking_pack` | `item.pack.hiking` | The backpack, with a lid, two buckled compression straps over a flapped front pocket, side pockets, and shoulder straps behind. |
| `toolbox` | `item.toolbox.steel` | The toolkit, with no crowbar. |
| `book` | `item.book.firstaid` and the nine other books, plus `item.paperback.dogeared` | The books share one cloth-bound manual with a pale title label. |
| `jerrycan` | `item.jerrycan.fuel`, `item.jerrycan.empty` | Fuel. |
| `storm_lantern` | `item.lantern.storm`, `item.lantern.oil`, `item.lantern.camping` | Oil and gas light. |
| `fallback_container` | `item.duffel.canvas` | The duffel, resting on its own slumped bottom with the shoulder strap draped on the floor. |

## The size ladder

Every other item of the six classes is routed by id. The builder takes the item's expected
largest dimension from its content and picks, from its class's ladder, the model whose largest
dimension is nearest in log scale.

The expected dimension is the larger of two estimates:

- **From the grid:** 7.5 cm per grid cell, or 20 cm per cell for a long footprint, where one side
  is three times the other.
- **From the mass:** 1.5 times the side of a cube of the item's mass at 400 kg/m³.

| Class | Ladder (smallest first) |
|---|---|
| consumable | squat tin `fallback_consumable` (8 cm), ration pouch (27 cm), sack `fallback_material` (35 cm) |
| material | parts case `fallback_attachment` (12 cm), scrap metal (22 cm), sack (35 cm), plank (1 m) |
| tool | parts case (12 cm), tool roll `fallback_tool` (32 cm), toolbox (47 cm) |
| container | `pouch` (15 cm), hiking pack (58 cm), duffel (67 cm) |
| armor | `armor_small`, a folded knit with a rolled cuff (14 cm); folded clothes `fallback_armor` (32 cm) |
| attachment | parts case (12 cm), tool roll (32 cm) |

The ladders hold neutral shapes only. As a result, a sack of flour is the sack, a utility pouch is
the pouch, a scalpel is the parts case and a dome tent is the tool roll. `scale` holds every
laddered item within 2x of its expected size.

The six class entries name the medium shape of each class: the tin, the sack, the tool roll, the
pouch, the folded clothes and the parts case.

## Geometry and UVs

Every part is a closed shell built from rings: a lathe, a loft or a sweep. The builder turns a
part inside out if its signed volume is negative.

UVs come from the final geometry:

- Planar bands and caps are projected onto their own plane, with the texel grid aligned to the
  object's own axes. A rounded box's cap therefore has straight label and edge rows, not
  stair-steps.
- Curved bands are unfolded quad by quad, two triangles at a time, so each triangle keeps its
  metric shape.
- A strip splits into a new island where it turns more than 80° or grows longer than 0.3 m
  (128-texel models) or 0.6 m (64-texel models).

Density is therefore exact by construction, and `density` measures it anyway.

Normals are smooth within 32°, with sharper edges split. The material is single-sided, so
interpenetrating parts are fine. Coplanar same-facing faces are not, and the builder keeps
deliberate offsets of at least 1 mm.

## Atlas and density

The atlas is one 512 × 512 PNG, with islands shelf-packed and a 1-texel gutter. The kit uses two
densities, chosen per model by its largest dimension:

- **128 texels per metre** for every model up to 0.40 m (27 of 32). At 64 texels per metre a 7.5 cm
  can is 5 texels across and its label is 6 texels tall. At 0.5 m (about 1400 screen pixels per
  metre at 1080p and 75° FOV) that gives a smear rather than a label. At 128 the can is about 30
  texels round, the label has a panel, a print row and a torn edge, and a book's title label reads.
- **64 texels per metre** above 0.40 m: the plank, backpack, toolbox, jerrycan and duffel. These
  already get 20 to 64 texels across at 64, the same density as the starter kit's furniture they
  stand beside.

At a crouch, a 64-texel item beside a 128-texel one shows texels twice the size. This is visible
within about 0.6 m.

Each GLB embeds its own copy of the atlas, which the clean-checkout loader needs (docs/23,
"First-person art loads from a clean checkout"). Sharing one texture across loaded models, and
runtime mipmaps, belong to the code piece that wires the manifest in.

## Painting

The atlas is painted, not tiled. Every texel knows the following:

- the 3D point it shows;
- its face normal;
- its part's tag;
- its distance to the nearest real convex edge, to the nearest hard (60° or more) convex edge, and
  to the nearest concave edge.

The painters are pure functions of those, with smooth value noise and integer hashes from fixed
seeds. The starter kit's reviews and this kit's first review drove the design:

- **No stamping.** Noise is evaluated at the 3D point with a per-model seed. No two islands or
  models share a pattern, and nothing repeats per atlas cell.
- **Wear follows the object, not the atlas.** Paint chips on painted metal sit on its convex
  edges. A worn highlight marks only hard edges, such as a can's rim or a box's corner, never a soft
  bevel. A one-texel highlight wandering along a narrow bevel was the first review's zigzag
  camouflage.
- **No camouflage.** Cloth is flat colour with a broad, low mottle that rarely crosses a palette
  step. It has a dark crease row in concave folds, rare one- or two-texel scuffs near hard edges,
  and one crisp contact row at the floor. Noise periods are 16 to 26 texels on surfaces, and the
  short-period noise is kept to rust and chips.
- **No readable text and no brands.** Labels are coloured bands and panels with rows of short
  dashes that suggest print. The medkit's cross is a pale plus on faded green, not a red cross.
- **No baked light.** The engine lights the albedo.

The palette is muted 6-step ramps (tin, rust, brass, card, olive, canvas, burlap and others),
listed at the top of the builder.
