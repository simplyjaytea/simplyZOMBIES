# Art-style screenshot fixtures — A vs B vs C

Authorized by the owner (2026-09-01 session), Package 5 of that session's plan. Twelve
screenshots, four moments (`day`, `indoors`, `night`, `combat`) times three candidate styles
from `.hermes/plans/2026-08-19_topdown-art-brainstorm.md`, all on the canonical seed
(`SimBoot.DISTRICT_SEED`, 20260805) and the default district. This package ships **no code** —
every render tweak below was a working-tree patch applied for its own four shots and reverted
before the next style, and `git status` was clean outside this directory and this note before
commit. **The pick stays the owner's.** This note describes what the images show; it does not
recommend one.

## Method, briefly

A throwaway `SceneTree` script (`godot/screenshot_fixture.gd`, deleted — it has no gate keeping
it honest once committed, same as `project_smoke.gd`'s pattern) booted
`res://presentation/main.tscn` under Xvfb, posed one of four moments, stepped the sim directly
(`world.step()`, not wall-clock frames — deterministic and immune to headless frame-timing
variance), waited for the draw to reach the viewport texture, and saved a PNG. The four moments:

- **day** — as booted, no changes (day 1, daylight).
- **indoors** — the player's `position` component written onto the annex's indoor floor tile
  (the same tile `boot.gd`'s `place_stations` stands the unlit campfire on), then a few ticks
  stepped so vision recomputes over the new position.
- **night** — `world.tick` set past `Clock.DUSK_ENDS` (`Clock.tick_on_day(1, 0.85)`), the boot
  campfire lit via `SimNeeds.set_lit` (the needs/fire path, which registers it as a
  `light_source` for the vision/light module), player stood two tiles off it, a few ticks
  stepped.
- **combat** — `SimRoster.spawn_zombie` (the roster module's own spawn path, so the shambler's
  content id, body and appearance resolve exactly as an ordinary wave would give them) at an
  open tile adjacent to the player, the player's `facing` pointed at it, 80 ticks stepped so it
  closes and engages. `GRABS_ENABLED` is live (Package 1), so this is a real threat, not a prop.

Per-style tweaks, each a working-tree patch reverted immediately after that style's four shots
(`git checkout -- godot/presentation/main.gd` for B; a restore pass from `.orig.png` backups for
C — both verified against `git status`/`git diff` before moving on):

- **A** — none. The shipped renderer, unmodified.
- **B** — one patch in `main.gd`'s `_draw_entities`, wrapping only the player's own sprite blit
  in `draw_set_transform(screen_pos, facing + PI/2, Vector2.ONE)` / reset immediately after.
  NPCs and zombies are untouched by the patch and stay face-on. The shipped baseline has **no
  player sprite yet** (only colonists and zombies carry art today — see `for_entity` in
  `presentation/appearance.gd`, where `is_player` alone never sets a content id), so the patch
  also borrows `survivor_mara.png` as a screenshot-only stand-in; without that there would be
  nothing to rotate and B's shots would be indistinguishable from A's. Both concessions are
  called out in the code comment and gone with the revert.
- **C** — a Python pass (`_squash_style_c.py`, also deleted) over every PNG in
  `godot/assets/sprites/`: resize to 85% height (anchored at the bottom, so the compression
  comes off the head, not the planted feet), then darken the bottom ~22% of the re-seated
  canvas to ~55% brightness. Backed up to `<name>.orig.png` and restored byte-for-byte after
  (`git diff --stat` empty). Placeholder quality only, per the brainstorm doc's own
  "legibility and layout, not pixel identity" standard.

## What the four moments show, per style

### A — baseline (shipped, non-rotating)
- **day** (`a-day.png`): the annex interior at boot — two beds (pale slabs), the unlit campfire
  (a small dark disc, no glow), a storage box outside, window panes reading as bright cyan
  breaks in the wall run. The player is a plain tan circle with a lighter ring and a short white
  facing tick pointing east (the boot default, `radians: 0.0`) — there is currently no player
  sprite at all in the shipped game, circle-and-tick is the true "as shipped" read.
- **indoors** (`a-indoors.png`): same room from one tile further in; a peripheral colonist glyph
  (an anonymous dark-green dot, no posture, no facing) is visible at the room's far edge — the
  peripheral-anonymity contract holding even in this baseline.
- **night** (`a-night.png`): see the dedicated sanity-check section below.
- **combat** (`a-combat.png`): the shambler is a small tan-green circle with its own facing
  line, standing one tile northeast of the player. Legible as "something is there and it is
  oriented at you," but a shambler-shaped circle and a colonist-shaped circle share the same
  primitive — only tint (and, at Focal detail, the reach line) tells them apart. This is exactly
  the risk the brainstorm doc named for A: "a shambler 'lunging' looks identical to one idling
  until it moves."

### B — rotating player
- **day** (`b-day.png`): identical framing to A, but the player is now the borrowed colonist
  sprite, standing upright (facing east, rotated a quarter turn from its head-up canvas
  orientation to match). Reads as a body with a heading rather than a token with a tick mark —
  the facing is *in* the silhouette now, not appended to it.
- **indoors** (`b-indoors.png`): same read, same peripheral colonist glyph at the edge
  (untouched by the patch, confirming it only ever reaches the player row).
- **night** (`b-night.png`): the rotated sprite sits in the warm pool exactly as A's circle did
  — the patch does not touch `_draw_light_pools` or the wash, so package 4's look is identical
  under B.
- **combat** (`b-combat.png`): the player's body is turned to face the shambler (east, toward
  the spawn point) and the sprite reads visibly foreshortened/sideways from its upright canvas
  pose — the rotation is doing real work in exactly the frame where facing the threat matters
  most. **Peripheral-anonymity check**: the same peripheral colonist glyph seen in `b-indoors`
  is the relevant control here — it is drawn by the *unmodified* branch of `_draw_entities`
  (Peripheral detail returns before any sprite or rotation code runs), so a bystander glimpsed
  at range still gives up no posture and no facing under B, exactly as the brainstorm's clause
  requires. The patch's own comment states the scope explicitly (`if bool(it["player"]):`) —
  there is no path from this patch to a rotated NPC or zombie at any detail level, Focal
  included: only the player's own draw call is inside the `draw_set_transform` block.
- **What it costs going forward** (not built here): a real player sprite (there isn't one yet),
  authored on a rig that reads at every heading rather than one canonical front pose; the
  brainstorm's own note that a rotating player against face-on NPCs is "a real aesthetic seam"
  that must be a deliberate pick; and every equip overlay (`back`, `primary`, `secondary`)
  re-authored against that rotated rig, since today's overlays assume the body they composite
  onto never turns — composited at an unrotated rect, they would swing out of alignment the
  moment the body under them does.

### C — hybrid high-3/4 (placeholder squash)
- **day** (`c-day.png`): **byte-identical to A's** (confirmed: both 44,336 bytes). Nothing in
  this framing carries a sprite today — the beds, the campfire, the storage box are all
  procedural shapes (`_draw_prop`'s slab/disc/box primitives), so a sprite-only patch has
  nothing to act on here.
- **indoors** (`c-indoors.png`): also byte-identical to A's for the same reason.
- **night** (`c-night.png`): visually identical to A's; the small byte-count difference (42,406
  vs 42,421) is PNG-encoder noise between two independent process runs, not a rendering change
  — nothing in this frame carries a sprite either.
- **combat** (`c-combat.png`): the one frame where C actually differs from A — the shambler
  (which does carry a sprite, `zombie_shambler.png`) is visibly shorter and has a darker band
  low on its silhouette, the "foreshortened, boot-fronts visible" read the brainstorm describes.
- **The honest limit of this fixture set**: C's effect is real but was only exercised once,
  because only two sprites exist in the whole project today (`survivor_mara.png`,
  `zombie_shambler.png`) and only one of them (the zombie) appears in these four framings. A
  fair C comparison needs more art on disk before it says much beyond "the squash script runs
  and looks plausible on one figure" — which is exactly why the brainstorm doc calls for a
  one-page rig sheet before more than a handful of sprites exist under this style, so the
  camera-angle-implied-by-the-art stays one deliberate answer rather than five different guesses
  from five prompts.
- **What it costs going forward**: nothing squashes itself correctly forever — every future
  sprite (new zombie types, new gear, new colonists) needs to be *authored* at the implied angle
  a rig sheet fixes, not run through this script, which is a fixture shortcut, not a pipeline.

## Package 4 visual sanity check (A-night)

Requested alongside this package while the night shot was already up: package 4's lit-and-seen
pools (`presentation/light_look.gd`) have passed `godot:m2:light` but nobody had looked at them.
`a-night.png`, read directly:

- **A warm pool is visible around the lit campfire.** The campfire prop itself reads as a
  brighter orange disc, and the floor tiles immediately around it carry a visible warm tint
  against the cooler ambient wash — the near/far split (`POOL_SPLIT_METRES`) is not obviously
  distinguishable by eye at this zoom, but the pool itself clearly reads against unlit floor.
- **No light is visible through walls.** The area outside the annex's west wall (left of the
  window column) is uniformly dark with no warm bleed, consistent with the shadowcast occlusion
  the pools are gated on (`light.gd`'s occlusion, asserted no-leak by `check_light_look.gd`).
- **The wash is present but not opaque.** Walls, window panes, the storage box and the beds all
  stay legible at night — dimmer and cooler than the day shot, but nothing is crushed to pure
  black except genuinely unlit floor at the edge of vision. `NIGHT_WASH` (0.8) times a
  near-`NIGHT_AMBIENT` (0.04) local-light fraction reads as intended: dark, not blind.

No visual wrongness found. This is a look-only check on one seed, one campfire, one framing —
it is not a substitute for `check_light_look.gd`'s gate, which still owns correctness.

## Summary

| | A — baseline | B — rotating player | C — hybrid 3/4 |
|---|---|---|---|
| Code changes to ship it | none | rotation slice in the renderer | none (art-only) |
| Art needed before it says more than this fixture | none | a real player sprite, on a rig authored for every heading | more sprites, on a one-page rig sheet fixing the implied angle |
| Follow-up equip work | none | every equip overlay re-authored for the rotated rig | none beyond ordinary sprite authoring |
| Aesthetic risk named by the brainstorm | shambler "lunging" reads identical to idle until it moves | face-on NPCs beside a rotating player is a deliberate seam, not a drift | inconsistent implied camera angle across artists/prompts without the rig sheet |
| Peripheral-anonymity clause | holds (untouched code path) | holds — confirmed in `b-indoors`/`b-combat`; the patch never reaches the Peripheral-detail branch | holds (untouched code path) |
| Package 4 lit pools | confirmed sane in `a-night.png` (see above) | unaffected — same draw call, same look | unaffected — same draw call, same look |

The twelve PNGs sit beside this file, named `<style>-<moment>.png`.
