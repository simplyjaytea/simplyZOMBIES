simplyZOMBIES - Zombie animation and corpse study 01
2026-10-02

GAME INTEGRATION
The native textures are registered in godot/assets/sprites/authored.json and
selected by zombie/player content in the Godot game. The authored, topdown,
appearance and zombie_art gates verify their runtime readers.

CONTENTS
7 zombie designs: workwear, commuter, raincoat, stalker, runner, armored, heavy.
Each has four directional idle poses and a four-frame locomotion loop in each
direction: south, east, north, west. That is 28 idle PNGs and 112 motion PNGs.
Each zombie also has a supine and a prone corpse pose (14 total).
The human corpse set adds supine, prone, side, and diagonal supine poses.
Total: 158 individual PNG sprites, plus 7 animation atlases.

OPEN FIRST
previews/zombie-walks.gif - animated review of all four directions, all variants.
previews/zombie-walks.png - the same animation as APNG.
previews/contact-sheet.png - all designs, directions, and corpse poses at 2x.
previews/motion-contact.png - selected animation phases for static inspection.
previews/human-matte-review.png - human poses on dark and light backgrounds.

PLAYBACK AND METADATA
manifest.json lists each asset, dimensions, anchor, frame paths, FPS, and loop.
The atlas rows are south/east/north/west. Columns are idle/walk00/01/02/03.
Use nearest-neighbor sampling; avoid filtering or mipmaps for the native sprites.
Workwear, commuter, raincoat: 5 fps. Stalker: 6. Runner: 9. Armored/heavy: 4.
These are the game frame rates. Velocity chooses idle or walk; the simulation
tick advances the walk cycle, with a stable phase offset for each body.
The manifest calls locomotion "walk" for compatibility; the runner uses a sprint.
Idle is a single pose per direction, not an animated breathing state.

SIZES AND ANCHORS
Most living frames: 32x40, bottom-boundary anchor [16,40], sole on row 39.
Heavy: 40x48, bottom-boundary anchor [20,48], sole on row 47.
Ordinary corpse: 48x40 with center ground anchor [24,20].
Heavy corpse: 56x40 with center ground anchor [28,20].
Human corpse: 48x40 with center ground anchor [24,20].
Body occupancy is approximately 28px tall, with the heavy about 34px.
Anchors are in pixel coordinates from top-left; the bottom boundary equals
canvas height. The renderer uses feet for live bodies and centers for corpses.
The heavy uses its declared canvas for rendering and mouse picking.

WHAT STILL NEEDS PRODUCTION WORK
The artwork includes locomotion and settled corpse poses. Attack, hit, death
transition, rising, and animated idle states are not included.
The armored base has no painted helmet or vest. Its actual inventory equipment
composes over the living sprite and drops through the existing death path.
Original composed studies are preserved as sources/*-composed-study.png only.
Shamblers select workwear/commuter/raincoat by stable entity id; stalker, runner,
armored and heavy content each selects its own animation family. Corpse art
matches the original family and tint. Zombie remains keep the most recent 256
positions in save data without adding entities, collision, scent or loot.
Human corpses retain their existing inventory and simulation behavior; their
standing equipment overlays are omitted on the ground poses.
All settled corpse pictures are Focal-only. Crawler stance artwork is not added.
Bloater and screamer are outside this first set.
The generated frames retain small shape/detail variation and 1-3 native pixels
of vertical pose variation, most visible in runner side views. A production
polish pass should tune foot contact and stabilize incidental clothing detail.

CHECKS COMPLETED
All 28 directional locomotion groups contain four distinct native RGBA frames.
Every group changes silhouette, rather than being translated duplicate frames.
Exports have transparent pixels and nonempty bodies, with no side clipping.
The source sheets and native contact sheets were visually inspected.
Living frames share foot pivots and use one fixed scale per character family.
The 4-second animated preview loops at the assigned per-family frame rates.
The native review contains actual frame changes; no tween or fake sliding.
The focused Godot gates verify live frame selection, stopped and paused bodies,
content variants, settled poses, Focal filtering, save/load and unchanged death
bookkeeping. See docs/23-roadmap.md for the complete integration evidence.

SOURCE AND REPRODUCTION
sources/ contains original generated sheets and a relative index.
references/ contains isolated standing studies used for animation generation.
prompts.json, sources/human-generation.json and
sources/armored-underlay-generation.json preserve generation instructions.
extraction.json records source rectangles, scales, resized sizes, and placement.
qa.json records native frame uniqueness and occupied heights by direction.
build_pack.py reproduces native PNGs, atlases, metadata, and the main previews.
Dependencies: Python 3, Pillow, numpy, scipy; DejaVu Sans for preview labels.
Run from any working directory: python /path/to/this/pack/build_pack.py

The export script performs only mechanical crop, nearest-neighbor resize,
padding, alignment, and composition. Alpha >=128 is used only to find body
bounds. The source RGBA pixels are preserved; backgrounds are not algorithmically
removed, and sprites are not procedurally repainted or recolored.
The near-opaque partial alpha in the generated sources remains in the exports.

Project reference revision inspected: f770edc6bcb7d477f045bdae2c9043da491ce1f7.
New art was generated with the built-in image generation tool from project
character references. No third-party game sprites were extracted or copied.
