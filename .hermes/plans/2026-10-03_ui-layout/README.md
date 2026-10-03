# Playable UI at 1280×720 and 1920×1080 — 2026-10-03

Native viewport captures from the playable Godot scene, Compatibility renderer on Xvfb/Mesa
llvmpipe. The same fixed boot seed and frame-pack loadout are used before and after. The
simulation is held still by the capture driver after entering the run; this is layout evidence,
not a campaign or performance measurement. The throwaway driver is removed after capture.

At each resolution, compare files with the same suffix:

- `inventory`: all twelve equipment slots, healthy condition chart, pockets, full-width frame
  pack and its inspect description. At 1280 the old inspect pane covers the pockets and pack,
  while the old stance, condition and footer collide; the responsive sheet separates them.
- `pack`: the bag column scrolled down. All seven native 56-pixel cells of the frame pack fit
  beside the inspect pane; vertical scrolling is still how a tall pack is reached. At 1920 this fixture fits without
  scrolling, so the two inventory views match.
- `condition` / `condition-scrolled`: all ten parts hurt, a deliberate fixture. The condition
  list wraps and the wheel over the survivor panel reaches its last row independently of the
  bag column. Its hint names the wheel only when there are more rows than fit.
- `work`: Work's full set of priority columns. At 1280 the old fixed panel loses its rightmost
  columns beyond the window. The responsive grid stays within its frame; its height follows
  the roster and leaves the bottom bars clear. The corner chart is hidden while Work or the
  skill web is open, including while soft-paused.
- `hud`: the corner chart, action bar and six-slot quick strip during play. The D2 chart's
  earlier upward shift already clears the action bar; the historic action-bar overlap is stale.
- `title`, `pause`, `settings`: existing menu layouts, checked at both sizes. No reproduced
  clipping in these menu frames and no menu redesign in this slice. The before pause/settings
  captures also expose an old bag-grid child left visible after closing inventory; the after
  captures hide it with the rest of the sheet.
- `item-menu`: an item action menu requested at the bottom-right corner, nudged back inside
  the viewport by the existing menu placement.

The compact sheet uses the existing chart at integer 2×, with 20-pixel text where needed; the
wide sheet keeps its 3× chart and existing text ladder. Native bag cells, kit frames, typeface,
prose read models, the six quick keys and the command queue remain the same. Equipment names
and dense Work column labels still use the existing fitted-text convention; inspect supplies
an item's full description.

This verifies the named panels at the two supported review sizes. It does not establish layouts
below 1280×720, every possible long item/learning description, or a human ten-day playtest.

Validation: `godot:check:inventory` (new LAYOUT), `godot:check:play` (new WORK-LAYOUT),
`godot:check:ui_skin`, `godot:check:hud` and `godot:check:respond` passed. LAYOUT covers
nonoverlap and native bag width, slot/condition bounds, scrolling to both ends, hidden bag
visibility and rejection of a drop below the clip. WORK-LAYOUT resizes the actual scene, sends a
mouse click through the viewport to the last Work column, and checks chart hiding/restoration
with Work and the skill web while soft-paused. An eight-row view at 1280 also wheels to both
clamped ends and routes the last visible priority click to the displayed survivor. The final
PLAY rerun passed in 27.62 runner seconds with no lane skipped. The subsequent combined
integration passed all 85 Milestone 2 gates in 47m16s (2835.79 runner seconds), including these
lanes; docs/23 records the full-chain result separately from the focused runs above.
