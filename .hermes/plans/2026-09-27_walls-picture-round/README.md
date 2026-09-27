# The walls picture round, 2026-09-27

docs/30, "The whole outpost pack, 2026-09-25" -> "The walls get a picture round first": one closed
building drawn two ways, for the owner to pick from before "The walls are modules" (docs/23's
outpost group) lands. Nothing here is decided and nothing under `godot/` changed.

## The scene

One render (cream plaster) building, 7 x 5 tiles, on the pack's grass, board floor inside.
South wall: wall, wall, window, door, window, wall, wall. East wall: one window in the middle of
the run. Every picture uses the same map, the same pixel origin and the same scale -- 32 px a
tile at 2x, 64 screen pixels a tile -- in daylight, which here means no light modulate at all.
Roofs are left off in every option so all four sides and both south corners can be seen, as if
the survivor stood inside.

## The pictures

- `b-generated-faces.png` -- **option B**, today's generated faces. Reproduced tile by tile from
  `main.gd`'s `_draw_district` arms by the driver (not a capture of the running game): a wall
  tile with open ground to its south draws `wall_render_face`, every other wall tile
  `wall_render_cap`; the south windows are the face plus `face_window`, the east window is the
  cap plus the procedural pane `_draw_window_glass` draws; the shut door is `_draw_solid_tile` in
  the palette's `door` colour. Each wall is a whole tile of mass.
- `a2-pack-corners-by-shape.png` -- **option A**, the pack's modules. The east-west runs are
  32-wide slices of the 64 x 48 modules (`wall-plaster`, `wall-window-intact`,
  `wall-door-closed`), feet on the tile's south edge, so each one overhangs the tile north of it
  by a quarter tile. A run's west end takes the module's west half, its east end the east half,
  a middle tile the middle 32 px, and a door or window the middle 32 px of its module. The
  north-south runs are **the corner piece's leg, cropped** (native x 0..16 of
  `wall-corner-nw`, x 47..63 of `wall-corner-ne`, a 16-row band repeated), running from under
  the north run's cap to the south run's cap. The pack's two corners stand at the building's
  **south** corners, because that is what they draw: a west (or east) leg coming down onto a
  south face.
- `a1-pack-corners-by-name.png` -- **option A, corners by their names.** The same, except the
  pack's `wall-corner-nw` and `wall-corner-ne` stand at the building's north corners, as their
  names say, and the south corners are the south run's end halves with the legs landing on them.
  Shown because the name and the shape disagree; the legs poke a tile up past the north wall.
- `compare-closed-a1-a2-b.png` -- the three closed buildings side by side, A1, A2, B.
- `compare-open-door-ns-run-1to1.png` -- **A2 with the door open** (`wall-door-open`) beside
  **B with the door open** (the threshold boards plus `face_door`), a 1:1 crop of the 2x render:
  the south-west corner, the west north-south run and the doorway.

## What the pack does not have, visible in the pictures

- **No north-south run.** A's west and east walls are a crop of the corner's leg; the leg is
  17 native px wide, about half a tile, so the other half of the wall tile shows floor. The
  sim's wall tile is still a whole tile.
- **No south-west or south-east corner** by name. A2 uses the named north corners at the south,
  where their shape fits; A1 uses them where their names fit and improvises the south ones.
  Either way a corner's horizontal part is 32 native px tall against the module's 40, so in A2
  the cap steps down where a corner meets the run, and the leg the corner brings has a rounded
  top that shows a seam where the cropped leg above it ends.
- **No east-west door or window.** The east wall's window has no pack piece, so in both A
  pictures that tile is plain leg -- the window is there in the sim and missing from the
  picture. B draws its pane.
- **No timber or block material.** Only brick and cream plaster exist, and only plaster has
  corners, a door and windows, which is why the building is plaster. Timber and block keep
  their generated faces either way (docs/30).

## Reproducing

`walls_round.gd` is the throwaway driver, labelled prototype, kept here only to reproduce these
pictures; nothing under `godot/` loads it. From the repository root:

```
<godot 4.7.1> --headless --path godot --script "$PWD/.hermes/plans/2026-09-27_walls-picture-round/walls_round.gd"
```

It needs an imported project (`npm run godot:smoke` once) and prints `WALLS_ROUND_DONE`.
