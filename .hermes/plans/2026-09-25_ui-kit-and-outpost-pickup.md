# Pickup: the UI Field Kit arc and the whole outpost pack (paused 2026-09-25)

Start here if you are the next session on branch `claude/serene-ride-r1p6y0` / PR #140. Read
`CLAUDE.md` first as always, then this, then docs/23's two what's-left groups named below.

## Where it stopped

Everything below is committed on `claude/serene-ride-r1p6y0` and pushed; PR #140 is open against
`main`. Nothing uncommitted was kept: two outpost slices were **in progress and stopped** (their
uncommitted worktrees are gone with the container) and must be started again from scratch —
"The bodies turn and walk" (2a) and "The cars are the pack's, east-west" (8).

### UI Field Kit — docs/23 "UI — the UI Field Kit, live"

Landed, each with its record in docs/23 and its lane in `godot:check:ui_skin` → `UI_SKIN_OK`:
the chrome wears the kit (2×, tiled centre, per-style edges, widened margins), one typeface
(VT323), empty slots say what goes there, the shell's rows are buttons, keys wear keycaps,
bubbles and the dashboard in kit frames, the four cursors, UI motion and a reduced-motion switch.

**Left, in order:**

1. **Saved, picked up, busy** (the last UI piece; opus). Replace `_events_lane` in
   `godot/check_ui_skin.gd` (it is already a coroutine the runner awaits). `presentation/session.gd`
   gains `signal saved`, emitted only on a successful `save()` (covers F5, the pause row, dawn
   autosave, quit-to-title, close request); `main.gd` connects it to the HUD, which draws
   `saved_tick` plus the word "saved" in the "outside" card header as chrome (not a line — check_hud's
   QUIET lane reads the lines). `item.pickedUp` (published in `sim/modules/inventory.gd`, read by
   nothing today) gets its first reader: `main.gd` scans `world.events.drained` in the step loop
   (beside `_camera_shake_from_events`) and a pickup **by the player** calls the inventory/quick
   strip's ping (`item_ping` on the slot). A live channel (treatment, construct, rescue, refuel,
   siphon — confirm the list by scanning `sim/modules` for actor components carrying `ticksLeft`)
   draws `busy` at the action bar's left end and **never reads `ticksLeft`** (docs/30: busy never
   encodes progress). `ui/motion.gd` already carries all four animations and `Motion.reduced()`.
   EVENTS lane: a save ticks and a failed save does not; a player pickup pings and an NPC's does not;
   a channel is busy and none is not; two different times-left give the same busy frame.
2. **Close-out** (haiku). Update `CLAUDE.md`'s chain count ("`godot:m2` chains **78**" — it is now
   one more with `godot:check:ui_skin`; count it in `package.json`) and its measured chain time;
   update `check_ui_skin.gd`'s header lane list (it still calls several landed lanes stubs); grep
   that no `ThemeDB.fallback_font` survives outside `ui/chrome.gd` and no kit `.tres` is loaded;
   run `npm run godot:m2`, `check:routing`, `check:timing`; tick the PR checklist.
3. **Screenshots for the owner** at 1920×1080 and 1280×720 (AGENTS.md: Xvfb, throwaway SceneTree
   driver, deleted after; Pillow is not installed on these containers — crop with Godot's Image API).

Known, recorded, not fixed: at 1280×720 the corner doll overlaps the action bar, the work panel is
fixed at 1520 px, the inspect column overlaps the pockets, the quick strip's sixth slot is off
screen (all predate the kit; see "One typeface"'s record). The bench offer line's → draws through
the OS font fallback (boxes on web). "open the door" wears the search glyph.

### The whole outpost pack — docs/23 "Art & renderer — the outpost pack"

The owner asked for the whole pack (codex's delivery, `godot/art/simplyzombies/`) and answered the
six questions it raised: docs/30 **"The whole outpost pack, 2026-09-25"** is the authority. Landed:
the reproducible-source tier (2026-09-17), **"A padded source copies, never blends"** and **the
needs-assets report** (both 2026-09-25). Four new pieces were named from the owner's answers (held
weapons, furnishings and container kinds, nature extras, props for things that exist).

**Order and workers** (from a read-only planner's pass; verify against the code before trusting):

| Wave | Piece | Worker | Needs first |
| --- | --- | --- | --- |
| 1 | The bodies turn and walk (2a: pack rig, walk clock, raider tint) | opus | — |
| 1 | The cars are the pack's, east-west (sim footprint; balance before/after) | opus | — |
| 1 | A picture per item base (6a: item icons on the floor and in bags) | sonnet | — |
| 2 | The ground is the pack's (pack grade wins; re-pin the ground lanes) | opus | 2a |
| 2 | Trees, the bed and the heaps (+ nature extras) | sonnet | — |
| 2 | Pack gear on the body (2b) + held weapons in the hand | opus | 2a |
| 3 | The walls are modules — **picture round first**, owner picks | opus | 2a, ground, trees |
| 3 | The shot is seen (effects; new `godot:check:fx`) | opus | 2a, 6a |
| any | The cursor (split by place; extends `ui/cursors.gd` + CURSORS lane) | sonnet | UI arc done |
| any | Item pictures in the quick strip / inspect pane (6b) | sonnet | UI arc done |
| any | Furnishings and containers; props for things that exist | sonnet | trees |

Parallel worktrees work (use `isolation: worktree`), but **a new worktree may be cut from `main`,
not this branch — fast-forward it first** (`git merge --ff-only <head>`). Prefix Godot runs with a
private `XDG_DATA_HOME` (the sandbox refuses `XDG_CONFIG_HOME`). Keep `authored.json` keys sorted by
prefix (`body_*`, `fx_*`, `item_*`, `module_*`, `tree_*`, `vehicle_*`) so slices merge. The
machine has 4 cores: two slices plus a chain run at once is the practical limit.

**Findings every outpost slice must honour** (measured by the planner):

- **Alpha threshold.** Pack art has alpha ≤ 6 specks out to the canvas edges (all 20 survivor
  walk frames). Any lane judging pack geometry needs a named threshold (e.g. 128) that refuses a
  real pixel and accepts a speck — "opaque = alpha > 0" makes an envelope that cannot fail.
- **Crop, don't pad, where the anchor allows.** Bodies crop to 32×40 (anchor row 40, soles row 39),
  pine to height 94, hatchback 47, van 55, plaster wall 44. Only `wall-door-open` and
  `wall-gate-open` hang below their anchor — the walls slice gives `authored.json`'s `anchor` its
  first reader.
- **READS can't see dressing or effects yet:** `check_authored`'s `_keys_content_declares` scans
  only `appearance.sprite/equipSprite/equipSpriteFront`; the trees slice widens it to dressing
  blocks, the effects slice to effect fields.
- **Never load the pack's `docs/godot/*.tres`** (null headless, the same trap as the UI kit);
  frame rates come from `manifest.json`; PNGs load the two-path way (`Kit.texture` / `Appearance`).
- **Effects must not leak position:** gate every effect on the player's seen set; blood must not
  vary with damage (a bite can present as a scratch).
- **Vehicle footprint is sim content** (`SimVehicles.extent_of`, worldgen `_vehicles`, loot HOST);
  the cars slice runs `godot:m2:balance` before and after, and stops if a FAST line moves.
- **The ground grade moves ~six lanes at once** (`check_road_look` PALETTE's 0.30 saturation cap,
  `check_weather` ACCENT, `check_topdown` GROUND/WALL, `check_water`, `check_appearance` GREY,
  `palette.py`'s guard). Re-pin each to a measured pack table with the owner's answer cited; never
  loosen in passing; pin hex literals, never a float `sum()` (the CPython 3.11/3.12 trap).
- **Retire generator code the pack replaces in the same commit** (`tools/sprites/parts/*`,
  `build.py` PAWN_KEYS / CANVAS) and delete the committed PNGs; `sprites:check` needs
  `pip install pillow==12.3.0` on a fresh container.

## PR #140

CI on the last checked head: `performance` failed once on the frozen TypeScript bench's
quiet-night budget (0.5348 ms against 0.5), a PR that touches no TypeScript; a comment on the PR
says so and names the next head's run as the one re-run. If it is red again, root-cause it — never
move the budget. `godot-m2` and `check` were still running at the pause.
