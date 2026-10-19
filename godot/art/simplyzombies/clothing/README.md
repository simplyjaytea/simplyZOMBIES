# Survivor clothing

Torso, legs and feet garments for the outpost survivor, painted onto **every frame** the pack
survivor draws: four idle views and a four-frame walk each way, twenty frames. Landed 2026-10-19
as alpha plan item A6 ("Clothe everyone"); docs/23 carries the record.

The pack's survivor is a paperdoll base in underwear, and its four wearables (vest, helmet, gas
mask, backpack) are fitted to the idle views and stand still while the body walks. A shirt cannot
do that, so a garment here is painted per frame and the game composes it **into** the body
picture (`Appearance.body_texture`) on the very frame the body shows. The clothes cannot step out
of time with the legs, because they are chosen by the body's own frame key.

## How a garment is painted

- `parts.py` labels every opaque pixel of each of the twenty source frames
  (`../textures/characters/survivor_*.png`, cut 32x48 to 32x40 exactly as `authored.json` crops
  the body): ink, head, torso, arm, hand, pelvis, leg, foot. The landmarks come from the frame's
  own underwear band, so the walk's bob moves them with the body.
- `build_clothing.py` repaints only the skin and underwear pixels of the parts a garment covers,
  in the frame's own light: lit skin becomes the cloth's base tone, shaded skin its shade, the
  darkest skin its deep tone, and a pixel with ink or nothing over it its highlight. Details
  (collar, placket and buttons, zip, cuffs, hem, belt and buckle, sole, boot cuff, apron bib and
  straps, wrap bands, blanket stripes) are placed on the frame's landmarks. The pack's ink and the
  head are never touched, so a garment cannot move the silhouette.
- Ramps are four flat tones in the pack's families (`../STYLE.md`); every number is an integer, so
  the output is the same bytes on every interpreter.

The output is one 160x160 sheet per garment under `native/`: a row per view (s, e, n, w), the
idle picture in column 0 and the walk's frames in columns 1-4. `authored.json` declares each
garment as kind `wear` with `fits: "body_survivor"` and crops its twenty members from the sheet;
`npm run sprites:check` reproduces `godot/assets/sprites/wear_*.png` from those crops.

```bash
python3 build_clothing.py           # repaint native/
python3 build_clothing.py --check   # repaint in memory, compare byte for byte -> CLOTHING_OK
python3 tools/sprites/build.py      # (from the repo root) re-cut the runtime PNGs
python3 preview.py DIR              # contact sheets for eyes, never read by the game
```

## The garments

| Slot | Garment | Worn by |
|---|---|---|
| torso | `wear_tee_sand`, `_olive`, `_slate`, `_rust` | the default outfit |
| torso | `wear_shirt_linen`, `wear_shirt_thermal` | linen shirt, thermal top |
| torso | `wear_jacket_leather` | leather jacket |
| torso | `wear_coat_winter`, `wear_coat_parka`, `wear_raincoat` | winter coat, parka, hooded raincoat |
| torso | `wear_poncho_rain`, `wear_poncho_tarp`, `wear_blanket` | rain poncho, tarp poncho, wool blanket |
| torso | `wear_coverall_paper`, `wear_suit_hazmat` | paper coverall, hazmat suit |
| torso | `wear_apron_butcher`, `wear_apron_welding`, `wear_wrap_cloth` | butcher's apron, welding apron, cloth wrap |
| legs | `wear_pants_charcoal` | the default outfit |
| legs | `wear_pants_denim`, `wear_pants_canvas` | jeans, canvas pants (and the default outfit) |
| legs | `wear_pants_insulated`, `wear_leggings_thermal`, `wear_shorts_cotton` | insulated trousers, thermal leggings, cotton shorts |
| feet | `wear_shoes_worn` | the default outfit |
| feet | `wear_boots_leather`, `wear_boots_steel`, `wear_boots_insulated`, `wear_sandals_canvas` | the matching items |

The default outfit lives in `godot/content/players/player.json` (`appearance.outfit`): a slot with
nothing equipped wears one of its garments, chosen by the body's full entity id (no simulation
random number). It is a picture, not an item: it weighs nothing and warms nothing.

## Limits, named

- Only the pack survivor rig is clothed. Zombies keep their own painted clothes; the screamer and
  the bloater are face-on generated rigs.
- A garment never changes the silhouette: a coat, a poncho or a blanket is drawn inside the body's
  outline rather than flaring past it.
- From the side, a short sleeve reads as a long one: the side views fold the near arm into the
  torso, so only the hand stays bare.
- Settled human corpses still use the pack's four bare corpse poses.
- Caps, hats, gloves, belts and eyewear still draw nothing on the body.
