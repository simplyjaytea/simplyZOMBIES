# The inventory, redone — 2026-10-19

The owner's ask (alpha plan Q5): keep the Tarkov-style grid, but it "looks very plain" and has to
look "super awesome, unique, bespoke". Decided alongside it: a fast list view sits next to the
grid, with the grid still the authority on capacity.

## Mockups

Three directions drawn at 1920×1080 with the repo's own item icons, at the world's 2× density:

- `mockup-A-canvas-webbing-1920x1080.png` — olive canvas, stitched webbing, MOLLE loops.
- `mockup-B-salvage-locker-1920x1080.png` — brushed steel, rivets, masking-tape labels,
  class-tinted plates. **Built.**
- `mockup-C-hard-case-1920x1080.png` — a black hard case with foam cut-outs.

B was picked by Claude and built straight away; the owner was sent all three on a decision card
and can redirect.

## Captures

Native viewport captures from the playable scene (Compatibility renderer, Xvfb/Mesa llvmpipe).
Before is `main` at bf6b41a, after is this branch; both from the same throwaway driver, which
boots the scene, puts on a frame pack, a chest rig, a medic pouch, a gas mask, a kitchen knife and
a service pistol, stows sixteen things, stands a cupboard beside the player and opens it, cuts the
left arm and the right leg, and selects the pump shotgun. The driver was deleted afterwards.

- `*-inventory.png` — the open sheet, Tab pressed.
- `*-hud.png` — the closed sheet at the open cupboard: the transfer window and the quick strip.

At 1920 the sheet shows the survivor, the carried bags and the cupboard side by side, the list
and the inspect pane down the right, and the strip along the bottom. At 1280 the right column
gives way to two lanes while a container is open (docs/32's "source and destination visible
together"), so the inspect pane and its buttons are not on screen there until the box is closed;
the right-click menu still offers every verb.

What these do not show: a drag in progress, the refusal stripes and the ghost, a filter chip in
force, or the item menu. The behaviour behind each is held by `godot:check:inventory`,
`godot:check:ui_skin` (CURSORS) and `godot:check:play`.
