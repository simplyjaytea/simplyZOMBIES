All contested facts verified in tree. Synthesis follows.

---

# STYLE-B ARC, NEXT PHASE — EXECUTABLE SLICE SPECS (slices 4–6)

Synthesis record, 2026-09-01, against HEAD `8b7b247` **plus the fact the three designs missed: slice 3
(vehicles/props/debris) is in flight, uncommitted, in this working tree** (`git status` shows modified
`prop.schema.json`, `content_validator.gd`, `appearance.gd`, `main.gd`, `worldgen.gd`, `tools/sprites/*`, plus new
prop/debris PNGs). Every slice below lands **after slice 3 commits**, rebased onto it; every line number and chain
count is recomputed against the tree as found.

Owner directives (2026-09-01, binding): all character sprites true-overhead like the player; NPCs/zombies still
never rotate; the player rig slims; gear renders on detailed bodies (pack, long gun, headwear).

## CONFLICTS RESOLVED (kept / discarded, with reasons)

1. **Gear is its own slice, not folded into characters.** Kept: Design 3's split. The characters slice already
   carries 8 sprites, 8 ramps, the zoom-scale fix, the corpse-cull fix, content edits across six files and five
   gate lanes; gear adds 10 sprites, a schema removal, a layer-order rework and a 7-lane gate. Folded is two
   sessions in one slice. Order: **4 weather → 5 characters → 6 worn look**. Weather first because it is
   independent and lands the final accent mood the characters screenshots are judged against; worn look last
   because it hard-depends on textured bodies and imports the rig constants slice 5 settles.
2. **Equip-layer mechanism: Design 3's `EQUIP_DRAW_ORDER` kept; Design 2's table flip discarded.** Design 2
   flipped `EQUIP_UNDER_BODY` to `[]` and kept the `over` tag; an always-empty const and an always-true field are
   the `check_ban_health_bar` anti-pattern, and landing the flip in slice 5 then retiring it in slice 6 reworks
   the same gate lane twice in consecutive slices. **Slice 5 does not touch the equip table, `equipSpriteFront`,
   or `_equipped_gear_layers_resolve` at all**; slice 6 lands
   `EQUIP_DRAW_ORDER = ["torso", "vest", "back", "secondary", "primary", "head", "face"]`, the flat
   `{texture}` return, and the lane rework in one commit. Design 2's lane C
   (`_equipped_gear_draws_overhead`) is discarded with the flip; `WORN_LOOK_OK` lane 2 supersedes it.
   Consequence, stated honestly: for the one slice between 5 and 6, face-on pack/bat art draws via the HEAD-era
   under/over table on overhead rigs — wrong-looking, already wrong today, recorded as the interim in slice 5's
   record.
3. **`equipSpriteFront` retires fully in slice 6** (schema property removed, `item.pack.hiking` key dropped,
   `item_pack_hiking_equip_front.png` deleted, straps live in the one pack PNG). Design 2's "stays mechanically
   supported" is discarded — Design 2 itself deferred the call to the gear designer, and the gear designer
   retired it.
4. **The stale "64x96 feet-anchored" `item.schema.json` descriptions are slice 6's fix**, not slice 5's (both
   designs claimed it). Slice 6 rewrites those very descriptions as part of removing `equipSpriteFront`; slice 5
   fixing the text first would be edited again one slice later, and dropping `item.schema.json` from slice 5
   shrinks its Ajv blast radius. Verified in tree: the stale text is at `item.schema.json:31` and in the
   `equipSprite` description.
5. **Gate name for gear: `check_worn_look.gd` → `WORN_LOOK_OK`, script `godot:check:worn`.** Verified:
   `godot/check_m2_gear.gd` exists — `godot:check:gear` collides inside `package.json`. Design 3's finding kept.
6. **Player slimming numbers: Design 2's constant table kept** (BODY 10.6×11.4, arms/hands/strap in step, head
   unchanged, radial_shade 12.0); Design 3's rougher ~10.5/10.0 discarded. Design 2 owns the rig and shows the
   silhouette arithmetic (shoulders 24.8 → 21.2 px, max extent ≈14.1 px, `look.radius` pin 14.0 untouched).
7. **Gear geometry is relative, not absolute.** Kept: Design 3's rule that `parts/gear.py` imports
   BODY_A/B, ARM_X, HAND_X/Y, HEAD_R, HEAD_Y from `parts/characters.py`. Design 3's absolute pixel numbers
   (hand at 7.2/−10.4, pistol at +8.5/+6.5) were computed against the pre-slim rig — **re-derive them from the
   imported post-slim constants at execution**; the table in slice 6 states offsets in terms of the constants.
8. **Chain counts.** Verified: CLAUDE.md line 94 says **40** and `package.json`'s `godot:m2` chains **40** —
   Design 1 is right; Design 3's "CLAUDE.md still says 35" is stale, discarded. Slice 4 appends one gate, slice 5
   appends none, slice 6 appends one. Every count is computed against `package.json` as found at execution
   (slice 3 may append its own); CLAUDE.md's prose count updates in the same commit each time it moves.
9. **Facing lines stay on all NPCs with zero code change** — Design 2 §6 kept, and it agrees with Design 3.
   `wants_facing_line`'s rule already returns true for every NPC; only its comment and the lane's error prose are
   rewritten ("their rigs draw unrotated, so the art's front is a lie about heading and the line is the truth").
10. **Raiders keep one shared body** (`raider_body`, both archetypes; tints removed). The owner's "gear renders on
    detailed bodies" is discharged by slice 6's machete/pistol layers at Focal — earned information; the raider
    schema's shared-look clause stands. Designs 2 and 3 agree; recorded in the docs/30 amendment.
11. **Daylight veil: refused, with an escalation clause** — Design 1 §5 kept verbatim. No disabled toggle ships;
    if the noon screenshot pair is genuinely ambiguous the question goes to `HANDOFF.md` as waiting-on-owner.
12. **Rig-interface README text splits across slices**: slice 5 writes the one-convention section (true overhead;
    the split is shading — radial on the rotating player, NW on everything static — and rotation — player only)
    plus the rig guarantees (shoulders ≤ ~21 px centred, head ≤ r 7.5); slice 6 adds the worn-art interface
    (64×64 centre-anchored, forward = up-canvas, neutral/radial shading carve-out for body-worn art, footprints,
    blunt ≥ 2 px).
13. **docs/30 gets one new dated entry, in slice 5**, covering all four owner directives (all-overhead art;
    NPCs never rotate — anonymity clause and single-transform socket unmoved; player slimmed; gear renders at
    Focal as earned information beside the shared-raider-body clause). Slice 6 references it and adds nothing to
    docs/30; slice 4 adds only Design 1's one-liner "Rain is ambience, not weather" under the art decision.
14. **Weather's lane-B scans and characters' `_draw_entities` edits are compatible** — characters adds
    `px_scale` and `Appearance.moving(` without touching the palette reads lane B pins. Slice 5 runs
    `godot:check:weather` after its edits to prove it.

---

## SLICE 4 — "The district stands in the rain" (weather & mood)

Design 1 adopted whole. Compressed spec; its §3 table and §6 lanes are normative.

**Files:** `godot/presentation/rain_look.gd` (new, `RainLook`, static pure functions, no state);
`godot/presentation/palette.gd` (accent regrade + new keys + delete 5 dead constants);
`godot/presentation/main.gd` (wire dead keys, replace bright literals, `_draw_rain()`, one line in `_draw()`);
`godot/check_weather.gd` (new → `WEATHER_OK`); `scripts/run-godot.mjs` (`case "--weather"`, clone of `--road`);
`package.json` (`godot:check:weather`, appended to `godot:m2`); `CLAUDE.md` (chain count prose);
`docs/23-roadmap.md`, `docs/30-decisions.md` ("Rain is ambience, not weather"); `HANDOFF.md` only if the veil
escalates. No content JSON, no schemas, no sim files.

**Settled mechanisms:**
- **Accent regrade**, Design 1 §3 table normative: `window` `#7ec8e8`→`#6b8794`; new keys `windowRim` `#8fa9b4`
  (replaces `#b8eaff` literal), `facing` `#cfccc08c` (replaces `Color(1,1,1,0.55)`), `aimCone` `#b9c2c94d`
  (replaces `Color(0.85,0.9,1.0,…)`), `rain` `#c2c9cf21`; `groundItem` `#d8c07a`→`#a89a70`. Wire the three dead
  keys `glimpse`/`memory`/`night` to their hardcoding call sites (zero visual change for `night`; near-zero for
  the other two — the work is dead-socket wiring, not muting). Delete `SWING_RGB`, `NIGHT_RGB`, `SHADOW_RGB`,
  `SHADE`, `CONDITION_TINT_HEX` (zero readers — the milestone's eleventh dead-socket batch). Lamp pools stay
  warm on purpose and get pinned warm (`LIGHT_POOL_NEAR.r > .b`, `a ≤ 0.25`). Entity/prop tints, `outline`,
  `CONDITION_TINTS` untouched (characters-slice / UI material). All values are starting points; the gate's
  property bounds arbitrate, tune by screenshot inside them.
- **Rain**: one screen-space streak layer, deterministic presentation ambience keyed off `world.tick` — the sim
  has no weather (docs/16 is Milestone 3; re-keying then is the named forward edge). `RainLook` constants
  `STREAK_COUNT 140` (gate-bounded ≤ 256), `FALL_PX_PER_TICK 9.0`, `SLANT 0.22`, `INTENSITY_MIN 0.4` (it never
  stops raining — onset/end would read as a weather event and imply a system that does not exist),
  `PERIOD_TICKS 1800`. Two-octave integer-hash value noise for intensity; road-paint-prime hashes per streak
  (no RNG stream); endpoints `roundf`-snapped **inside** `segments`. Time base
  `float(world.tick) + clampf(accumulator/TICK_SECONDS, 0, 1)`; frozen when paused; 10× under fast-forward —
  accepted, recorded. Indoor cull via `falls_at` (`indoors != 0` → false; out-of-bounds/null map → true). One
  `draw_multiline` for the whole sky, alpha `× (0.6 + 0.4·intensity)`.
- **Draw order, decided:** background → district → light pools → entities → **rain** → night wash.
- **Daylight veil: refused** (conflict 11). Screenshots taken regardless; escalation clause stands.

**Sprite batch: none — zero PNGs, stated in the record** so nobody goes looking for the missing art.

**Gate `WEATHER_OK` — lanes A–E** (Design 1 §6 normative, each red both ways):
- **A** accent property bounds on the live `Palette`, with built-in true negatives asserting every **old** value
  fails its bound, plus the warm-pool pin with its own TN (`Color(0.5,0.6,1.0,0.2)` refused).
- **B** dead-socket wiring: `_function_body` scans prove `_draw_night_wash`/`_draw_entities`/
  `_draw_window_glass` read `Palette.COLOURS[...]` and no longer contain the old literals; empty body fails
  "had nothing to judge", never skips.
- **C** rain pure: determinism (identical at fixed integer t), bounds, whole-pixel snap, falls-and-slants; TN:
  frozen rain red (t vs t+1 differ), ≥ 8 distinct x-columns, intensity spread ≥ 0.25 and min > 0 sampled 4096×
  over a day; textual no-`static var`/no-RNG on the whole file; `STREAK_COUNT ≤ 256`.
- **D** wired and ordered: `_draw` indices of entities → rain → night wash strictly ascending;
  `_draw_rain` contains `RainLook.segments(`, `RainLook.falls_at(`, `draw_multiline(`.
- **E** `falls_at` boot (suburb@64, seed 20260805): indoor tile false (the TN), outdoor true, out-of-bounds and
  null-map true.

**Traps:** lambda-capture/packed-array (accumulators as locals; `PackedVector2Array` returns are value copies);
no `static var` in `RainLook` (lane C forbids); grep `func _draw_rain(`/`func segments(`/`func falls_at(` before
trusting textual lanes; 8-digit hex is RGBA; snap inside `segments`, not at call sites; never touch
`light_look.gd` or `NIGHT_WASH` for how rain reads; prettier-covered paths add `typecheck`/`lint`/
`format:check`; **rebase over slice 3's landed commit and compute the chain append against `package.json` as
found**.

**Verification:** `npm run godot:check:weather` iterating; `npm run godot:m2` (check `_OK` lines + exit code,
ignore ObjectDB noise); `npm run typecheck && npm run lint && npm run format:check`; noon/dusk/night screenshots
via throwaway Xvfb `SceneTree` driver (deleted; PNGs to `.hermes/plans/`), rain over street, absent over a seen
interior; `npm run godot:run` — drizzle breathes over ~90 s, pause freezes it, lamp pools stay warm.

**docs/23 record sketch:** delete "Weather & mood" from what's-left; record the streak layer (pure statics,
hash-not-stream, never stops, re-keyed to docs/16 when it lands), drawn over bodies under the wash, indoor-culled;
the accent regrade with lamp pools pinned warm; three dead keys wired + five dead constants deleted (eleventh
dead-socket batch); `WEATHER_OK` lanes A–E named. Deferrals: ground splashes/ripples; per-streak brightening in
lit pools; slant from sim wind at docs/16; daylight veil considered and screenshot-refused (or
shipped-with-lane / escalated — whichever actually happened). Zero sprites shipped, stated.

---

## SLICE 5 — "Every body is an overhead rig" (characters)

Design 2 adopted, minus the equip-table flip, minus `item.schema.json` (conflicts 2, 4), lane C dropped.

**Files:** `tools/sprites/parts/characters.py` (shared `_figure(canvas, p)` assembler, slimmed player, 7 new
keys); `tools/sprites/draw.py` (`nw_shade(gain)` — per-pixel,
`factor = 1 − gain·clamp((dx+dy)/26, −1, 1)`, no PIL drawing/resampling); `tools/sprites/palette.py` (8 ramps +
`GROUND_FACING` additions); `godot/assets/sprites/` (`player_body` regenerated slim; `survivor_mara` +
`zombie_shambler` hand files **replaced by generated** and their keys added to the registry in the same commit;
new `survivor_ellis`, `survivor_colonist`, `zombie_screamer`, `zombie_bloater`, `raider_body`);
`godot/content/zombies/screamer.json` + `bloater.json` (add `sprite`, **remove** `tint`);
`godot/content/survivors/uniques/ellis.json` (add `appearance.sprite`); `godot/content/colony/looks.json` (add
`"sprite": "survivor_colonist"` ×6 + regrade the six tints to `#a89478 #c99a6f #a2917b #e0c49a #b58a63 #d9c7ab`);
`godot/content/raiders/scav.json` + `gunhand.json` (add `"sprite": "raider_body"`, remove tint `#a2705a`);
`godot/presentation/camera.gd` (`const ART_NATIVE: float = 64.0`); `godot/presentation/appearance.gd`
(`blit_scale`, `moving`, comment rewrites — **not** the equip table); `godot/presentation/main.gd`
(`_draw_entities`: `px_scale` on body/equip rects and radii; `moving()` in the peripheral cull);
`godot/check_appearance.gd` + `godot/check_topdown.gd` (lanes below); `godot/assets/sprites/README.md` +
`tools/sprites/build.py` MODULES comment (one-convention rewrite + rig guarantees, conflict 12);
`docs/23-roadmap.md`, `docs/30-decisions.md` (the dated owner-directive entry, conflict 13). **No
`package.json`/CI change** — both gates already chained, `sprites:check` already in CI. **Not touched:**
`item.schema.json`, `EQUIP_UNDER_BODY`/`EQUIP_OVER_BODY`, `_equipped_gear_layers_resolve`.

**Settled mechanisms:**
- **Slimmed player** (Design 2 §2 table normative): BODY 12.4/11.8 → **10.6/11.4**; ARM 9.4/3.9/5.6 →
  **8.4/3.4/5.2**; FOREARM → **7.1/2.9/4.1**; HAND → **(6.5, −10.0, r 2.2)**; HEAD_R **5.8 unchanged**; strap
  band and pouch in step; `radial_shade` 13.0 → **12.0**. Mass stays radially centred on (31.5, 31.5);
  `look.radius` stays 14.0 (`_the_player_has_a_body` pin untouched). Start values; the fixture screenshot
  judges, the owner judges the screenshot.
- **Rig family**: one `_figure` assembler; the player closes with `radial_shade`, every static rig with
  `nw_shade(0.12)`. Roster per Design 2 §3: Mara (bob + rolled sleeves, no tint, white pass-through); Ellis
  (broadened 11.8×12.4, grey beard crescent); colonists (achromatic `colonist_grey` S=0 rig — the one
  legitimate grayscale-to-tint case; composed luminance = g × luma(tint), which makes the ground-contrast guard
  computable → lane B); shambler (plain, trailing right arm, seeded mottle); screamer (pale head r 7.5 with
  black mouth void, narrow shoulders, `screamer_red` seeded from `#d95947` through the clamp — the regrade mutes
  the old flat tint deliberately, recorded); bloater (16.5×15.5, the only rig allowed near the tile edge, small
  sunk head, distension arcs); raiders (one `raider_body` — hood, webbing X). `zombie.base` spawns nowhere and
  gets no art; the record says so.
- **Colour moves from content tint to generator ramp**; the look stays content-owned (the `sprite` key). The
  pinned-hex lane `_tints_come_from_content_not_code` goes red mid-slice by design; its successor (lane A) lands
  in the same commit, never a loosened copy.
- **Zoom-scale defect lands** (inherited deferral a): `Appearance.blit_scale(zoom) = zoom / CameraUtil.ART_NATIVE`;
  hoist `px_scale` once in `_draw_entities`; `size = texture.get_size() * px_scale`;
  `r = float(look["radius"]) * px_scale` (peripheral disc, fallback disc, contact shadow follow). Resolver stays
  zoom-innocent. Aim-cone `+36/+44` and facing-line `+12` stay screen-px UI constants, named deliberate.
- **Corpse cull inversion lands** (the mechanical half): `Appearance.moving(vel)` — missing velocity is
  motionless; cull becomes `if not Appearance.moving(vel): continue`. Corpse **art** stays deferred (a second
  rotation collides with the `count("draw_set_transform(") == 1` spine; what a glimpsed corpse shows is an
  owner-adjacent scarcity call) — new what's-left entry "a corpse reads as a corpse".
- **Facing lines: zero code change** (conflict 9). **Peripheral anonymity untouched** (disc now scales by
  `px_scale` — size, not information).

**Sprite batch (8 keys, all `parts/characters.py`):** `player_body`, `survivor_mara`, `survivor_ellis`,
`survivor_colonist`, `zombie_shambler`, `zombie_screamer`, `zombie_bloater`, `raider_body`. All 64×64, 1 px
`#161614` inward outline, no baked shadow, NW shade except the player's radial. **New ramps** (all through the
clamp): `hair_black #2a2622`, `beard_grey #8d8579`, `colonist_grey #c2c2c2` (S=0), `gore_rot #8a8f7c`,
`screamer_red #d95947`, `screamer_pale #cfc9bd`, `bloater_green #6b8c47`, `raider_drab #7d7568` (the darker
`#6d6558` fails the ground guard by arithmetic). `GROUND_FACING += [gore_rot, screamer_red, bloater_green,
raider_drab]`; `colonist_grey` deliberately not listed — composed clearance is lane B's job, comment names the
lane.

**Gate lanes** (chain unchanged):
- `check_appearance.gd` **A `_the_roster_resolves_bodies`** (replaces `_tints_come_from_content_not_code`). TP:
  every roster id resolves `texture != null` through `for_entity`; non-colonists `tint == Color.WHITE`; each
  colonist `tint ==` its looks.json hex (the modulate composition asserted). TN: a stripped-content copy yields
  `texture == null` + role colour for one member of each family — colour can never move back into the draw loop.
  `Appearance.forget()` between worlds.
- **B `_colonists_are_tinted_grey`**: raw-pixel achromatic check (`max(|r−g|,|g−b|) ≤ 2`); composed ground
  clearance — median opaque luma × luma(tint) ≥ max `SURFACE_TINTS` luma + 0.06 for **each** looks.json tint,
  read from the real palette and real content; built-in TN: retired `#5c4632` must fail the predicate.
- `check_topdown.gd` **D `_bodies_scale_with_the_zoom`**: pure — `blit_scale(step)·64 == step` over
  `ZOOM_STEPS` walked, `blit_scale(ART_NATIVE) == 1.0`, `ZOOM_STEPS.has(ART_NATIVE)`; dead-socket — textual on
  `_draw_entities`: contains `Appearance.blit_scale(`, `texture.get_size() * px_scale`,
  `float(look["radius"]) * px_scale`; empty body fails loudly.
- **E `_a_still_body_is_not_glimpsed`**: pure TP `moving({dx:1,dy:0}) == true`; TN `moving({0,0}) == false`,
  `moving(null) == false` (the corpse case); textual socket: `_draw_entities` contains `Appearance.moving(`.
- `_only_the_player_rotates` assertions untouched (error prose updated); `_the_player_has_a_body`,
  `_every_canvas_is_64`, `_sprite_keys_resolve` untouched and judging all eight PNGs for free.

**Traps:** `Appearance._cache` static var — `forget()` before every probe; the validator depth split —
`zombies/` and `survivors/` **are** oracle dirs, so `npm test` is mandatory, while `colony/`/`raiders/` are
shallow-only and lanes A/B are their real enforcement; `for_entity` kind-routing computes "survivor" for
`colony.look.*` and resolves anyway — note in lane A's comment, do not "fix" in passing; grep
`func blit_scale(`/`func moving(` before trusting textual lanes; lane-B statistics as straight-line locals;
Pillow determinism (per-pixel + seeded `random.Random(f"{key}:{salt}")`, no resampling);
`count("draw_set_transform(") == 1` is load-bearing — it is *why* corpse art is deferred; no sim files touched —
if any `M2_BALANCE` line moves, diagnose with a throwaway driver, never theorise; **rebase over slices 3 and 4;
run `godot:check:weather` after the `_draw_entities` edits** (lane-B scans must stay green, conflict 14).

**Verification:** `sprites:check`, `godot:check:appearance`, `godot:check:topdown`, `godot:check:weather`
iterating; `npm run godot:m2`; `npm run godot:validate` **and** `npm test` (oracle recurses into
zombies/survivors); `typecheck`/`lint`/`format:check` (JSON is prettier-covered); day/night/zoom-32 screenshots
via throwaway driver into `.hermes/plans/2026-09-01_style-b-arc-slices-shots/slice5-*.png`, driver deleted;
`godot:run` — WASD turn, colonist beside Mara, screamer at night, all four zooms.

**docs/23 record sketch:** delete "Characters re-authored for overhead" from what's-left; add "a corpse reads as
a corpse" (art half); strike the cull half of the corpse defect naming lane E and the zoom-scale deferral naming
lane D; record lanes A/B/D/E, the looks.json regrade with the composed-luma arithmetic, the tint→ramp move, the
hand-art takeover convention (Mara/shambler keys now registry-owned; after slice 6 no hand art remains), and the
interim: face-on gear art draws on overhead rigs via the unchanged equip table until the worn-look slice.
**docs/30:** the dated 2026-09-01 owner-directive entry (conflict 13). **Honest deferrals:** display-rotation
lerp (named, unmoved); the entire worn look incl. equip-table rework and `equip_front` retirement (slice 6);
corpse prone art + the glimpsed-corpse question; per-source light tint; Detail tiers unchanged ("detailed NPC"
maps to Focal).

---

## SLICE 6 — "What you carry shows on your body" (worn look)

Design 3 adopted whole, with conflict-7 geometry re-derivation and the schema-text fix it inherits (conflict 4).

**Files:** `godot/presentation/appearance.gd` (delete `EQUIP_UNDER_BODY`/`EQUIP_OVER_BODY`; add
`const EQUIP_DRAW_ORDER: Array[String] = ["torso", "vest", "back", "secondary", "primary", "head", "face"]`;
`equipment_layers_for` returns flat ordered `Array[Dictionary]` of `{texture}`; `_resolve_equip_key` keeps only
`equipSprite`); `godot/presentation/main.gd` (`_blit_body(rect, texture, col, layers)`: body first, layers in
order, same rect, no modulate on layers); `godot/content/schemas/item.schema.json` (**remove**
`equipSpriteFront`; rewrite `equipSprite` description — 64×64 centre-anchored, rendered slots =
EQUIP_DRAW_ORDER, unrendered: belt/eyes/gloves/legs/feet — killing the stale 64×96 text);
`godot/content/items/*` (`item.pack.hiking` drops `equipSpriteFront`; ten items gain `equipSprite` keys);
delete `godot/assets/sprites/item_pack_hiking_equip_front.png`; `tools/sprites/parts/gear.py` (new, registered
in `build.py` MODULES); `tools/sprites/palette.py` (ramps `gunmetal #5a5c60`, `wood_worn #705c42`,
`canvas_gear #7d7663`, all into `GROUND_FACING`); ten generated PNGs (below; `item_bat_aluminium_equip.png`
**replaced** by generated, key becomes registry-owned); `godot/check_worn_look.gd` (new → `WORN_LOOK_OK`);
`godot/check_appearance.gd` (`_equipped_gear_layers_resolve` reworked: pack = one layer; the
"no equipSprite → no layer" TN moves from the knife to `item.spear.improvised`); `scripts/run-godot.mjs`
(`--worn` case); `package.json` (`godot:check:worn`, appended to `godot:m2`); `CLAUDE.md` (chain prose);
`godot/assets/sprites/README.md` (worn-art interface section, conflict 12); `docs/23-roadmap.md`. **One commit**
for schema + content + PNG deletion + gate rework — splitting any of it is a red `npm test` (Ajv recurses;
`godot:validate` will not see it).

**Settled mechanisms:**
- One pinned draw order, world height from the skin up; the under/over split and the always-true `over` tag
  retire (conflict 2). Rotation/NPC behaviour: **zero new code** — layers composite inside `_blit_body`, riding
  the player's transform and sitting unrotated on NPCs.
- **Slots deliberately unrendered, with reasons recorded:** belt (batch-2 art first), gloves (batch 2), eyes
  (crown-occluded — permanent), legs/feet (invisible from true overhead — permanent).
- **Tint-only bodies composite nothing, by design** — after slice 5 no detailed body is tint-only; the disc
  fallback stays layer-less (lane 6 pins it).
- **Scarcity survives docs/01 clause 4:** the Peripheral early-out draws a disc and `continue`s before equipment
  is read — distance gates it structurally via `SimVisibility.detail()`; at Focal a carried machete is the
  sanctioned animation channel (`raiders.gd` already defines a raider as "a body with a weapon in its hand");
  layers never read health/infection/quality/ammo/durability/attachments — **armor-wear display and attachment
  rendering refused**, recorded.
- **The "long gun shows" directive is discharged by the bow plus the long-shaft melee family** — no rifle or
  shotgun item exists and none is invented; the record says so.
- Holstered pistol (carry shown at the hip; the aim cone announces firing) — recorded simplification, revisit
  only on playtest confusion.

**Sprite batch (10 keys, `parts/gear.py`; all geometry re-derived from imported `characters.py` post-slim
constants — conflict 7):** `item_knife_kitchen_equip` (1.5×7 blade from the right hand, −y);
`item_pipe_steel_equip` (2×12 shaft across the hands); `item_bat_aluminium_equip` (13-long taper 3→2,
replaces the face-on PNG); `item_machete_rusted_equip` (3×10 blade, seeded `:rust` flecks);
`item_bow_hunting_equip` (the long silhouette — ~16 px stave in the left-hand column, string in `strap` dark);
`item_pistol_service_equip` (holstered L-blob at the right hip ≈ (ARM_X, +6.5)); `item_pack_hiking_equip`
(re-authored overhead — ~15×11 mass centred (0, +6.5), shoulder-strap bands to (±ARM_X·0.7, −4); straps live in
this one PNG); `item_vest_scrap_equip` (torso ellipse BODY_A−2.5 × BODY_B−2.5, plate-seam pixels);
`item_cap_canvas_equip` (crown r ≈ HEAD_R+0.5, brim stub forward, fully occludes hair);
`item_mask_cloth_equip` (2 px crescent at the crown's forward edge). All 64×64, pivot (31.5, 31.5), forward −y,
1 px outline, **neutral/radial shading — no NW bake on anything body-worn** (README carve-out: one asset serves
the rotating rig and static bodies), blunt ≥ 2 px, seeded wear.

**Gate `WORN_LOOK_OK` — seven lanes** (canvas/resolution already enforced dir-wide by `_sprite_keys_resolve` +
`_every_canvas_is_64`; not duplicated):
1. **Kit items never invisibly armed**: every kit-reachable item with `equipSlot ∈ EQUIP_DRAW_ORDER` declares a
   resolving `equipSprite`. TP: knife/pipe/bat/machete/pistol pass. TN: fixture tree with the bat's key blanked
   → red. Loot-only items may lawfully lack art; the record lists them.
2. **Order pinned**: fixture actor with vest+pack+pistol+bat+cap+mask → exactly six textures in
   EQUIP_DRAW_ORDER sequence, compared by resolved-texture identity, never by count. TN shown once by mutation
   (swap two const entries → red → revert).
3. **The draw path reads the list** (dead-socket): `_function_body(main.gd, "_draw_entities")` contains
   `Appearance.equipment_layers_for(world, eid)` exactly once, at an index after the Peripheral `continue`;
   `_blit_body`'s body draw index precedes the layer loop's. Empty body → fail, never skip.
4. **No gear on a glimpse**: lane 3's index assertion is the structural proof, paired with check_appearance's
   no-equipment → `[]` negative; check_topdown's anonymity lane named in the print as standing co-assertion.
5. **Layers pass through untinted** (textual: layer draw call carries no colour argument; TN: appending `, col`
   goes red).
6. **Discs composite nothing** (textual: the texture-less fallback branch contains no `equip` token — red the
   day someone wires layers onto disc bodies instead of giving them rigs).
7. **End-to-end**: `SimBoot.playable(seed)` → player's layers non-empty and containing the knife's texture.

**Traps:** `godot:check:gear` collides with the sim gate — use `worn`; schema removal is oracle-enforced only —
one commit; `Appearance._cache` `forget()` in lanes 1/2/7; the `{texture, over}` → `{texture}` ripple — rework
`check_appearance` and any `_blit_body` textual expectations in the same commit, grep
`func equipment_layers_for(`/`func _blit_body(` before trusting lanes; accumulators as locals, no
PackedStringArray; two slots can hold value-identical dicts — iterate, never `find`/`erase`; `build.py` MODULES
and `palette.py` will merge-conflict with slices 3/5 — rebase onto their landed commits; `equipment.slots`
values come back float after a load — keep the `int(item)` cast; no balance claim — all four M2_BALANCE seed
lines byte-identical.

**Verification:** `godot:check:worn`, `sprites:check`, `godot:check:appearance` iterating; `npm run godot:m2`
(chain +1, count as found); `npm run godot:validate` **and** `npm test` (schema + items changed — the depth
split); `typecheck`/`lint`/`format:check`; screenshots — player with pack+bat rotating, a Focal raider showing
machete vs pistol, a Peripheral disc showing nothing — throwaway driver, deleted; `godot:run` eyeball.

**docs/23 record sketch:** record the worn look naming all seven lanes, ten generated keys, `equipSpriteFront`
retired (a mechanism removed *before* it became the next dead socket), the coverage table with the batch-2 list
(spear/axe/sledge, candle/lamp, wrap, rig.chest, satchel, gloves) and the never list (glasses, pants/boots, with
reasons), the no-long-gun honesty line, the holstered-pistol simplification. **Honest deferrals:** batch-2 gear
art; rendering the belt slot (needs its art first); in-hand pistol; any attachment/wear display (refused, not
deferred — say which). `HANDOFF.md` unchanged — no owner decision pending; the owner judges batches by
screenshot in the standing loop.

---

## AMENDMENTS — exact statements superseding the QUEUE note in `.hermes/plans/2026-09-01_style-b-arc-slices.md`

The executor of each slice updates the plan file in the same commit. Replace as follows.

**1. Replace QUEUE item 4's paragraph ("4. Weather / mood. …") in full with:**

> **4. Weather / mood — superseded by the synthesis record of 2026-09-01 (slices 4–6).** Executable spec:
> slice 4, "The district stands in the rain". Correction to this note's premise: the glimpse disc and memory
> mark are already near-muted hardcodes shadowing dead palette keys — the work there is dead-socket wiring, not
> muting; the genuinely bright constants are window glass `#7ec8e8`, the pane rim `#b8eaff`, the facing line,
> the aim cone, and `groundItem` `#d8c07a`. Rain is a deterministic presentation-side ambience keyed off
> `world.tick` (docs/16's weather sim stays Milestone 3); gate `WEATHER_OK`, chain +1.

**2. Replace QUEUE item 5's paragraph ("5. Characters re-authored for overhead. …") in full with:**

> **5–6. Characters, then the worn look — superseded by the synthesis record of 2026-09-01.** Owner directives
> of 2026-09-01: **all character sprites are authored true-overhead like the player; NPCs and zombies still
> never rotate** (`body_rotation(false, *) == 0.0` and the count==1 socket stand untouched — an unrotated rig
> faces up-canvas and the facing line carries real heading); **the player rig slims**; **gear renders on
> detailed bodies — pack, long gun, headwear** — as earned Focal information. This supersedes this note's
> "NPCs/zombies stay face-on and never rotate" sentence in its face-on half only, and retires the face-on
> authoring convention itself. The old slice 5 splits in two: **slice 5 "Every body is an overhead rig"**
> (all eight roster bodies generated overhead; the slimmed player; inherited deferral (a), the zoom-scale
> defect, lands here; the corpse-cull inversion lands here; colonists remain the one grayscale-to-tint case,
> now as an achromatic rig × regraded looks.json tints) and **slice 6 "What you carry shows on your body"**
> (inherited deferral (b) resolved: `EQUIP_DRAW_ORDER` replaces the under/over split, `equipSpriteFront`
> retires, ten generated gear keys, gate `WORN_LOOK_OK` via `godot:check:worn` — `godot:check:gear` collides
> with the sim gate — chain +1). Inherited deferral (c), the display-rotation lerp, remains deferred and named.
> Order: 4 → 5 → 6; 6 hard-depends on 5's textured bodies and imports its rig constants.

**3. In "Standing constraints across all queue slices", replace the final clause ("the art-style seam (rotating
player beside face-on pawns) is owner-accepted until slice 5 exists to judge it properly") with:**

> the art-style seam is resolved by the 2026-09-01 owner directives: one authoring convention, true overhead;
> the remaining splits are shading (radial on the rotating player, NW on everything static) and rotation
> (player only). The one-slice interim between slices 5 and 6, in which face-on gear art draws on overhead rigs
> through the unchanged equip table, is accepted and recorded in slice 5's record.

**4. Append one line to the PRODUCTION-METHOD note:**

> Amendment (2026-09-01): the overhead re-author retires the hand-art convention — `survivor_mara.png` and
> `zombie_shambler.png` become registry-owned in slice 5 and `item_bat_aluminium_equip.png` in slice 6; after
> slice 6 no hand-authored PNG remains, and the "never registry-owned" sentence above is historical.

---

Sequencing note for the executor: slice 3 is uncommitted in this working tree — land it first; every slice
rebases onto the tree as found and recomputes chain counts against `package.json`, never against the numbers
quoted here (40 at HEAD `8b7b247`; +1 in slice 4, +0 in slice 5, +1 in slice 6). Key files:
`.hermes/plans/2026-09-01_style-b-arc-slices.md`, `/home/user/simplyZOMBIES/godot/presentation/appearance.gd`
(equip consts at lines 45–46), `/home/user/simplyZOMBIES/godot/content/schemas/item.schema.json` (stale 64×96
text at line 31), `/home/user/simplyZOMBIES/godot/check_m2_gear.gd` (the name collision),
`/home/user/simplyZOMBIES/CLAUDE.md` line 94 (chain-count prose).
