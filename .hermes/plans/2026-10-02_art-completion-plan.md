# Finite art completion pass — 2026-10-02

Implementation plan against main `b11756b`; root owns `luna/art-completion`, branch claiming,
asset generation and integration gates. Luna implements; Sol reviews. This document is a plan,
not implementation evidence. No tests were run in making it. Jev is unavailable.

The present request authorizes these reversible art and reader choices. The owner selected
**A2 — fitted pack walls** on 2026-10-03 (Asia/Seoul); the wall slice below is now in scope
after the shared renderer edits. No question is needed before phases 1–4. Root's environment note gives
`DISPLAY=:0` and Godot at
`/tmp/simplyzombies-sprite-audit-3lcxVb/.ci-tools/godot/Godot_v4.7.1-stable_linux.x86_64`.
Use that engine through `GODOT_BIN`; do not install another engine or assume Xvfb exists.

## Contract and references

Read CLAUDE.md, HANDOFF.md and the relevant docs/23 records before implementing. Governing
art decisions are docs/30's 2026-09-09 exploded chart, 2026-09-17 outpost adoption,
2026-09-25 whole-pack extension and 2026-10-02 zombie poses. The historical face-on pawn
paragraphs in the sprite brief do not override its current pack/zombie sections.

Accepted visual references, inspected for this plan:

- `.hermes/plans/2026-09-09_character-fixtures/diagram/takes-sheet-3x.png`: **D2**, not D1,
  D3 or D4. Also use `takes-corner-2x.png` in that directory and
  `.hermes/plans/2026-09-09_character-fixtures/diagram.py` as the approved geometry reference,
  not a new fixture dependency in production.
- `godot/art/simplyzombies/previews/asset-catalog.png` and
  `groups/props/previews/props-contact.png`: the established furniture and icon scale.
- `godot/art/simplyzombies/zombie-poses/previews/contact-sheet.png`: the current seven families
  and settled human poses; its draft caption is not implementation evidence. Runtime status
  comes from docs/23 and `godot/check_zombie_art.gd`.
- `godot/art/simplyzombies/STYLE.md`: elevated flat top-down three-quarter view, broad readable
  silhouettes, near-black stepped edges, restrained material shading, muted olive/ochre/slate,
  warm wood and faded metal. Game scale remains 32 native pixels per tile at 2×.

Reuse existing pack pixels. Pack adoption permits crop/pad, **no source resizing, repainting or
cropping solid rows to make a canvas fit**. The general STYLE allowance for nearest-neighbour
resizing does not override this stricter adopted-pack contract. All genuinely new raster art
and edits use built-in imagegen; code may only crop, pad, compose previews and mechanically
extract new artwork. No procedural repaint, palette quantization or background deletion.
The condition chart is the explicit exception: code-native diagram masks through its existing
established generator, not a procedural repaint of pack artwork.

Every slice retains the health-bar ban, word-only HUD, no certainty through walls, unchanged
Detail tiers, fixed sim light reach, no new collision/pathfinding/loot/interaction mechanics,
no sim RNG consumption, and no changes to the frozen TypeScript product. New declarations need
real readers. Root records each completed slice in docs/23 in the same implementation commit;
only remove the precise shipped remainder, not an entire partially completed umbrella item.

## Phase 1 — the separated condition chart (start immediately)

**Files:** `tools/sprites/parts/paperdoll.py`, its thirty
`godot/assets/sprites/chart_<part>_<pose>.png` outputs, `godot/ui/paperdoll.gd`,
`godot/check_appearance.gd`; `godot/presentation/appearance.gd` only if a shared mark/layout
helper actually needs to change. No content or sim changes.

Bring the approved D2 geometry into the production generator: ten bordered plates, uniform
small transparent seams between adjacent parts, head about one sixth of the figure, legs just
under half. Do not merely pull the old mannequin apart. Keep 64×160, ten existing part names,
near-white masks, stand/crouch/prone and integer drawing scale. Derive the other poses from
one published plate model; do not import the historical fixture at runtime. Keep anatomy
anonymous and full-part state tint discrete. Retain armour as an outer stroke, wounds and
infection as marks, and the stance word. Read only `SimCondition.view`.

The seams must read at corner size and remain intelligible with adjacent armoured plates.
A one-native-pixel minimum transparent separation is the base acceptance; choose the smallest
uniform practical spacing matching D2. If armour closes it visually, make the stroke respect
part separation rather than changing what armour means. Marks must sit on their own plate;
if the bounding-box midpoint falls in transparent space, choose an interior opaque point.

**Focused acceptance:** expand existing CHART in `godot/check_appearance.gd`. Retain thirty
resolved masks, canvas, brightness, distinct poses, head-above-feet, left/right distinction and
real UI draw/tint readers. Add pairwise opaque-mask non-overlap, separation at the named joints,
and meaningful standing proportion bounds around the approved model. Exercise the predicate
with a touching/overlapping fabricated pair and a separated pair; a relocated mark outside
its plate must fail. UI reader assertions follow actual function bodies if drawing is factored.
Keep `godot:ban:healthbar` unchanged and green; run `godot:check:appearance`, `godot:check:hud`,
`godot:check:inventory`, `godot:check:respond` and `sprites:check`.

**Screenshots:** actual Godot sheet and corner at 1920×1080 and 1280×720; healthy, arm cut,
bad torso plus infected leg/armoured head, unusable arm under armour. Include all three stances
in a contact sheet. Existing small-screen overlap is reported, not repaired in this art pass.
No new imagegen deliverable is required for this phase.

## Phase 2 — the real workbench and three tall furnishings

**Files:** `godot/assets/sprites/authored.json`, four reproduced sprite PNGs,
`godot/content/props/stations.json`, `godot/content/dressing/street.json`,
`godot/content/schemas/dressing.schema.json`, `godot/presentation/appearance.gd`,
`godot/presentation/dressing.gd`, `godot/presentation/main.gd`,
`godot/check_appearance.gd`, `godot/check_trees.gd`, `godot/check_authored.gd`.
No edits to `SimGunsmith.build` are necessary: add `bench` to `Appearance.PROP_KINDS`.

Use `godot/art/simplyzombies/groups/props/native/` sources and their manifest:

| Source basename | Native canvas | Ground anchor | Runtime key and reader |
|---|---|---|---|
| prop-workbench.png | 48×32 | [24,30] | `prop_workbench`; new `prop.workbench` appearance on actual `bench` component |
| prop-fridge.png | 24×40 | [12,38] | `prop_fridge`; indoor inert furnishing beside wall |
| prop-road-sign.png | 24×40 | [12,38] | `prop_road_sign`; outdoor paved inert furnishing |
| prop-streetlamp.png | 24×64 | [12,62] | `prop_streetlamp`; outdoor paved inert furnishing, unlit |

Follow existing anchor-row cropping only after checking that the discarded rows contain no
solid art. Otherwise preserve full canvas and carry the manifest anchor into the renderer;
never erase feet to satisfy a bound. The workbench can use existing flat prop rendering at its
native scale, like the table/bed. Measure `appearance.size` against its actual alpha footprint,
within the current 1.5 limit; do not change all prop scale rules to make one asset fit.

Keep the existing `furnishings` list but permit an explicit optional `standing: true` for these
three records, with a default false for the eight existing ones. Feed the same deterministic
`Dressing.furnishing_tiles_cached` selection into the standing sort and skip standing entries
in `_draw_furnishings`; never draw both. Existing floor, surface, indoor/outdoor, neighbour,
doorway and occupied-real-prop exclusions remain. Suggested initial rarities: fridge 45,
road sign 140, streetlamp 180, appended after existing entries so existing hash indices stay
stable. These are reversible content choices, not balance tuning.

Use the tree/standing-prop ground-depth ordering and foot anchoring; fade a tall decoration
when its opaque picture would obscure a Focal body, following the existing tree rule. Do not
make it an occluder. A lamp silhouette is not a light source; a fridge is not a container.
Retain bounds/seen intersection and invalidate caches on map, generation, seed/content changes.

**Focused acceptance:** FURNISH judges short versus explicitly standing entries separately;
do not simply delete its 48×32 limit. Add valid tall/invalid unflagged tall fixtures, native
anchor/canvas/source checks, all three kinds selected on shipped districts, correct place and
wrong-place refusals, door/edge/real-prop exclusions, cache equivalence/invalidation, seen/bounds
subset, and unchanged map/components/RNG. Add sort fixture with a body north and south of each
prop and fade only on overlap. Source-scanned or runtime reader tests must fail when the sort
append, flat-pass skip, seen check, or fade call is removed. Workbench positive is a bench
created by the existing build path; negative is an unrelated entity, an unseen bench and a
despawned bench. Prove it draws through `prop_look` and the normal prop pass and stays actionable
through the existing bench interaction, not a second decorative entity.

Run `godot:check:trees`, `godot:check:appearance`, `godot:check:authored`,
`godot:check:topdown`, `godot:m2:bench`, `godot:validate`, `npm test`, `sprites:check`.
Capture native-size source contact, a built functioning bench, tall furnishing with body
north/south, overlap fade, and the same scene's unseen area. No new raster is needed.

## Phase 3 — the Camp Stove icon (root imagegen parallel with phase 2)

Root has already supplied the required imagegen source at
`godot/art/simplyzombies/art-completion/sources/camp-stove.png`, with
`stove-prompt.json` and a source `.gdignore`. Root reports true alpha 0..255 and solid bounds
(350,390)–(955,914) on 1274×1235. Use this source rather than generating a duplicate; Luna
inspects and extracts to roughly 26×23 occupied pixels centered on 32×32, preserving partial
alpha. These are coordinator-reported measurements, not measurements performed by this plan.

**Deliverable:** one original 32×32 RGBA item icon with genuine transparent background,
compact portable graphite/olive stove, clear burner top and short supports, no long chimney,
no text, fire, glow or ground shadow implying an active placed object. Read as a stove at the
inventory's real size. Match the pack's toolkit, flashlight and repair-kit icons in
`groups/items/icons/item-toolkit.png`, `item-flashlight.png` and `item-repair-kit.png` and the iron stove utility for material,
not geometry. Root should inspect those actual PNGs before imagegen.

Preserve new source, prompt, extraction metadata, final native PNG and inspected transparent/
dark/light contact preview under `godot/art/simplyzombies/art-completion/`. Do not modify the
original utility stove source or claim to have adopted that 32×40 object. If imagegen returns
oversized art, mechanically extract the newly authored icon using documented nearest-neighbour
export; never resize the existing pack stove. Reject baked checkerboards and request an
imagegen transparency edit rather than removing the background in code.

**Integration files:** `godot/assets/sprites/authored.json` (`item_camp_stove`, kind `icon`,
source pointing to new native export), corresponding runtime PNG,
`godot/content/items/kitchen.json` (`item.stove.camp.appearance.sprite`),
`godot/check_appearance.gd` PICTURES and `godot/check_authored.gd` ICON only where needed to
include the new expected key. Existing `ui/item_picture.gd` is already the reader; change it
only if a demonstrated bug prevents the existing contract.

**Acceptance:** 32×32, visible opaque content and real transparent exterior, no fully opaque
matte; known stove resolves, absent sprite retains glyph fallback, bad key fails; all four
surfaces (floor, bag, quick strip, inspect) reach the common resolver. Add the stove to explicit
content/key expectations so swapping it back to a glyph fails. Preserve item class, 2×2 grid,
use/boil behavior and all other content fields. Run appearance, authored, inventory, validate,
`npm test`, `sprites:check`; screenshot bag plus inspect and quick strip, and a dropped stove.

## Phase 4 — existing light sources get their own colour

**Files:** `godot/content/items/light.json`, `lights.json`, `attachments.json`,
`godot/content/schemas/item.schema.json`, `godot/presentation/appearance.gd`,
`godot/presentation/light_look.gd`, `godot/presentation/main.gd`,
`godot/presentation/palette.gd`, `godot/check_light_look.gd`,
`godot/check_appearance.gd`. For campfire colour add a presentation-only `light` tint block to
`godot/content/props/stations.json` and its schema, or a narrowly equivalent content appearance
key; do not put RGB into simulation state. No raster generation.

Use the backlog's `light.tint` beside magnitude for items: strict `#rrggbb`, optional,
unknown/missing source falls back to today's warm colour. Initial palette: candles/lighters/
oil lamps/fire warm amber `#ffd68c`; electric torches/headlamps/weapon light/floodlight/worklight
pale neutral `#e5edf2`; gas camping lantern `#fff0ca`; glowstick muted green `#a8d58b`; road flare
muted red `#ee856c`. Confirm against descriptions, not item-id branches in the draw loop.
Colour is appearance only; no numbers, reach, duration or attraction change.

`SimLight` already exposes `sources_list()`, `source_at()` and `tiles_for()`: use the existing
casts, do not recast or invent radii. For each seen bounded tile choose the contributor with
maximum positive remaining reach, matching `lit_metres` exactly; retain source iteration tie
order and current near/far alpha. Output grouped tinted tiles or records consumed by
`_draw_light_pools`; retain a compatibility union for existing near/far checks if useful.
Never sum light strength or change night wash, which stays observer sight-derived.

Resolve each source tint once per frame: placed item to its actual base, a campfire to its
existing lit prop content, a human to `SimLightModule.brightest_carried` (including attachments,
fuel exhaustion and current equipment). A muzzle flash can temporarily dominate the holder's
source: when current source magnitude exceeds carried magnitude use the neutral/warm flash
fallback, not the held glowstick colour; inspect the existing active ranged flash fact for
equal-magnitude handling. Do not add a new flash sim event. Cache source metadata for the draw
call rather than scanning inventories once per tile. Unrecognized sources retain safe default.

**Acceptance:** LIGHT gate covers two distinct colours, unknown default, correct attached and
carried winner, exhausted lamp fallback, removed source, campfire lit/unlit, flash then carried
restoration, wall-blocked and unseen tiles, bounds, overlapping stronger source and deterministic
tie. Match the coloured union to original near/far membership; measured `lit_metres`, sight
range and wash are identical before/after. Bad tint format/type and unused tint declaration fail
nested-shape/reader checks. Sabotages: always warm, all sources summed, no seen guard, no cast
membership, tint ignored by `_draw_light_pools`, and stale equipment colour must each be caught.
Run light, appearance, `godot:m2:light_burn`, sight, memory, validate and `npm test`. Capture
same-view fire versus electric, red/green carried lights, overlap and wall occlusion at night;
noon should remain unchanged. This is **not** the directional torch/cone mechanic.

## Phase 5 — bounded corpse and foot polish, after the four deliverables

This is an optional polish budget, not permission to regenerate all 158 new pose pictures.
First inspect the actual native frames and animated preview: docs/23 records 1–3 pixel height
and incidental clothing variation, which is not proof that every frame is defective.

**5A, first priority:** pick at most one demonstrably worst four-frame directional cycle and
its matching two settled zombie poses. Use imagegen edits referenced to that family's approved
idle and current frames to stabilize clothing identity, limb count and planted-foot contact.
Keep family, palette, silhouette scale, canvas, anchor and frame order/rate. Four visibly
different locomotion silhouettes must remain; shifting/recolouring one duplicate is not an
animation. Do not remove legitimate up/down gait motion merely to make heights identical.
Only replace frames visibly improved at native and 2× size; otherwise keep originals and report
that polish was attempted but not accepted. Preserve provenance and extraction under a new
art-completion polish folder; update only selected `authored.json` member sources and their
reproduced runtime PNGs, plus focused expectations/QA metadata as warranted.

**5B, optional separate mini-slice:** human corpse clothing is a real missing pose socket, not
something to bake onto all four shirtless base corpses. Bound it to **one existing vest family
in four human corpse poses** (supine, prone, side, diagonal), four transparent 48×40 overlays
aligned pixel-for-pixel to current human corpse canvases. Root imagegen uses each base pose and
the pack's existing vest as reference; no new jacket/helmet/backpack claim. Store the new
family in authored metadata; add optional `appearance.corpseEquipSprite` to supported item
entries in `godot/content/items/armor.json` and item schema, with members keyed by the actual
human corpse pose. The existing vest declarations are in armor.json; bind only entries already using item_gear_vest. Add an Appearance
resolver and compose at `corpse_rect` after the base, at Focal only, only for a human corpse
still owning that actual equipped vest. Inventory removal removes its picture. No overlay on
zombie history (gear already dropped), no standing-gear reuse, no permanent clothing painted
onto naked bodies. Do not enter this mini-slice unless root can supply all four fitted overlays;
partial speculative assets do not land. Existing bare-base fallback remains for all other gear.

**Gates/screens:** `godot:check:zombie_art` retains motion/corpse family/save/ground/readers;
`godot:check:authored` and `sprites:check` hold geometry and provenance; memory remains green.
5B adds clothed/bare/unequipped/looted fixtures, exact four-pose mapping, unrelated gear refusal,
Focal/peripheral/unseen cases and an actual `_draw_corpse` reader assertion. Add an explicit
narrow authored overlay kind if required; do not weaken living PACK rules. Inspect an animated
before/after cycle at native and 2×, settled corpse next to living family, and (5B) equipped
human then same corpse after the vest is taken. No new saved cosmetic data or save version.

## Required wall slice, using the owner's A2 choice

The owner chose **A2, shape-matched pack corners**, on 2026-10-03. Read
`.hermes/plans/2026-09-27_walls-picture-round/` and reproduce that mapping rather than inventing
A3. The choice does not change unseen-wall roof coverage. Keep the bounded implementation and
fallback scope below; no east-west window or new fence/gate mechanics are part of this slice.

For A1/A2, bounded files are `godot/presentation/roof_look.gd`, `main.gd`, `dressing.gd`,
`appearance.gd`, `godot/content/dressing/street.json`, dressing schema, authored manifest and
reproduced wall module PNGs, `godot/check_roof_look.gd`, `check_topdown.gd`, `check_authored.gd`.
Use pack crop/pad pieces in entity depth order, preserve generated timber/block and documented
fallbacks for absent orientations. No invented east-west window or fence/gate tile mechanics.
Missing art can be a documented existing fallback, never a rotated/resized source pretending
to be supplied. Preserve visibility and current roof coverage; unseen perimeter-wall coverage
remains the separate owner choice. Gate chosen corner mapping with its opposite as negative,
body north/south draw order, open/closed/broken door/window states that already exist, unseen
segments and roof cuts. Run roof, topdown, sight, memory, authored and sprites; screenshot
exact comparison scene plus doorway/body crossings. Do this after main.gd phase edits serialize.

## Residual work and the finish line

The remaining grade is **not** permission to recolour the adopted ground pack. Its measured
palette is pinned by the owner. Full generator-family regrade would now replace or edit art
outside this finite pass and touches the wall choice: assess with matched day/dusk/night shots,
then leave a named remainder. This pass's per-source pools supplies a concrete part of warm
night without claiming the overcast grade complete. No palette-wide procedural repaint.

Grime/density can reuse existing inert litter/nature/ground overlays, but is not needed to close
these four slices. Existing eight furnishings stay stable except new sparse additions. Do not
add decals representing unseen blood, tracks, shots or scorch; those require recorded sim facts.
No generator, rain collector, spike trap, placed stove, activated streetlamp, new container state,
new zombie kind, screamer/bloater replacement, crawler/attack/hit/death animation, aim/muzzle
mechanic, idle breath, selected-pawn portrait or forest-density decision enters this pass.

Root/Luna place actual game captures under `.hermes/plans/2026-10-02_art-completion/`, with
short scenario captions (seed, time, resolution, what's deliberately staged). Retain source
contacts separately from runtime proof. Use a temporary Godot SceneTree driver, save screenshots
through viewport image capture, then delete the driver. Native capture at DISPLAY=:0 is known
available; screenshots are judged by eye, not replaced by green geometry gates.

Implementation adds truthful records and removes only completed backlog clauses. Update the
sprite brief for the new source groups and narrow corpse overlay contract, if shipped. Add no
per-item status ledger. Check duplicate JSON keys after integrating concurrent content edits.
Sol reviews the finite diff, visible native-scale results, positive/negative/reader lanes and
scope; root runs final `npm run godot:m2` plus `sprites:check`, `check:routing` when gates/routing
change, `check:timing` if runner/chain changes, content validation and `npm test`, and normal
format/type/lint gates where applicable. No commit/push is delegated by this planning document.
Do not report broad art completion: report chart, four props, one icon and source colours as
completed only when their gates and real screenshots exist, with exact optional polish shipped
and the remaining wall/grade/dressing decisions named separately.
