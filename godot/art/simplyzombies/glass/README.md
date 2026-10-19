# Window glass

Until 2026-10-19 `main.gd`'s `_draw_window_glass` drew a window as two `draw_rect` calls: a rim
and a pane. These six textures are that window as art, at the same geometry: an east-west pane, a
north-south pane, and a square pane, each with its frame. Declared as
`glass_{pane,frame}_{ew,ns,square}` in `godot/assets/sprites/authored.json`, named by the street
dressing's `faces.glass` (`godot/content/dressing/street.json`) and read through
`Dressing.glass_keys`; `check_topdown.gd`'s GLASS lane holds them to the rects' geometry and to
greys, and holds the draw to them.

| texture         | canvas | tinted by                                |
| --------------- | ------ | ---------------------------------------- |
| `pane-<shape>`  | 32x32  | the window tile's colour, lightened 0.28 |
| `frame-<shape>` | 32x32  | `Palette.COLOURS["windowRim"]`           |

They are greys on purpose. The colour still comes from the palette and the street dressing, so
night, weather and a lit window keep working as before; the texture adds the lintel shadow, the
mullion and the lit streak the flat rect could not. `glass.py` draws them in code, because a
32-pixel window is a handful of pixels an image model would not place exactly.

```bash
python3 glass.py
python3 ../../../../tools/sprites/build.py
```
