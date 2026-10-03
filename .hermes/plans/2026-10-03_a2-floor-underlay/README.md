# A2 perimeter floor underlay, 2026-10-03

The accepted A2 wall and horizontal-window owner cells now draw the existing room Boards
atlas row beneath their native transparent pixels. The colour is the existing ground-to-indoor
mix, resolved before outdoor snow. This extends the visible floor without setting simulation
indoor flags or changing traversability, ownership, visibility, roofs, native art or door
thresholds. The unsupported east side window still shows its generated pane and masonry.

## Captures

Twelve exact-size PNGs compare the same `main.tscn` scenes at 1280×720 and 1920×1080. Each pair
is named `before-<size>-<scenario>.png` and `after-<size>-<scenario>.png`. All use seed 20260805,
daylight, zoom 64, and the roof gate's 7×5 plaster-ring fixture at (2, 2), with an open south
door, a south window and an unsupported east side window. The other boot entities are moved
off-map; presentation dressing remains. The player is staged and simulation paused.

| Scenario | What the image proves |
| --- | --- |
| `normal-inside` | Actual `SimVisibility`, player at (5.5, 4.5). The left and right outdoor strips become room boards while the unsupported east pane retains its generated fallback. |
| `normal-north-roof` | Actual `SimVisibility`, player north at (5.5, 0.5), facing south. The visible north wall gets its underlay; unseen interior roof coverage and unseen perimeter policy remain as shipped. |
| `diagnostic-all-seen` | **Forced all-seen diagnostic**, player inside. All 25 A2 pieces produce 51 clipped blits; this is a geometry comparison, not a gameplay visibility claim. |

The two normal views produce 43 and 18 wall blits respectively. Pixel comparison between each
before/after pair confines differences to the building's owner-cell bounds: 30,562 changed
pixels inside, 4,465 on the north approach and 30,553 in the all-seen diagnostic. Counts agree
at both resolutions; the north approach changes only the north owner row, not the roof below.
The images were inspected at both sizes.

A throwaway scenario driver staged these screenshots through exact-size SubViewports under
Xvfb display `:91`, using the Godot 4.7.1 executable, `--audio-driver Dummy`, `--path godot`,
and isolated `XDG_DATA_HOME=/tmp/sz-floor-data` / `XDG_CACHE_HOME=/tmp/sz-floor-cache`. The driver
was removed after capture, following AGENTS.md's screenshot workflow. The settings above are
the scenario specification for reproducing the comparison.

The `before` set was captured with the two accepted Wall/Window calls restored to their
baseline at `5b2706c`: `_draw_floor_tile(rect, Appearance.indoor_floor(world.tilemap, tx, ty,
ground), tx, ty, Appearance.ground_row_for(world.tilemap, tx, ty, false))`. The new helper was
consequently unused. The final `_draw_a2_floor_underlay(rect, tx, ty)` calls were restored
immediately afterward.

## Gates and negative proof

`godot:check:roof` gained A2_FLOOR, which instruments only its actual `main.tscn` instance and
forwards to the real floor drawer. All 18 accepted wall/window owners reach the Boards row and
the same tint as the room, with no underlay on the door or unsupported side window. The same
scene repeats under full snow cover, below the texture threshold, and with the atlas missing;
outdoor snow still changes the outdoor floor. Board/scrap overlays, timber, remembered-only
and never-seen frames refuse the underlay. Tiles, indoor flags, surfaces and building metadata
are compared before/after. Existing A2_RUNTIME and roof lanes retain topology, missing-key,
owner/destination clipping, opening-state and roof checks.

Restoring the two old calls produced exit 1 and `A2_FLOOR clear expected 18 wall/window owners
only, got []`; the restored final code passes. Verbose capture, regression and gate logs were
moved to `/tmp/sz-floor-evidence-logs/`; the commands and outcomes below are the committed record.
The final focused gates all passed:

| Gate | Runner seconds | Exit |
| --- | ---: | ---: |
| `godot:check:roof` | 4.45 | 0 |
| `godot:check:water` | 9.67 | 0 |
| `godot:check:memory` | 4.36 | 0 |
| `godot:check:weather` | 1.87 | 0 |
| `godot:check:topdown` | 1.85 | 0 |
| `godot:check:road` | 3.62 | 0 |

Each row ran as `npm run <gate>` with the isolated XDG directories above and
`GODOT_BIN=/workspace/simplyZOMBIES/.ci-tools/godot/Godot_v4.7.1-stable_linux.x86_64`.
`npm run check:routing` also passed (122 paths, 93 scripts, 68 links). The usual Godot shutdown
resource warnings followed success and exit 0. No sprite or content changes were
made. The coordinator's subsequent combined integration passed all 85 Milestone 2 gates in
47m16s (2835.79 runner seconds), including this lane; docs/23 records that separate full-chain
result. Jev was unavailable.
