# A8 evidence: actions, before and after

Rendered from the committed runtime PNGs (`godot/assets/sprites/`), 4x, one row per view
(south, east, north, west; the crawl east and west only).

- `<body>_<action>_before.png` / `.gif`: what the body showed at that moment before A8 -- the
  rest view (a shot, a hit, a stagger, a swing, a reload, a crouch changed no picture), the
  upright walk (a crouched walk, a crawl), or a cut straight to the corpse (a death).
- `<body>_<action>_after.png`: the action's frames (a fall ends on the settled corpse).
- `<body>_<action>_after.gif`: rest, the action at its own rate, rest again (a loop just loops;
  the crouch, one still pose, is shown at 4 fps).

Survivor: swing, recoil, reload, flinch, crouch, crouchwalk, prone, fall. Every zombie family:
lunge, stagger, fall. The swing's east, west and south views are generated; every other frame,
the swing's north view included, is moved from the pack's own pixels (docs/23's A8 record).
