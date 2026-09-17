# Compact survivor wearables

Four original items, each with south, east, north, and west views: olive utility vest, tan canvas backpack, olive steel helmet, and graphite respirator. Sixteen isolated equipment PNGs and four horizontal atlases are included. All frames use a transparent 32×48 canvas and ground anchor `(16, 40)` so they can be drawn over the approved compact survivor at the same canvas origin.

The survivor is not included in any wearable texture. Preview composites use the unchanged approved survivor for fit inspection only.

## Layering

Draw the base human at z=0. Use each asset's `z_by_direction` from `manifest.json`:

| Item | South | East | North | West |
|---|---:|---:|---:|---:|
| Vest | 2 | 2 | 2 | 2 |
| Backpack | 3 | -1 | 3 | -1 |
| Gasmask | 4 | 4 | 4 | 4 |
| Helmet | 5 | 5 | 5 | 5 |

The south backpack texture contains front shoulder straps, while north shows the exterior. Side backpack textures sit behind the body so the body naturally occludes part of the strap. The rear gasmask view contains the head harness. The helmet is drawn last and covers the upper mask harness when both are equipped.

## Scope and fit limits

These are static, direction-specific overlays fitted to the approved standing survivor. They have been inspected individually and as a full loadout on all four idle views. Their short torsos and open vest armholes leave room for the existing walking arms, but the overlays do not include individual walk-frame deformation, arm masks, recoil, or head bob. Per-frame rigging should be added when the character's final equipment attachment system is integrated. They do not replace clothing or underwear on the base sprite.

Only nearest-neighbor resize, alpha-bound crops, padding, and composition were used after image generation. The fitted boxes sometimes use different horizontal and vertical resize ratios to match the compact body. Original RGBA values, including a few partially transparent edge pixels, remain intact. The palette is visually restrained, but an exact color-count gate has not been applied.

## Files

- `native/`: 16 individual overlays and four 128×48 atlases.
- `manifest.json`: relative paths, sizes, pivots, directional states, z order, source crop bounds, and fit placements.
- `sources/`: four final transparent source sheets. Rejected opaque backpack attempts are excluded.
- `prompts/`: generation and successful transparency-cleanup prompts.
- `source-crops/`: original crop pixels before fitting.
- `previews/wearable-fit-contact.png`: equipped idle fit sheet at 5× nearest-neighbor.
- `previews/wearables-only-contact.png`: isolated gear sheet at 4× nearest-neighbor.
- `extract.py`: reproducible extraction and preview composition, using the existing approved character pack as a preview reference.

Artwork was created with the built-in image generation tool using the approved survivor reference and the shared world style. ZERO Sievert screenshots informed the compact silhouettes and muted palette; no game sprites were extracted or copied.
