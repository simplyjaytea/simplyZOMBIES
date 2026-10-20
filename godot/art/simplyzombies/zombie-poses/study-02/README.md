# Zombie study 02: the screamer and the bloater

The last two face-on generated rigs (`zombie_screamer`, `zombie_bloater`, drawn by
`tools/sprites/parts/characters.py` until 2026-10-19), redrawn as pose families beside study 01's
seven: four idle views, a four-frame walk each way, and a supine and a prone corpse. They are
declared in `godot/assets/sprites/authored.json` as `body_zombie_screamer`,
`body_zombie_bloater` and their `corpse_*` keys, and judged by `check_authored.gd`'s
ZOMBIE_POSES lane at study 01's own geometry.

| family   | living canvas | anchor  | walk fps | corpse canvas | built on          |
| -------- | ------------- | ------- | -------- | ------------- | ----------------- |
| screamer | 32x40         | [16,40] | 5        | 48x40         | the commuter      |
| bloater  | 40x48         | [20,48] | 4        | 56x40         | the heavy, painted by code |

## How it was made

1. **A paint-over guide** (`guides/`), from a study 01 family that already has the right body
   and the right motion: the commuter for the screamer (gown, bloodless skin, bare shins, an open
   mouth), the heavy for the bloater (sickly skin and a swollen belly per view; a separate back
   view for the north row, so no face shows walking away). The guides keep every frame's pose,
   so the walk cycle and its timing are study 01's.
2. **One img2img pass over the whole 5x4 atlas** at init strength 300, so all twenty frames are
   drawn together and stay one character. `prompts.json` has every prompt, seed and strength,
   rejected passes included.
3. **Mechanical extraction** (`extract.py`): each cell cut whole and moved so its soles sit on
   the bottom row; corpses centred on their ground anchor. Nothing repainted or resized.

**The bloater was repainted by code after the art review (2026-10-20).** The img2img pass gave
it a lost purple head on the front row, a belly pasted over its near arm, single-pixel speckle
for shading and an acid green past the pack's range. `guides/bloater_paint.py` now builds both
its sheets straight from the heavy, with no generation: the heavy's head, face and walk kept,
its body pushed apart into the bloater's own silhouette (arms out beside the gut, legs set wider
and thicker; in the side views the near arm bent at the elbow so the forearm rests on the gut),
the skin carried onto a four-tone olive at the pack's saturation, the clothes soured a step, and
the belly an ellipsoid lit from the top left in contiguous bands with a fine grain, riding out
from under the vest's hem (which keeps a one-pixel shadow), sagging over the belt, bulging
forward in the side views 3-4 px past the arms and hips with its front edge held still through
the walk, spilling past the flanks from behind, and outlined in the pack's near-black. In every
side frame the forearm is painted over it in the upper arm's own skin with a cast shadow, and
belly and forearm bob a pixel with each step. Its corpses take the same skin and a mound shaded the
same way; on the prone one it bulges out from under the torso. The generated bloater sheets stay under
`sources/` as the record `prompts.json` describes; nothing reads them.

The screamer's corpses are the paint-over guides **used as drawn**. Every img2img pass over them blurred the
outline and lost the head (the `rejected-*-corpses-*` sheets), so the settled poses are study
01's own commuter corpses, recoloured. `extract.py` also pulls the screamer's near-white
highlights down into the pack's skin range, takes its shirt a value under its face, and shades
each hand in two tones of the face's grey-green inside the commuter's own hand range.

## Rebuilding

```bash
python3 guides/screamer_walk.py ../atlases/zombie-commuter.png sources/screamer-walk-guide.png
python3 guides/screamer_corpses.py ../textures sources/screamer-corpses.png
python3 guides/bloater_paint.py ../atlases/zombie-heavy.png ../textures/zombie-heavy sources/
# the screamer's generated sheet is not reproducible offline; it is committed under sources/
python3 extract.py
python3 ../../../../../tools/sprites/build.py   # copies the textures into assets/sprites/
```

Run from this directory. `npm run sprites:check` proves the copies match.

## What is still open

Like study 01: no attack, hit, death-transition or rising states, and an idle that is one pose.
The screamer's scream and the bloater's burst are sim events with no animation of their own.
