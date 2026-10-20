# Stations: the well, the latrine and the campfire

Drawn by `tools/sprites/parts/props.py` until 2026-10-19; replaced here in the outpost pack's
manner. Declared as `prop_well`, `prop_latrine`, `prop_campfire` and `prop_campfire_lit` in
`godot/assets/sprites/authored.json`, kind `tile`, each padded (`source.pad`) onto the 32x32 tile
square the way the pack's crates are, so `main.gd::_draw_prop` centres them on their point. The
content entries in `godot/content/props/stations.json` declare `size` as the picture's width over
32, which `check_appearance.gd`'s PROPS lane holds.

| prop          | canvas | how it was made                                        |
| ------------- | ------ | ------------------------------------------------------ |
| well          | 32x29  | guide, one img2img pass, cell 0 cut                    |
| latrine       | 32x28  | drawn by `stations.py`: an outhouse, door gap, moon, vent, ash bucket |
| campfire      | 30x20  | drawn by `stations.py`: stones, ash, two charred logs  |
| campfire, lit | 30x20  | the same ring burning down to embers                   |

`stations.py` paints all four as a guide sheet (`sources/stations-guide.png`). One generation ran
over it (`prompts.json`); only its well was better than the guide. It turned the cold fire's ash to
embers and flattened the latrine's boards, so those two ship as drawn. The lit fire's flames are
`fx_flame_loop`, drawn over the lit picture. The tones reuse `../vehicles/light.py`'s painter: a near-black outline and four tones a
material, lit from the north.

Every prop stands flat on the ground: none is tall enough to sort with bodies, which is what
`check_appearance.gd`'s STANDING lane asserts.

## Rebuilding

```bash
python3 stations.py   # writes sources/stations-guide.png and textures/*.png
python3 ../../../../tools/sprites/build.py
```

Run from this directory. The generated sheet is committed under `sources/`.
