# The look

What the first-person game is meant to look like, the law a picture must keep, and how a change to
the look is judged. The owner delegated the look on 2026-11-12
([the decision](decisions/2026-11-12-the-look-is-judged-by-pictures.md)); this file is the target
every look piece aims at. It carries no status: what is built is whatever
`npm run godot:check:fp_look` judges and the look sheet shows.

## The reference, already decided

Project Zomboid's Project Viewpoint reading of ordinary places in 3D, with Zero Sievert's pixel
textures, restrained colour and wear ([docs/39](39-first-person-pivot.md)). The place is the Kagase
valley ([docs/42](42-ome-okutama-setting.md), "Materials and colours, for the art lead"): grey
kawara, darkened cedar boards, streaked plaster, rust-edged sheet, pale concrete block with a moss
line; wet grey asphalt, concrete, gravel, cedar-needle brown; cedar plantations in dark rows,
bamboo, plum and persimmon by the houses. Cool and low in chroma, with few accents.

## Three pillars

1. **Quiet, not grim.** The valley is beautiful and indifferent: soft light, mist on cedar slopes,
   wet asphalt, grey tile. The dread comes from stillness and from what the air hides.
2. **The picture is the sim.** Nothing drawn claims what the sim does not hold. Fog and night are
   real limits of sight, and the picture leans on them instead of fighting them.
3. **Built, low-poly, crisp.** Forms stay simple and textures stay pixel-true. Beauty comes from
   light, air, colour and composition, never from detail the kit does not have.

## The law a picture keeps

These are settled elsewhere; the clause is linked so a look piece reads it before it draws.

- **Geometry is the sim's.** Walls, windows, doors, low cover and trees fill exactly the bands of
  `SimSpace.PROFILE` ([docs/40](40-first-person-spatial-contract.md)). A tree is opaque over its
  whole tile to 2.55 m; the crown above that is dressing. A picture may add above and around what
  the sim holds. It never opens what the sim closes and never closes what the sim leaves open.
- **Dressing hides nobody.** Decoration stops no body, hides no body and gives no light
  ([docs/41](41-weapons-characters-world-plan.md), rule 2). Anything taller than the Low band
  (1.1 m) stands flush to a wall. Ground cover stays under a crawling body's height. It is placed
  by a hash of the map seed and the tile, never by a random draw.
- **Bodies are drawn only where the sim sees them**, with no outline, glow or silhouette through
  geometry. A shadow or an effect that belongs to a body hides with it.
- **Light is the sim's.** No lamp, window, sign or machine lights the world unless the sim lit
  it. Night stays as dark as the sim says: the first-person gate's LIGHT lane holds the midnight
  sun under 0.05 and the ambient under 0.15, and no grade, glow or moon may undo that.
- **Weather is read, not invented.** The sky, the air and whatever falls follow
  `SimWeather.kind`, the sim's sight multiplier and the sim's own lightning. Nothing drawn limits
  sight more or less than the sim does.
- **The camera at rest does not move** (the GAMECAM lane), the near plane stays at 0.05 m, and no
  physics body enters the scene.
- **Words, no numbers.** No bar, meter, reticle or digit on the HUD. One face (VT323) at the
  sizes of `Chrome.LADDER`.
- **Art is built.** No downloaded, photographed or generated image ships. Models come from a
  builder with a check; textures and meshes made in code are deterministic. World surfaces hold
  64 texels a metre, people 128 and 256, nearest filtering with mipmaps.
- **Budgets are correctness.** See "How a change is judged".

## Colour script

sRGB. A season shifts the green and the accents; the sim starts in spring.

| Thing | Colour |
|---|---|
| Overcast sky | zenith `#8E979C`, horizon `#C4C8C6`, a slow cloud mottle within a few percent |
| Clear sky | pale and washed: zenith `#6F8FB4`, horizon `#C3CFD4`; sun `#FFF2DC` |
| Dusk | horizon `#D99A72`, middle `#6E6A86`, zenith `#2B3350`; sun `#FFB070` |
| Dawn | horizon `#D3B8A8`, zenith `#56627A`; the valley's mist at its thickest |
| Night | zenith `#05070C`, horizon `#0B1018`; sparse stars on a clear night |
| Haze | the sky's horizon colour at that hour |
| Wet asphalt | `#4A4D50`, patches `#3A3D40`, worn paint `#C9C7B8` |
| Concrete, gravel, packed dirt, rubble | `#8C8B84`, `#9A968C`, `#6B5A45`, `#77726A` |
| Grass | spring `#6F8448`, summer `#57733B`, autumn `#7A7A45` with dry tips `#9A8F55`, winter `#7B7559` |
| Undergrowth, cedar litter, moss line | `#4D5A36`, `#6A4A30`, `#586B3A` |
| Cedar | foliage `#263A2C`, trunk `#4A3A30`, the same in every season |
| Accents, under a twentieth of a frame | plum blossom `#E8C9CF` in spring, persimmon `#B5652B` and maple `#9C3B25` in autumn, torii vermilion, vending-machine blue |
| HUD ink | `#E4DFCF` on a soft shadow; prompt amber `#E2A33A`; harm rust |

By day the figures are the warmest, sharpest things in a frame. At night only what the carried
light touches has colour.

## Light and air

- **The sun moves** with the sim's clock: an arc from east through the south to west, low enough
  that shadows are long. Overcast softens its shadows to about a third; a clear day gives them
  weight. The energies stay inside the LIGHT lane's thresholds.
- **The sky is drawn**: a gradient, a slow cloud layer and a soft sun, chosen by the sim's weather
  kind. Clear is pale. Rain and storm lower and darken the deck. Fog is a white wall. Snow is a
  soft grey.
- **Air is always there**: a thin haze by day that takes the far side of the district down by
  about two thirds, thicker under rain, and the sim's own sight distance in fog weather.
  `fog_enabled()` keeps meaning the sim's fog; the haze is a separate thing with its own reader.
- **The valley stands beyond the edge**: a verge, a retaining wall, cedar rows, steep cedar
  slopes on three sides and the river side open to a far bank, then paler ridges with bands of
  mist. Nothing there is reachable or tells the player anything. It is the place.
- **Night gains depth, not light.** The horizon is a shade paler than the zenith; the ground is
  not brighter than today.
- **Grade**: a gentle filmic curve, saturation near 0.9, a light vignette, fine grain. No lens
  tricks.

## The ground

One continuous surface instead of a board of tiles. The sim's surface decides the material per
tile: asphalt on carved streets with worn lines, concrete on other paving, dirt, grass with low
tufts, undergrowth, rubble, water. Edges between surfaces are irregular. It stays flat and
flat-shaded (the FLAT lane), 64 texels a metre, with mipmaps so distance does not shimmer.

## What is a plain box today

- **Trees** are cedars: dark, tall, a trunk and skirt that fill the tile the sim blocks, the crown
  above. A few broadleaf trees by houses carry the season's accent.
- **Thickets** (the sim's Screen) are dense brush, opaque to 2.55 m and plainly walkable.
- **Low cover** reads as what it is and as 1.10 m tall: a block wall, stacked timber, rubble, a
  parked kei car.
- **Walls, windows and doors no kit building owns** get the valley's materials: block, board and
  sheet, a frame and a sill around an opening.

## Words on the screen

No slabs. The HUD's sentences, unchanged and free of digits, sit low on the left with a soft
shadow; steady lines recede and new ones arrive; the key strip is small and gets out of the way;
the prompt sits under the centre in amber. The HUD hides under any screen that covers it. The
title sets the name large over its own still backdrop.

## How a change is judged

- **By pictures.** `xvfb-run -a npm run godot:shots:look -- --out=<dir>` photographs fixed stations
  at noon, dusk and night (`--weather=` for the other skies); `tools/look/look_sheet.py` lays out
  one sheet, before and after pairs, or a pixel diff. A pull request that changes the look carries
  the pairs. A critic who did not build the change reads them against this file.
- **By structure.** `npm run godot:check:fp_look` holds each mechanism to the scene the game boots
  and to the sim. A built lane names its plants above its function, and
  `-- --plant=<name>` must end red on that lane's own FAIL line. A lane whose mechanism is not
  built yet says so with `FP_LOOK_SKIP`, and the result line counts the skips.
- **By cost.** `xvfb-run -a npm run godot:frames:look -- --out=<dir>` times the same stations. The
  draw budget is 10 ms mean ([docs/22](22-performance.md)); the measure is `render_cpu_ms` plus
  `render_gpu_ms` per station at 1280x720, before and after, in the pull request. A look piece
  also runs it once on software GL (`LIBGL_ALWAYS_SOFTWARE=1 __GLX_VENDOR_LIBRARY_NAME=mesa`),
  where fill cost shows, and says what the ratio is.
- **By the gates that already hold the picture**: `godot:check:first_person`,
  `godot:check:fp_geometry`, `godot:check:hud`, `godot:check:ui_skin`.
