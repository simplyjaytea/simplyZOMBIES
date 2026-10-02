# A2 wall integration supplement — Astra, 2026-10-03

Planning only; no runtime edits or tests. This supplements the required wall section of `.hermes/plans/2026-10-02_art-completion-plan.md`, not a new design choice. A2 is approved. Keep the existing bounded files and generated fallbacks; do not introduce A3, a scene-node renderer, sim changes, or a roof decision.

## Minimal implementation shape

Keep pure topology/placement math in `roof_look.gd`, content-key lookup in `Dressing.wall_modules`, and frame-local placement records in `main.gd` appended to the existing entity sort. A record needs a resolved key, native source/destination rectangles, depth, and explicit owner cells. The `covered` dictionary means **these logical wall cells have replacement art**, not **these screen tiles intersect a sprite**. Resolve keys before reserving cells. Rebuild state-sensitive selection each frame (or use a real map/overlay invalidation key); never cache open/closed state solely by map identity.

Existing `RoofLook.rect_of` is a bounding footprint, not proof that every edge is masonry. `SimTemplates.stamp` copies arbitrary tile and indoors arrays without making a rectangular shell. Validate the actual ring before applying the rectangular A2 mapping: walls/windows/doorways along a closed perimeter, correct inside/outside adjacency, no compound/staggered perimeter or overlapping building ownership. Internal partitions can retain generated rendering. A compound annex, notched footprint, T-junction, or ambiguous segment stays generated; do not turn its bounding box into invented walls. This is a finite supported-topology contract, not a new shape solver.

## Exact native geometry and reservations

Use native pixels with 32 px per tile and scale `zoom / 32`, never squeeze a 64 px corner into one cell. Coordinates below use inclusive perimeter indices W/E/N/S.

| Piece | Authored source | Native destination | Replacement ownership |
|---|---|---|---|
| EW run at (x,y) | 32x48 crop of 64x48 module; source x=0 at west end, 32 at east end, 16 in middle; openings always x=16 | left=32*x, top=32*(y+1)-44; pivot44 | Only (x,y) |
| SW shape | full64x64 `wall-corner-nw` | left=32*W, top=32*(S-1); pivot64 at south edge of row S | (W,S), (W+1,S), (W,S-1) |
| SE shape | full64x64 `wall-corner-ne` | left=32*(E-1), top=32*(S-1); pivot64 | (E-1,S), (E,S), (E,S-1) |
| West leg | crop (0,8,17,16) from NW source | left=32*W | Side-wall portions it actually replaces |
| East leg | crop (47,8,17,16) from NE source | left=32*E+15 | Side-wall portions it actually replaces |

A full corner requires all three support cells to be plain, unoverlaid Wall in the same building. Its upper inner cell is interior space, not another wall reservation. Reject the corner when either south cell is a window/door, the upper side cell is an opening/overlay, or its footprint conflicts with another accepted corner. A width of at least five and height of at least three covers the prototype without overlapping corners. Do not unconditionally omit two cells at each end of the south run: skip only successful corner reservations. A rejected corner uses the established generated corner/affected cells and ordinary supported EW pieces elsewhere; never cover an opening with masonry. Brick has no pack corners, so its south EW run must still include its end cells.

The EW destination is **12 native pixels north of its tile and 4 pixels south of it**. A visibility check of rows y-1 and y is insufficient: row y+1 intersects too. The full corner spans exactly two rows, no southern overhang. Source crop and world support are separate concepts.

## Continuous NS legs, exactly as the approved picture

For the supported plaster rectangle with accepted south corner, repeat the 17x16 band continuously on each side over native Y interval `[32*N+2, 32*(S-1))`. The start follows prototype `(N+1)*32-30`; the full south corner supplies the last side row. Repeat every 16 pixels and clip the final repeat; preserve phase when clipping at tile boundaries. The current one-band-per-tile sketch draws only 16 of each 32 pixels and misses the north cap join.

Split these repeated bands at logical row boundaries for owner visibility and sorting. The top join belongs to the north endpoint and draws after its EW cap at equal depth, matching prototype's north-run-then-leg order. Do not stretch one band to 32 px. Stop the leg at unsupported NS windows/doors or overlays and keep their existing generated appearance; resume with the same global band phase after the interruption. If the full south corner is rejected, retain generated art for the affected lower corner/side junction rather than inventing a new corner splice.

The prototype itself omits the east window; the runtime's documented generated orientation fallback must retain that pane. Call out that intentional difference in the comparison evidence rather than silently making the window disappear to get identical pixels. Describe orientations by run axis, not the confusing historical phrase “east-west window”: pack openings live on EW wall runs; openings in NS side walls lack pack art.

## Depth and doorway state

`TopDownProjection.depth_of(x,y)` is y. Put each EW module/open-door frame and full south corner at depth `row+1`, their native foot line, and append to the existing standing-item sort. NS band fragments use the south edge of their logical owner row. Use an explicit tie priority for north EW before its leg join and bodies after walls at an exactly equal foot line; do not rely on unstable equal-key sort. A body just north of that foot line draws behind the wall, and just south draws in front. Flat threshold/floor stays in `_draw_district`; the doorway frame is the standing piece. No fade mechanic is needed for walls.

Read `Tile.Door` and `SimFortify.sync_map`'s `{kind: door, open, stage}` semantics: closed door overlay selects closed art; open overlay selects open art; no overlay is an open/broken doorway. Broken doors intentionally lose their overlay at DOOR_BROKEN and can use open art without a new state. Exclude scrap or board overlays from pack replacement so existing fortification visuals survive. Legacy threshold identification remains `_threshold_tiles()` where relevant.

There is no independent broken-glass state in the inspected map/fortify path. `kind: scrap` is a scrap barricade, not a broken window; board stage three is damaged boarding, and stage four despawns the boards. Preserve that generated treatment. Do not declare `a2_window_broken` as a shipped reader by mapping unrelated state to it; omit/defer that source unless a real existing glass state is demonstrated. No sim mechanic should be added to consume it.

## Exact sight mask; roofs stay where they are

`_draw()` calls `_draw_district` (including `_draw_roofs`) before `_draw_entities`. Leave that order and `RoofLook.roof_tiles` unchanged. Moving roofs after actors would be an unrelated ordering change and would not fix wall visibility safely.

Use the conservative bounded policy: A2 standing art requires current sight of its logical owner/support cells. Remembered-only walls retain the existing generated tile path and Palette.remembered treatment; they do not gain live door state, full-height silhouettes, or sorted overhang. A full corner requires all three supports currently seen; otherwise its cells remain fallback. A seen-null debug/no-vision path can retain the existing renderer convention that all in-bounds cells are live.

For each accepted piece, intersect its native destination rectangle with **each currently seen destination tile rectangle** and blit only nonempty fragments, adjusting source crop by the same offset. Both support visibility and destination visibility matter: a seen destination must not expose an unseen neighboring source wall. Keep all fragments at the original piece depth. Calculate intersections before camera rounding and reuse the tile grid's screen edges so masks leave no one-pixel seam. Clip map bounds too.

This includes the EW southern 4 px, northern 12 px, and every corner/leg fragment. Never use `seen OR explored` as permission for standing overhang. The resulting sorted wall pixels are a subset of currently seen screen tiles, whereas roofs cover unseen indoor tiles; therefore the later wall pass cannot paint over a roof or expose the unseen wall ring. Known-building status alone grants no wall fragment. Overhang intersecting an unseen tile is simply clipped, not grounds to suppress the entire visible EW run.

## Authored/content/runtime chain

Use the in-progress key shape `wall_modules[material]` in street dressing and `Dressing.wall_modules`; each runtime key resolves through `Appearance.resolve` from `assets/sprites`. Declare source crops in authored.json and reproduce PNGs with existing sprite tooling:

- plaster/brick west, middle, east: 32x48 with crops x=0/16/32;
- available plaster EW door states/intact window: middle32x48;
- corners: full64x64;
- legs: native17x16 crops above.

No resize, rotation, new palette, direct load from `res://art/simplyzombies/...`, or extra pack cache. Remove temporary `pack_wall_texture`; the pure helper's hardcoded pack-name answer should not compete with content-key resolution. Timber/block, absent material/key/texture, NS openings, unsupported shape, overlays, and unresolved reservations fall through to the existing generated material/orientation code. Missing art must not add anything to `covered`.

Extend authored READS discovery to `wall_modules` and test that discovery with a probe containing real nested module keys, not only a scan-loop mention. Content declarations alone do not prove runtime consumption: roof/topdown lanes must reach the selector, queued placement, and draw dispatch. Source pixels/canvas/crops remain held by authored and sprites gates.

## Bounded acceptance for Luna and Sol6.1

Add positive/negative lanes for: exact prototype 7x5 placements; reversed north-corner mapping rejected; corner-adjacent door/window never reserved; brick ends retained; unsupported compound layout creates no imaginary ring; continuous legs with no 16px gaps; generated NS pane retained; missing asset does not suppress fallback; board/scrap not broken glass; closed/open/no-overlay door cases; body ordering immediately north/south/equal foot line; unseen owner with seen destination draws nothing; seen owner with unseen overhang clips both northern and southern pixels; remembered-only fallback; unchanged roof tile set and pass order. Include a real draw-path probe so dictionary-only checks cannot pass disconnected code.

Luna should run the existing plan's targeted roof/topdown/sight/memory/authored/sprites gates and content validation/npm test as applicable, then capture the all-seen reference rectangle and doorway/body crossings plus a partial-seen roof edge. Coordinator owns the final combined gates and commit discipline. No gates were run for this planning task.

Read-only snapshot findings already sent early to coordinator/Luna: overhang span incorrectly reserved as covered; unconditional south-end skipping; half-height leg stamps; missed south4px visibility; arbitrary bounding-ring stamping; scrap incorrectly selecting broken glass. The working tree is changing while Luna implements, so these are guidance on the inspected snapshot, not claims about the eventual final diff. Also noticed `_a2_wall_modules(...bounds)` above the local `bounds` declaration in that snapshot; fix the order if still present.
