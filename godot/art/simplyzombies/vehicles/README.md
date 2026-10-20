# Vehicles: the north-south cars and the light vehicles

The outpost pack drew its sedan, van and truck east-west only. Until 2026-10-19 the north-south
view and all five light vehicles were drawn by `tools/sprites/parts/vehicles.py` and
`parts/light_vehicles.py`; this folder replaces both. The textures are declared in
`godot/assets/sprites/authored.json` and listed in `../manifest.json`.

| set                      | canvases                          | how it was made                      |
| ------------------------ | --------------------------------- | ------------------------------------ |
| sedan, van, truck (N-S)  | 64x128, 64x160, 64x160            | painted by `guides/cars_ns_paint.py` |
| their wrecks             | as above                          | `guides/wreck.py` over that sheet    |
| five light vehicles x 3  | 64x64 / 32x96, or 32x64 both ways | drawn by `light.py`                  |

## The north-south cars

1. **Painted by code** (`guides/cars_ns_paint.py`): the three cars nose-up on one 224x160 sheet,
   in the pack's own paint, as long north-south as the pack draws them east-west plus a few rows
   of deep rear face (91, 108 and 110 rows with the outline, which closes the rear on the
   canvas's bottom row). A short roof over a tall rear face for a strong three-quarter view,
   four body tones, a side panel down each flank with the side glass in it, a wheel arch at each
   axle with the tyre flush inside it, amber indicators on the nose, red lamps, a plate and (van,
   hatchback) rear glass on the rear face, glass in four tones with a diagonal streak.
2. **The wrecks are not a second painting.** `guides/wreck.py` damages that sheet
   deterministically: dulled paint, rust blooms (solid ragged patches, never a ring), crazed
   glass, a starred windshield, a creased hood and a crumpled corner. Same seed, same pixels.
3. **`cars.py`** runs both and cuts each car whole, standing on its canvas's bottom row.

The first north-south cars were one img2img pass over a paint-over guide; the art review found
them a fifth too long, flat-roofed and with tabs for wheels, so they were replaced. That sheet is
kept as `sources/rejected-cars-ns-pass2.png`, its prompts in `prompts.json`.

## The light vehicles

`light.py` draws them in the pack's manner: a one-pixel near-black outline, broad flat pixels,
four tones a material lit from the north. Thin frames and spokes are what an image model smears,
so these were drawn by code. Pale and green are paint; burnt loses its rubber and its seat.

## Rebuilding

```bash
python3 cars.py      # runs guides/cars_ns_paint.py and guides/wreck.py, then cuts textures/*-ns.png
python3 light.py     # textures/<class>-<variant>-<axis>.png
python3 ../../../../tools/sprites/build.py
```

Run from this directory. `npm run sprites:check` proves the copies match.

## What is still open

No damage states between intact and wreck, no open doors, and no headlight or brake-light glow.
