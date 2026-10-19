# Vehicles: the north-south cars and the light vehicles

The outpost pack drew its sedan, van and truck east-west only. Until 2026-10-19 the north-south
view and all five light vehicles were drawn by `tools/sprites/parts/vehicles.py` and
`parts/light_vehicles.py`; this folder replaces both. The textures are declared in
`godot/assets/sprites/authored.json` and listed in `../manifest.json`.

| set                      | canvases                          | how it was made                      |
| ------------------------ | --------------------------------- | ------------------------------------ |
| sedan, van, truck (N-S)  | 64x128, 64x160, 64x160            | guide, one img2img pass, cut         |
| their wrecks             | as above                          | `guides/wreck.py` over the kept pass |
| five light vehicles x 3  | 64x64 / 32x96, or 32x64 both ways | drawn by `light.py`                  |

## The north-south cars

1. **A paint-over guide** (`guides/cars_ns.py`): the three cars nose-up on one 224x160 sheet,
   sized so a car is as long north-south as the pack draws it east-west (sedan three tiles, van
   and truck four).
2. **One img2img pass** over the sheet, so the three share one hand. `prompts.json` has both
   passes; the first, at strength 300, kept the guide almost unchanged and was rejected.
3. **The wrecks are not generated.** `guides/wreck.py` damages the kept sheet deterministically:
   dulled paint, rust blooms, crazed glass, a starred windshield, a creased hood and a crumpled
   corner. Same seed, same pixels.
4. **`cars.py`** cuts each car whole and stands it on its canvas's bottom row.

## The light vehicles

`light.py` draws them in the pack's manner: a one-pixel near-black outline, broad flat pixels,
four tones a material lit from the north. Thin frames and spokes are what an image model smears,
so these were drawn by code. Pale and green are paint; burnt loses its rubber and its seat.

## Rebuilding

```bash
python3 guides/cars_ns.py sources/cars-ns-guide.png
# sources/cars-ns-pass2.png is the generated sheet; it is not reproducible offline
python3 cars.py      # runs guides/wreck.py, then cuts textures/*-ns.png
python3 light.py     # textures/<class>-<variant>-<axis>.png
python3 ../../../../tools/sprites/build.py
```

Run from this directory. `npm run sprites:check` proves the copies match.

## What is still open

No damage states between intact and wreck, no open doors, and no headlight or brake-light glow.
