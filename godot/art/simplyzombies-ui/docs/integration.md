# Godot integration

The runtime folder must resolve to `res://art/simplyzombies-ui/`. Resource paths
have no dependency on the standalone demo.

## Existing CanvasItem UI

The game's `ui/chrome.gd` requires explicit integration. Example from `_draw()`:

```gdscript
const Skin = preload("res://art/simplyzombies-ui/ui_skin.gd")
const Bag = preload("res://art/simplyzombies-ui/glyphs/glyph_back.png")

func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
    Skin.draw_panel(self, Rect2(20, 20, 280, 400), "panel_standard")
    Skin.draw_panel(self, Rect2(40, 70, 48, 48), "slot_selected")
    Skin.draw_icon(self, Bag, Vector2(52, 82))
```

Or preload a StyleBoxTexture and call `style.draw(get_canvas_item(), rect)` directly.
The helper duplicates styles when applying opacity to preserve shared resources.
Call `queue_redraw()` when state changes.

## Native Controls

```gdscript
theme = preload("res://art/simplyzombies-ui/theme.tres")
texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
$DropButton.theme_type_variation = "DangerButton"
$SlotButton.theme_type_variation = "SlotButton"
$SlotButton.toggle_mode = true
```

The Theme covers Button, Panel, PanelContainer, PopupPanel, CheckBox, CheckButton,
TabBar, HSlider, VScrollBar, LineEdit and tooltips. Variants are `DangerButton`,
`SlotButton`, `InsetPanel`, `MutedLabel`. Other Godot Control classes may need styles.
Keep rectangles larger than the sum of their corner margins. Preserve whole-pixel
positions, nearest filtering and integer texture scales.

## Animations

```gdscript
$Saved.sprite_frames = preload("res://art/simplyzombies-ui/animations/saved_tick.tres")
$Saved.animation = "saved_tick"
$Saved.stop()
$Saved.play()
```

Names match resource filenames. Stop before replaying to restart at the beginning.
For reduced motion, stop and set the zero-based static frame in the manifest.
Saved tick uses frame 2: the completed check without the final sparkle.

## Cursor hotspots

| Cursor | Native size | Hotspot |
| --- | --- | --- |
| Arrow | 24 × 24 | (6, 2) |
| Hand | 24 × 24 | (9, 2) |
| Move | 24 × 24 | (12, 12) |
| Blocked | 24 × 24 | (12, 12) |

Pass the Texture2D and hotspot to `Input.set_custom_mouse_cursor`. Scale both
together if preparing larger cursor images.

## Atlas

`atlas.png` is 512 × 512 with a two-pixel transparent gutter. `atlas.json` maps every
export, including variants and animation frames. Godot styles and animations use
individual PNGs for editing convenience. To use the atlas, create AtlasTexture
resources using these rectangles and replace the relevant Texture2D references.
Disable mipmaps and use nearest filtering; linear-sampling color extrusion is not provided.

## Rebuild and verify

From the repository root:

```sh
python3 godot/art/simplyzombies-ui/tools/build_assets.py
godot --headless --path godot --editor --import --quit
godot --headless --path godot --script res://art/simplyzombies-ui/tools/build_theme.gd
python3 godot/art/simplyzombies-ui/tools/build_preview.py
python3 godot/art/simplyzombies-ui/tools/validate_assets.py
godot --headless --path godot --script res://art/simplyzombies-ui/tools/validate.gd
node godot/art/simplyzombies-ui/tools/verify_preview.cjs
```

Python needs Pillow, NumPy and SciPy. The optional Node check needs `@napi-rs/canvas`
on the module path. These dependencies are unnecessary for using the art, opening
the HTML preview or running the Godot demo. Use PNG/SpriteFrames assets in-game;
the GIF is for preview only.
