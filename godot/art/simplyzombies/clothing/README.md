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
  own underwear band, so the walk's bob moves them with the body. Seen from the side, the near
  arm past the underwear's span on the side the body faces is labelled arm, not chest, so a
  short sleeve ends on it and a long one is creased apart from the body.
- `build_clothing.py` repaints only the skin and underwear pixels of the parts a garment covers.
  A pixel is shaded on a light scale, not picked from four tones: it starts from the body's own
  tone under it (lit skin, shaded skin, the darkest skin; the underwear's flat grey counts as
  lit, since its value is its colour and not its light), softened with its covered neighbours;
  cloth darkens as it falls down its part and starts again at the waist, where a belt, a
  drawstring or a seam cinches it; cloth facing the sky lifts and cloth turning under or away at
  an edge drops; the pack's key light from the upper left keeps the body's left side lit and
  turns the far side into shade.
  Folds crease it, one pixel each: the drape from each armpit, the bunching above the belt, the
  inside of a long sleeve's elbow, the sleeve seam at the shoulder, a lit plane over the chest
  with two creases running down from it, the crease parting a side view's near arm from the body,
  the crotch, the knee, a trouser leg's outer seam, a pocket's mouth. Details (collar, placket and buttons, zip, patch pockets, cuffs, hems with their rolled
  lip, belt and buckle, a coat's drawstring in its trim, a hazmat suit's taped seams and its hood
  and steel respirator, sole, boot cuff, apron bib and straps, wrap bands, blanket stripes) are
  placed on the frame's landmarks. Where cloth meets bare skin it ends on its deep tone, as the
  pack's vest does, and a short sleeve or short hem casts a pixel of shadow on the skin below.
  The pack's ink is never touched, so a garment cannot move the silhouette; the head is touched
  only by a hood (the hair, and the mask over the lower face), never its ink or its eyes.
- `Canvas.render` turns each level into its ramp's colour through the material: plain cloth
  gains contrast and a faint grain, denim a twill, wool and fur a coarse nap, paper a crinkle;
  leather and rubber take a hard light, deeper shadows and a shine where they face up (rubber
  with no weave at all, so a hazmat suit is smooth rather than speckled). A garment frame comes
  out at about the pack vest's tonal density, counted as distinct colours over painted pixels on
  the south view: the tee 61 over 84, the leather jacket 76 over 100, the parka 73 over 122, the
  hazmat suit 81 over 159; the pack's vest 85 over 117.
- Ramps are four tones in the pack's families (`../STYLE.md`), blended between and paled or
  cooled past either end; every number is an integer, so the output is the same bytes on every
  interpreter (checked on Python 3.12 and 3.13).

The output is one 160x160 sheet per garment under `native/`: a row per view (s, e, n, w), the
idle picture in column 0 and the walk's frames in columns 1-4. `authored.json` declares each
garment as kind `wear` with `fits: "body_survivor"` and crops its twenty members from the sheet;
`npm run sprites:check` reproduces `godot/assets/sprites/wear_*.png` from those crops.

```bash
python3 build_clothing.py           # repaint native/
python3 build_clothing.py --check   # repaint in memory, compare byte for byte -> CLOTHING_OK (in npm run sprites:check)
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
- The pack's side-view arm is a stub of four or five pixels, so from the side a sleeve is a
  sleeve and a cuff, not a modelled forearm; at this scale that is the arm there is.
- Settled human corpses still use the pack's four bare corpse poses.
- Caps, hats, gloves, belts and eyewear still draw nothing on the body.
