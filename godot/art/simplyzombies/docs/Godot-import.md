# Godot 4 import notes

These are import instructions and generated resources for the delivered art pack. All 20
SpriteFrames resources and their textures were imported and loaded successfully in a temporary
Godot 4.7.1 project (`OUTPOST_RESOURCES_OK`). This verifies the resource files and paths; the
game's renderer has not yet been connected to them. The HTML showcase is a separate renderer.

## Files and texture settings

The pack is already checked in at `res://art/simplyzombies/`, preserving `manifest.json`,
`textures/`, and `groups/`. The generated SpriteFrames files under `docs/godot/` reference that
location. For a different project, copy the pack to the same path or rerun
`export_spriteframes.py` with `--prefix` set to its destination. Source and preview folders
carry `.gdignore`; native texture folders do not.

Use Lossless compression for these PNGs. Preserve their RGBA alpha; terrain is intentionally opaque. Godot documents Lossless as the appropriate pixel-art import mode. Keep mipmaps disabled for this pack's intended native or integer-enlarged presentation. [Image import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)

Set the relevant CanvasItem's `texture_filter` to `CanvasItem.TEXTURE_FILTER_NEAREST`, or inherit it from a configured parent. In Godot 4 this is a CanvasItem setting, rather than the old texture import filter switch. Keep camera enlargement and sprite scale at integers for the crispest presentation. [CanvasItem texture filters](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#enum-canvasitem-texturefilter)

## Playback and ground anchors

Assign a generated `.tres` to an `AnimatedSprite2D.sprite_frames` property. SpriteFrames stores named frame sequences, speed, and looping settings; the node handles playback. For a static object use its individual PNG on a Sprite2D instead. [SpriteFrames documentation](https://docs.godotengine.org/en/stable/classes/class_spriteframes.html)

This pack stores anchors as pixel coordinates from the image's upper-left corner. Set `centered = false` and set `offset = -anchor` so the node's position is the declared ground/contact point. The approved survivor and shambler use 32×48 canvases with anchor `(16, 40)`. For them, the offset is `Vector2(-16, -40)`. Other assets have their own anchors in `manifest.json`; do not apply the human anchor to a tree, effect, or weapon. [AnimatedSprite2D properties](https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html)

```gdscript
# Example on an existing Node2D that owns an AnimatedSprite2D named Body.
@onready var body: AnimatedSprite2D = $Body

func _ready() -> void:
    body.centered = false
    body.offset = Vector2(-16, -40)
    body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    body.sprite_frames = preload("res://art/simplyzombies/docs/godot/survivor.tres")
    body.play("idle_s")

func set_motion(moving: bool, facing: String) -> void:
    # facing must be s, e, n, or w. Facing policy belongs to the game.
    var wanted := ("walk_" if moving else "idle_") + facing
    if body.animation != wanted:
        body.play(wanted)
```

The survivor has four walk frames per direction at 8 fps; the shambler uses 5 fps. Their idle directions are single standing drawings. Preserve the explicit east/west/north/south images instead of assuming mirrored directions. The generated resource index records every animation and its playback settings.

For one-shot effects, follow the asset's `loop: false` setting and remove or hide the effect node when playback finishes. Godot's `animation_finished` signal is emitted when a nonlooping animation ends. Flame and smoke use looping playback. [Animation completion signal](https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html#signal-animatedsprite2d-animation-finished)

## Equipment and effects

Keep the equipment-free survivor texture on its own body node. Vest, helmet, gas mask, and backpack are separate transparent overlays on 32×48 canvases with the same `(16, 40)` anchor. Match their `idle_s/e/n/w` state to the body direction and apply `z_by_direction` from the manifest. These overlays are fitted to standing poses; matching clothing movement to every walk frame remains future rigging work. The current character body itself is a flattened approved animation, not separate animated limb parts.

Held weapons are separate PNGs. Use their `grip` as the weapon's anchor, and place the weapon node at the game's hand attachment point. With `centered = false` and `offset = -grip`, the local muzzle position is `muzzle - grip`. Convert that position through the weapon node's transform when spawning a muzzle effect. Rotating a weapon independently does not require painting it onto the character.

Flashes, hits, splashes, casings, explosion, flame and smoke use their manifest anchors, fps and loop values. Frame duration values in SpriteFrames are relative durations; the exported frames use a relative duration of 1 unless specified otherwise. [SpriteFrames frame timing](https://docs.godotengine.org/en/stable/classes/class_spriteframes.html#class-spriteframes-method-get-frame-duration)

## Engine work still required

Create the scene nodes, collision shapes, actor movement/aim rules, hit logic, effect spawning, equipment attachment logic, and map sorting in the game. Ground tiles fit a 32 px grid. Architecture and interactive containers have discrete state sprites, but no complete collision/TileSet/autotile setup is supplied. A lamp activation and running generator have actual four-frame sequences. This art export does not change the repository or ship gameplay code.
