# First-person loot-item kit

The everyday things a player picks up, as world-pose GLBs that share one pixel atlas. There are
24 specific models, matched to 60 item ids, and one fallback per item class. Every item of class
`consumable`, `material`, `tool`, `container`, `armor` or `attachment` in
`godot/content/items/*.json` therefore has something to draw. Weapons (`weapon.melee`,
`weapon.ranged`) belong to the weapon kit, which uses the same manifest format.

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

- `godot/assets/first_person/items/*.glb`: 30 models.
- `godot/assets/first_person/items/items_atlas.png`: the shared atlas.
- `godot/assets/first_person/items.manifest.json`: the manifest.
- `items.blend`: the convenience scene.

A rebuild runs every check below on what it wrote and prints `ITEMS_BUILD_OK`.

`--check` rebuilds into a temporary folder and judges the exported files, not the builder's
memory. It prints one line per check and ends with `ITEMS_CHECK_OK`, or with `ITEMS_CHECK_FAIL`
naming the failed checks; a failure exits 1. CI has no Blender, so this check is run by hand,
like the starter kit's.

| Check | What fails it |
|---|---|
| `bounds` | A GLB whose measured size differs from its manifest `sizeM` by more than 1 cm on any axis. |
| `origin` | An origin that is not bottom-centre (min y = 0, x and z centred), or a node carrying a transform. |
| `ids` | A manifest `id` that is not an item id in `godot/content/items/*.json` (a typo fails), or a `class` that is not one of the six. |
| `coverage` | A class with no fallback, or an item of those six classes that resolves to no model. |
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
| `id` | `item.food.canned` misspelt as `item.food.caned`. | ids, bytes |
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
- The item's front faces -Z: the can's label, the torch's head and the backpack's pocket. A node
  that looks at the player shows the player the front.

## The models

These are the ids a player meets most: food and water, the first medical items, the three
cartridge families, light and fire, and the materials every barricade and repair uses. Where
one item has close variants, the variants share its model.

| GLB | Ids (first is the model's own) | Why |
|---|---|---|
| `food_canned` | `item.food.canned`, `.beans.tin`, `.soup.tin`, `.fruit.tin`, `.dogfood.tin` | The staple. It is a dented tin with a torn label. |
| `soda_can` | `item.soda.can`, `item.drink.beer.can`, `item.drink.energy` | Common drink cans. |
| `water_bottle` | `item.water.bottle`, `.untreated`, `.empty` | Water is the first need. |
| `pill_bottle` | `item.painkillers.strong`, `item.antibiotics.veterinary` | An amber bottle with a pharmacy label. |
| `bandage_roll` | `item.bandage.cloth`, `item.wrap.elastic` | The first wound item. The roll trails a loose tail. |
| `antiseptic` | `item.antiseptic.bottle`, `item.peroxide.bottle`, `item.sanitiser.gel` | A flat flask with a flip cap. |
| `medkit` | `item.medkit.field` | The first-aid kit: a zipped, padded case with a pale cross. |
| `ration_pack` | `item.food.ration` | A sealed pouch with crimped ends. |
| `ammo_pistol_box` | `item.ammo.9mm` and its variants, plus `.38`, `.45` and `.22` and their variants | A single pistol round is under 3 cm and vanishes on the floor, so pistol ammunition is drawn as the card box it is found in. |
| `ammo_shotshells` | `item.ammo.12g`, `.slug`, `.bird`, `.handload` | Three loose shells. Each is 7 cm long, so they read loose. |
| `ammo_rifle_clip` | `item.ammo.rifle`, `.match`, `.surplus`, `.handload` | Five rifle rounds in a stripper clip. |
| `lighter` | `item.lighter.disposable` | Fire. There is no match item. |
| `torch` | `item.torch.handheld` | Light is the attention system's other half. |
| `battery` | `item.battery` | It feeds the torch. |
| `scrap_metal` | `item.scrap.metal` | The repair and barricade material. |
| `plank` | `item.plank.sawn` | The building material. |
| `nails_jar` | `item.fixings.nails` | "A jar of nails". |
| `duct_tape` | `item.tape.duct` | A half-used roll. |
| `rope_coil` | `item.cordage.rope` | A coil with a loose end. |
| `hiking_pack` | `item.pack.hiking` | The backpack. |
| `toolbox` | `item.toolbox.steel` | The toolkit, with no crowbar. |
| `book` | `item.book.firstaid`, plus the closequarters, marksmanship, bushcraft, conditioning and gunsmithing books | The skill books share one cloth-bound manual. |
| `jerrycan` | `item.jerrycan.fuel`, `item.jerrycan.empty` | Fuel. |
| `storm_lantern` | `item.lantern.storm`, `item.lantern.oil` | Oil light. |

The class fallbacks are:

| GLB | Class | Shape |
|---|---|---|
| `fallback_consumable` | `consumable` | A squat ring-pull tin with a plain band. |
| `fallback_material` | `material` | A tied burlap sack. |
| `fallback_tool` | `tool` | A canvas tool roll with two straps. |
| `fallback_container` | `container` | A slumped canvas duffel. |
| `fallback_armor` | `armor` | Folded clothes in a stack of three layers. |
| `fallback_attachment` | `attachment` | A small plastic parts case with a label. |

## Geometry and UVs

Every part is a closed shell built from rings: a lathe, a loft or a sweep. The builder turns a
part inside out if its signed volume is negative.

UVs come from the final geometry:

- Planar bands and caps are projected onto their own plane.
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

- **128 texels per metre** for every model up to 0.40 m (25 of 30). At 64 texels per metre a 7.5 cm
  can is 5 texels across and its label is 6 texels tall. At 0.5 m (about 1400 screen pixels per
  metre at 1080p and 75° FOV) that gives a smear rather than a label. At 128 the can is about 30
  texels round, the label has a panel, a print row and a torn edge, and a book's title band reads.
- **64 texels per metre** above 0.40 m: the plank, backpack, toolbox, jerrycan and duffel. These
  already get 20 to 64 texels across at 64, the same density as the starter kit's furniture they
  stand beside.

Each GLB embeds its own copy of the atlas, which the clean-checkout loader needs (docs/23, "First-person art
loads from a clean checkout"). That copy is most of each file's 82 to 167 KB, and 3.1 MB in total.

## Painting

The atlas is painted, not tiled. Every texel knows the following:

- the 3D point it shows;
- its face normal;
- its part's tag;
- its distance to the nearest real convex and concave mesh edge.

The painters are pure functions of those, with smooth value noise and integer hashes from fixed
seeds. The starter kit's reviews drove the design:

- **No stamping.** Noise is evaluated at the 3D point with a per-model seed. No two islands or
  models share a pattern, and nothing repeats per atlas cell.
- **Wear follows the object, not the atlas.** Paint chips, scuffs, crease grime and floor grime
  are measured from the mesh's own edges and the floor plane.
- **No camouflage.** Noise periods are set in texels (14 to 26 for mottling), with amplitudes that
  rarely cross a palette step. Surfaces read as flat colour with deliberate detail: chips on
  edges, rare scratches, stains, labels and seams.
- **No readable text and no brands.** Labels are coloured bands and panels with rows of short
  dashes that suggest print. The medkit's cross is a pale plus on faded green, not a red cross.
- **No baked light.** The engine lights the albedo.

The palette is muted 6-step ramps (tin, rust, brass, card, olive, canvas, burlap and others),
listed at the top of the builder.
