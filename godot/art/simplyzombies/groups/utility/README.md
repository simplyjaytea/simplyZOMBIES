# Vehicles, utilities and HUD sprites

Original art for simplyZOMBIES, guided by the approved compact survivor and the supplied ZERO Sievert screenshots. The sprites use broad shapes, dark outlines, muted materials and nearest-neighbor rendering.

## Contents

- Eight east-facing vehicle sprites: intact and wrecked hatchback, van, pickup and ambulance. Hatchback uses a 96×48 canvas; the larger vehicles use 112×56.
- Generator off plus four-frame running loop; intact/broken wooden barricade; rain collector; stove; worklamp off/on plus four-frame activation; armed/triggered spike trap.
- Sixteen native 16×16 HUD glyphs: crosshair, hand, backpack, health, hunger, thirst, stamina, radio, warning, ammo, lock, work, wound, temperature, map marker and exit.
- Individual RGBA PNGs, generator/worklamp strips, HUD atlas, relative-path manifest, source artwork, exact prompts and extraction metadata.

There are **35 manifest entries**. Eight animation-frame PNGs serve two animation clips; static state entries may point to a frame that is also used by a clip. These counts describe exported assets, not gameplay systems.

## Animation and placement

Use the manifest's pixel anchor as the world ground position. State pairs share canvas dimensions and anchors. Generator and lamp canvases are 40×48 with anchor `[20,44]`, reserving space above the body for exhaust and activation rays. Generator `running` loops at 6 fps. Worklamp `activate` plays at 8 fps and holds frame 4. Vehicles face east and are static; west views can be engine-mirrored if appropriate.

`previews/utility-animations.gif` demonstrates the generator loop and repeated lamp activation with an on-state hold. `previews/animation-frames-contact.png` shows every distinct frame. `previews/world-contact.png` and `previews/ui-contact.png` display nearest-neighbor enlargements of the actual native outputs.

## Authorship and validation

All artwork was generated with the built-in image-generation tool. The animation sheet initially contained a painted checkerboard; a second image-generation edit supplied the final genuine RGBA source. Python only crops, resizes with nearest neighbor, pads, assembles atlases and creates previews. It does not paint or recolor the sprites. Source RGBA is preserved, including partial alpha on some edge pixels.

`extract.py` reproduces native outputs and core metadata from the source sheets. `finish.py` adds atlas metadata and the animation contact sheet. `verification.json` records checks for every path, expected dimensions, alpha and four distinct frames per animation.

Vehicle damage, broken barricades and triggered spikes are alternate static states. Driving, destruction transitions, collisions, interaction logic and engine integration are outside this sprite group. The generator smoke and lamp lighting are baked sprite effects; surrounding scene lighting is an engine concern.
