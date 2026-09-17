# Shared production direction

User approved the revised compact ZERO Sievert-like survivor and shambler, and now asks the other game assets to match, including flashes and animations. Build original artwork informed by the original game's screenshots; do not copy logos or extract its sprites.

References: `references/zero-outpost.jpg` (official Steam screenshot); `references/zero-combat.png` and `references/zero-bunker.png` when available. Approved characters: `../character-revision/pack/character-design-contact.png` and `../character-animation/pack/textures/characters/`.

Camera: consistent elevated top-down 3/4 game view, north-facing wall fronts visible, no isometric diamond projection. World tile 32 px. People occupy28px on32×48canvases. Strong near-black stepped outlines, broad readable shapes, restrained3–4flat shades per material. Sparse deliberate wear. Avoid gradients, bevelled terrain tiles, noisy miniature-photo textures and gratuitous detail. Original artwork only.

Palette families: forest olive/pine green; dusty ochre soil; cool slate asphalt; worn cream plaster/red-brown brick; faded teal and olive painted metal; warm desaturated wood; graphite weapons with limited silver highlights. Effects add pale yellow/orange flashes, rusty red blood, cool gray smoke. Transparency genuinely RGBA; no checkerboard painted into the asset.

Size guidance: terrain32×32; short wall modules64×48 and corner64×64; tree64×96 or80×96; bush32×32; rock32×24; barrel24×32; small container32×32; cabinet32×48; bed48×32; table48×32; bench48×24; sign24×40; car96×48; truck112×56; generator40×32; item icon24×24 or32×32; held firearm32×16 or48×24. Occupied shapes can be smaller than padded canvases. Shared ground pivots required.

Every group exports a manifest.json with assets array. Each asset includes id, label, category, path (relative to group folder), size, anchor in pixels; animated assets include frames (e.g. idle:[{path:...}]), fps, loop boolean and clear state names. Held weapons additionally include grip and muzzle coordinates. Use unique ids with family prefixes (tile-, wall-, prop-, nature-, vehicle-, item-, weapon-, fx-, ui-). Actual sprite frames must change shape, not just be duplicate recolors or moved copies.

Use built-in imagegen for all new art and visual edits, inspect references first. Mechanical crop, nearest-neighbor resize, padding, atlas/preview composition and timing in code are allowed; do not procedurally repaint sprites or remove backgrounds. Check actual alpha. If a sheet has a baked checkerboard, request an imagegen background-removal edit; a short prompt often works. Preserve source artwork, prompts and extraction metadata. Keep each group inside its owned directory. Do not edit another group's files.

Do not call unfinished animation a finished action set. Each deliverable must include native PNGs, usable metadata, source and an inspected contact sheet. Looping/effect assets need an actual frame animation preview. Keep the work bounded to assigned groups, and report any material defect without hiding it.
