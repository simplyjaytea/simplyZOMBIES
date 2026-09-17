# Nature, props and searchable containers

33 native transparent sprites: eight nature objects, sixteen interior/street props, and three container families with closed, open-with-supplies and empty states.

Designed against the official ZERO Sievert outpost, combat and bunker screenshots supplied in the parent reference directory, with original silhouettes and materials. The target world tile is 32 pixels and the approved survivor occupies 28 pixels in height. The trees occupy about three character heights; barrels, furniture and storage are sized to the same scale.

`manifest.json` gives each asset's relative PNG path, logical canvas size, bottom ground anchor, atlas rectangle and category. `stateGroups` links each searchable container's three states. All container states use a 32×32 canvas and the same `[16,30]` ground anchor. They are discrete state swaps, not a continuous lid-opening animation.

`props-atlas.png` contains all 33 sprites. `native/` contains the separate production PNGs. `previews/` contains inspected native-plus-4× contact sheets and `container-states.gif`, an actual animated state preview. `validation.json` records RGBA, dimension, transparent-corner, unique-state and matching-ground-baseline checks.

The built-in image generation tool produced all artwork. `sources/`, `prompts/`, `source-crops/` and `extraction.json` preserve provenance. `extract-props.py` performs only crop, nearest-neighbor resize, padding, atlas packing and preview composition. Source RGBA alpha is retained; no background was painted out or replaced programmatically.

Pixel-art import: nearest-neighbor filtering; no mipmaps or lossy texture compression. These static prop assets do not include collisions or occlusion polygons. Exact four-tone-per-material quantization has not been imposed. Some native edges retain fractional alpha from the source; there is no baked checkerboard or ambient glow background.
