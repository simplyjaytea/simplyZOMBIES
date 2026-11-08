# First-person clothing layers

The first cut of the modular clothing kit. Layers bind by bone name to the survivor rig and share one
1024 x 1024 `ClothingAtlas` at 128 px/m. Each layer GLB has one single-sided, nearest-filtered material.
A dressed body therefore needs only `SurvivorAtlas` and `ClothingAtlas`, however many layers it wears.

## Rebuild, publish and check

From the repository root, with Blender 5.2:

```bash
blender --background --factory-startup --python tools/blender/first_person_clothing/build_clothing.py
blender --background --factory-startup --python tools/blender/first_person_clothing/build_clothing.py -- --check
blender --background --factory-startup --python tools/blender/first_person_clothing/build_clothing.py -- --plant missing-entry
blender --background --factory-startup --python tools/blender/first_person_clothing/build_clothing.py -- --uv-layout-dir /absolute/clothing/uv --render-dir /absolute/clothing/review
```

The builder writes `cap_soft.glb`, `pack.glb`, `clothing_atlas.png` and `clothing.json` under
`godot/assets/first_person/clothing/`. The manifest is deliberately not a `*.manifest.json`, so the
loot-model loader never consumes it. `--check` rebuilds into a temporary directory, judges the exported
GLBs and compares all four outputs byte for byte. `--plant <name>` must be refused by its named check,
printing `CLOTHING_PLANT_REFUSED`; a defect that escapes prints `CLOTHING_PLANT_FAIL` and exits 1.
No `.blend` or hand-edited binary is part of this kit.

`--uv-layout-dir` writes `uv_layout.png`, `uv_layout.json` and `uv_position.png`. Every family rectangle,
including the reserved art-pass families, is fixed in `clothing_manifest.FROZEN`; later work cannot move
an earlier island. The JSON records top-left pixel rectangles, orientation, landmarks and mirroring.
`--render-dir` writes clay and textured turnarounds and a dressed survivor GLB for the in-engine sheet.

## The published shape

`clothing.json` names the survivor rig, hair nodes, family GLBs and variant nodes, sleeve nodes, hand
pages and chemical cuff extra. It carries all 63 worn content ids. A picture names its family, variant,
read distance and drawn coverage; an item not in this cut has `none: "first cut"`. Every torso item,
including a `none`, carries `inner`, `mid` or `over`, so the presentation order is data rather than sim
state. Gloves name their hand page and explicitly keep body paint out of this cut.

The first modelled families are:

- `cap_soft`: `cap_soft_cap` for the canvas cap and `cap_soft_knit` for the wool hat. Both use tucked hair.
- `pack`: one `pack` outline for the hiking, school and frame packs. A pack never shows what it contains.

Carrier (`flat`, `loaded`, `rig`), hard helmet and padded coat (`default`, `hood`) names are published now
for the next round. Their entries are present before their GLBs. The parka names hidden hair and the
padded sleeve. Carrier loading reads only the plate slot, never condition, tier, affixes or contents.

The owner's cards 28 to 32 use their defaults: rain gear and the blanket will hide the vest; other torso
garments draw under it; the base top and trousers stay; base-boot and shared-raider paint are later;
turned-colonist clothing waits for C3; and the named first-cut gap ships. No survivor footwear changes
are in this round.

## What the checks measure

| Check | Exported evidence | Plant |
|---|---|---|
| `coverage` | every worn content id exactly once, a picture or reasoned `none`, no unknown id, torso layers present | `missing-entry` |
| `declared-parts` | bone-weighted body parts equal armour/warmth keys plus named `drawnBeyond` | `undeclared-cover` |
| `never-clips` | body and hair clearance over eight samples of every survivor clip | `clip` |
| `stand-off` | nearest-body distance per family, with the brim and pack depth included | `float` |
| `density` | finite UV Jacobians and area-weighted median 128 px/m +/-10% per chart | `layer-density` |
| `rig-material` | known bone names, at most four normalized influences, one nearest single-sided atlas material | `bone-rename`, `second-material` |
| `budget` | per-variant family caps and the dressed stack below 14,500 triangles | `budget` |
| `far-read` | rasterised outline against the empty slot at 47 px/m for 10 m and 235 px/m for 2 m | `far-read` |
| `paint` | declared fabric ramps, no atlas-cell checker, four painted texels around every sampled island texel | `paint-cells` |
| `bytes` | GLBs, atlas and manifest rebuild byte-identical | `flip-byte` |

Paint is deterministic form shading from each face's normal within the family's declared ramp. There is
no random noise, atlas-cell camouflage, condition display, tier display or affix display. The chemical
cuff and glove pages are named now but built with the arms round, after the rifle merge required by the
task.
