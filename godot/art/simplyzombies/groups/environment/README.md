# Environment library

33 original native assets for the compact simplyZOMBIES art direction: 12 opaque 32×32 terrain tiles, eight transparent 32×32 overlays, and 13 architecture pieces. The visual references were the official ZERO Sievert outpost, bunker, and combat screenshots in the parent project's `references/` folder. No source-game sprites were extracted.

Use `manifest.json` as the asset index. Every asset has a relative PNG path, dimensions, category, and pixel anchor. The three native atlases include explicit regions and anchors. Individual PNGs are the canonical imports.

## Placement

- Terrain and overlays use an upper-left anchor `[0, 0]` on a 32 px grid.
- Straight walls and door/window states are 64×48 with ground anchor `[32, 44]`. Their face occupies approximately 40 px; the open door extends a few pixels past the front wall base.
- Corners are 64×64 with anchor `[32, 64]`.
- Horizontal fence is 64×32 with anchor `[32, 32]`; vertical fence is 32×64 with anchor `[16, 64]`.
- Gate states are 64×48 with shared anchor `[32, 32]`; the open gate projects below that baseline.
- Render terrain first, then ground overlays, then sort architecture and characters by their ground anchors. Use nearest-neighbor filtering at integer scales.

The four grass fringes are decorative transition overlays. They are not a complete corner/junction autotile set. Road lines are vertical; rotating the sprites by 90° provides horizontal road markings.

## Interaction states

The door, window, and gate each have two discrete states. They switch sprites when the game changes state. These pairs are not intermediate animation cycles. Their native canvas, module width and pivot are normalized, but wear details and some source perspective differ between states. The state preview GIF makes these differences inspectable. Collision, exact wall adjacency, and engine TileSet rules still need integration.

## Sources and validation

Artwork was generated and refined with the built-in image generation tool. All prompts and original sheets are preserved. `extract.py` performs only mechanical cropping, nearest-neighbor scaling, padding, mirroring, atlas composition, and preview composition. It does not repaint pixels or remove backgrounds. The eastern corner is mirrored during extraction to correct the generated handedness. Crop coordinates are saved in `extraction.json`.

All 12 ground tiles are opaque; architecture and overlays retain genuine RGBA transparency. A few native edge pixels retain partial alpha from the source. The style aims at restrained flat material palettes, but this export does not claim a strict four-color palette validation.

`previews/environment-contact.png` shows every native sprite enlarged with nearest-neighbor sampling. `previews/terrain-repeat-2x2.png` repeats every terrain tile. The repeat was visually inspected: the flat ground has no bevel or dark square border. The checker floor intentionally alternates teal and cream at its wrapped edge, so its numerical edge difference is high while its checker geometry repeats correctly. `previews/validation.json` records sizes, nonempty pixels and alpha counts.

To reproduce the native exports from the included sheets, run `python extract.py` with Pillow installed. The preview text uses the local DejaVu Sans font path in that script.
