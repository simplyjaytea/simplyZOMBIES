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
| bloater  | 40x48         | [20,48] | 4        | 56x40         | the heavy (broad) |

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

The corpses are the paint-over guides **used as drawn**. Every img2img pass over them blurred the
outline and lost the head (the `rejected-*-corpses-*` sheets), so the settled poses are study
01's own commuter and heavy corpses, recoloured and, for the bloater, given a belly mound and
swollen flanks.

## Rebuilding

```bash
python3 guides/screamer_walk.py ../atlases/zombie-commuter.png sources/screamer-walk-guide.png
python3 guides/bloater_walk.py ../atlases/zombie-heavy.png sources/bloater-walk-guide.png
python3 guides/bloater_north.py ../atlases/zombie-heavy.png sources/bloater-north-guide.png
python3 guides/screamer_corpses.py ../textures sources/screamer-corpses.png
python3 guides/bloater_corpses.py ../textures/zombie-heavy sources/bloater-corpses.png
# the generated sheets are not reproducible offline; they are committed under sources/
python3 extract.py
python3 ../../../../../tools/sprites/build.py   # copies the textures into assets/sprites/
```

Run from this directory. `npm run sprites:check` proves the copies match.

## What is still open

Like study 01: no attack, hit, death-transition or rising states, and an idle that is one pose.
The screamer's scream and the bloater's burst are sim events with no animation of their own.
