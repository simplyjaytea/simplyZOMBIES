# simplyZOMBIES — UI Field Kit

A bespoke survival pixel UI built from the approved olive, charcoal, cream and amber
mockups. Includes transparent sprites, scalable frames, live-text examples, UI
animations, an offline browser preview and a standalone Godot demo.

**Repository delivery:** resources live at `res://art/simplyzombies-ui/`.
The live game UI has not been reskinned; the preview and demo do not alter game state.

## Start here

- Open `simplyzombies-ui-preview.html` in a browser. Everything is embedded; no
  server, network, installation or account is needed. Click the top tabs and items.
  Tab / Enter navigate controls; Escape opens the pause screen.
- Open the game’s `godot/project.godot`, then run
  `res://art/simplyzombies-ui/demo/demo.tscn` with F6. The native demo exercises
  buttons, settings controls, equipment slots and all four animations.
- See `previews/simplyzombies-ui-catalog.png` for the set and
  `previews/simplyzombies-ui-motion.gif` for motion. One-shot effects are retriggered
  in the GIF so they can be inspected repeatedly.

## Contents

| Set | Logical assets | Native exports |
| --- | ---: | ---: |
| Panels, buttons, slots, tabs | 24 | 24 PNGs |
| Equipment and action glyphs | 32 | 32 at 24 px + 32 at 16 px |
| Settings controls and cursors | 16 | 16 PNGs |
| UI animations | 4 | 16 frame PNGs |
| **Total** | **76** | **120 PNGs** |

Also included: a 512 × 512 atlas and region map, 24 StyleBoxTexture resources,
four SpriteFrames resources, a native Theme, pixel-font configuration, cursor
hotspots and an optional CanvasItem drawing helper. PNG totals exclude the atlas,
source sheets, previews and existing game art included for demonstration only.

## Import into simplyZOMBIES

1. The resources are already installed at **`godot/art/simplyzombies-ui/`**.
2. Assign `res://art/simplyzombies-ui/theme.tres` to a Control subtree. Set its
   texture filter to Nearest. Use whole-pixel positions and integer display scales.
   Import PNGs losslessly, with mipmaps disabled.
3. The current game's `ui/chrome.gd` draws directly onto CanvasItem. A Theme will
   not change those calls. Use the StyleBoxTexture resources or `ui_skin.gd` in
   those draw helpers; see `docs/integration.md`. This kit does not replace game code.
4. Load an animation `.tres` onto AnimatedSprite2D and play its named animation.

`manifest.json` is the canonical runtime inventory. Nine-slice margins are left,
top, right, bottom; atlas rectangles are x, y, width, height. Exported settings and
cursor IDs begin with `control_` to avoid collisions with frame texture names.

## Motion

| Animation | Frames | FPS | Behavior | Reduced-motion frame |
| --- | ---: | ---: | --- | ---: |
| `focus_pulse` | 4 | 6 | Loop | 0 |
| `busy` | 4 | 8 | Loop | 0 |
| `item_ping` | 4 | 12 | One shot | 0 |
| `saved_tick` | 4 | 10 | One shot, hold completion | 2 |

Frames share bounds and anchors. The HTML preview honors the operating system's
reduced-motion setting on startup and has a manual override. The Godot demo has
the same manual option; connect it to the game's accessibility setting at integration.

## Visual rules

- Worn frames, warm labels, amber focus and restrained rust warnings.
- Keep labels as real, localizable text. Preserve keyboard focus.
- Keep the gameplay center open. No health, needs or threat gauges, enemy counts,
  infection-certainty labels or numerical condition percentages are introduced.
- Inventory stays equipment / carried / inspect. Gear remains separate from the
  base survivor. The preview’s sample counts and shortcut numerals do not amend the
  game’s information and digit bans; live integration must keep those gates green.
- Pause rows: Resume, Save, Load, Settings, Quit to title. No numeric state readout.
  Helper: “Returning to title saves your progress.”

## Source and rebuild

`sources/` preserves generated art and cleaned RGBA sheets. The original RGB source
sheets contain a baked checkerboard; only `*-rgba.png` and runtime exports have real
transparency. Approved mockups are in `previews/`; source requests are in `prompts/`.
Runtime PNGs use binary alpha, zero RGB outside alpha, and nearest-neighbor resampling.

The user authorized deterministic pixel cleanup and export. `tools/build_assets.py`
reproduces that process using Pillow, NumPy and SciPy. Mask thresholds, extraction
rectangles and shared animation bounds are in `docs/extraction.json`.
`tools/build_theme.gd` rebuilds Godot resources; `tools/build_preview.py` rebuilds
the embedded browser preview. `demo-assets/` holds existing survivor and item art
from the earlier game pack, solely for context; these are not new UI assets.

## Validation

Validated with **Godot 4.7.1**: PNGs, styles, Theme, font, drawing bridge and animation
resources load; the demo starts; reduced motion freezes intended frames; one-shot
playback ends correctly. Transparency, atlas pixels and frame dimensions are checked.

The HTML preview's exact canvas renderer was rendered offline and visually inspected
in all four views, and its input handlers were exercised. A browser-window smoke test
was unavailable in this environment; browser-specific font loading and DOM events
remain an integration check. Reports are in `docs/*validation.json`.

## Typography and attribution

VT323 is bundled with its SIL Open Font License in `fonts/`.
The original TTF is unchanged; `VT323-Pixel.res` configures Godot rasterization.
Copyright 2011, The VT323 Project Authors.

- Font: <https://github.com/google/fonts/tree/main/ofl/vt323>
- License: <https://github.com/google/fonts/blob/main/ofl/vt323/OFL.txt>

Keep `OFL.txt` with redistributed fonts. UI art was generated for this project from
the approved direction. No textures were extracted from ZERO Sievert.

Sources and prompts are provenance, not repository instructions. Non-runtime source,
preview and tool directories use `.gdignore` to avoid unnecessary engine imports.

Repository verification, including the interrupted full-suite run, is recorded in
[the delivery receipt](docs/repository-delivery.json).
