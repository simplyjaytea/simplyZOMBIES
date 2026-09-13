# HANDOFF

**This is not a status ledger.** A per-item checkbox file of this name was retired into
[docs/23](docs/23-roadmap.md) after drifting four times, most recently by ~34 shipped-but-unticked
items. This file came back a commit later as something smaller and it must stay that way. Do not
put checkboxes back in here.

What this file is: a short note for whoever picks the project up next. **Where the code is** lives
in [where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands), which is the authority
and is updated in the same commit as the work it describes — where this file and that section ever
disagree, that section is right. **Why something is shaped the way it is** lives in
[docs/30](docs/30-decisions.md). **What must not be broken** lives in `CLAUDE.md`. **How to get a
container running** lives in `AGENTS.md`.

---

## State, as of 2026-09-12 (the alpha-roster arc)

Green, and verified this session rather than quoted: `npm run godot:m2` chains **69 gates**
(counted off the script in `package.json`, which is the authoritative list — the number here keeps
drifting, so count it there rather than trusting this line) and exits 0, `npm test` is **45 files /
594 tests** passing, and `godot:validate`, `godot:test` and `godot:smoke` are clean. CI's `check`
job runs those plus typecheck, lint and format; its `performance` job runs the two TypeScript
benchmarks.

The game is playable — `npm run godot:run`, needs a display. It boots on day 1 in daylight with
**three colonists** (you, Mara, and Ellis — the bigger-colony decision), and the survival loop is
**on**: `SimShambler.GRABS_ENABLED` ships `true`, so a shambler in reach swipes, closes into a
hold, bites, and a bite can infect. Wounds bleed; pressure, bandaging, rescue and recovery are all
live in ordinary play. The decision, the measurement and the gate promotions are in
[docs/23's flag record](docs/23-roadmap.md#where-milestone-2-stands), which now ends with the flip.

## What landed recently

**2026-09-12 — the alpha-roster arc is closed: fifteen slices, and a re-baseline that vindicates
the content and indicts one rule.** The roster went **152 → 362 bases** and the chain **57 → 69
gates**. The last slice, *armour that reaches a campaign*, gave colonists a rule that equips armour
they find — no starting kit, by the owner's decision — and gave the balance harness a dressed arm
beside a bare control, since once colonists dress themselves the old tier is not a bare colony any
more.

**The re-baseline is the number to know**, measured on one driver in three configurations. Against
the pre-arc tree, **three of four seeds are byte-identical with the full 362-base roster** and the
fourth only doubled its grabs while still ending 3/3 — so 186 new loot rows moved contact and moved
no outcome, which is exactly what the reserved re-baseline predicted. **The acquisition rule is
what moved outcomes**, on two seeds: 404 from a quiet 7-grab campaign to 124 grabs and one
survivor, 90210 from two deaths to four. Colonists leave the compound to fetch gear, and contact is
what happens outside the walls.

**So the arc made the campaign harder and the record says so.** That is now a named question for
the human ten-day playtest rather than something settled by a harness, and the lever is one static
(`SimJobs.WEAR_FOUND_ARMOR`) if the answer is "too punishing".

**Two findings worth carrying forward.** A lane was written, measured and thrown away because it
stayed green with `armor_damage_factor` deleted — it was measuring the damage closure's clamp, not
armour; the replacement samples unhurt colonists only and reads 1.0000 bare against 0.7212 dressed.
That is the fifth unfailable assertion this arc. And the worktree/loot-stream confound recurred
within a day of being written down: a before-and-after across two trees with ~115 loot rows between
them appeared to show a tuning lever backfiring. Compare on one tree or do not compare.

**CI was restructured mid-arc, owner-approved.** `npm run godot:m2` now runs in its own job
(`godot-m2`, 45 min) parallel to `check` (25 min), with `godot-exports` waiting on both, because
`check` was being cancelled at 30m15s on the second-to-last gate of 69 — the second time a timeout
had come due. The chain is **26m45s locally / 19–23 min on CI**, measured; both places that quoted
"~11.8 min" from eight days earlier were corrected.

**2026-09-12 — camping gear, and what a bed is made of.** The arc's thirteenth slice, absorbing
the older "bed quality as an authored property" piece. docs/10 had been using "a sleeping bag and a
scalpel" as its own worked example of the footprint puzzle while neither item existed, and
`make_bed` spawned a bare entity with no quality on it. `bedQuality` and `hygiene` are both flat
scalars under an enum — the `buildMaterial` shape, because that is the only depth the shallow Godot
validator enforces unaided — and `furnish_bed` spends the best bedding out of the builder's own pack
when the Construct bed job completes. It is additive by arithmetic rather than by assertion: comfort
is spent against the penalties the night already has, so a bed with no bedding is the bed that
shipped before. Measured over six identically seeded districts, **a cold night on a foam bedroll
restored 84.00 of rest against bare boards' 75.00**.

**Half of docs/04's soap clause shipped and the slice said which half.** A bar banks charges and a
dirtying spends one, but a wash still works with no soap at all — making it required is a rebalance
of a need every colonist has, and a district that rolled none would have no way back from `filthy`,
which `sepsis_mul` reads. Left to the owner rather than taken.

**The loot gate's container lane was rewritten during this merge, and the reason generalises.** It
asserted a flat zero items on the floor after an open, on the strength of a comment reading "a
cupboard is six by four, so a residential roll fits" — an observation about the table of the day
rather than a promise `SimContainers` ever made, since it has always spilled deliberately and says
so at the line that does it. The arc's new rows made residential generous enough to overflow and the
lane went red against correct code. It now asserts the real guarantee: a spilled item re-offered to
the box must be refused, so a spill is never a packing failure. **Sabotage then showed that was
still not enough** — making the module destroy what it cannot fit left it green, because nothing
overflowed on that seed and the assertion had no data — so a fixture now stuffs a cupboard by hand
and makes the accounting balance.

**2026-09-12 — comfort, and books that teach.** The arc's eleventh and twelfth slices. Mood had
seven sources and every one was something done *to* a survivor; a `comfort` block is the first thing
a person can do for their own morale that is not a meal, and it respects the module's existing
non-stacking rule rather than routing around it — one modifier from one source, accumulating toward
a cap, on an int clock. `skills.gd` had been a finished six-region XP ladder with zero item content
since Milestone 1; ten books now pay into the same `_earn`, consumed on reading, with a per-reader
ledger so a second copy of a title already read teaches nothing and is not spent, and a ceiling of
`PRACTICE_POINTS` so a book never out-teaches doing the work.

**Three findings worth more than the content.** The comfort gate's CLOCK lane **could not fail when
written** — the shipped harmonica's clock landed on tick 60000 and the mood cadence divides it, so a
sabotage gating the whole tick left it green; it now deliberately lands off the cadence and asserts
that it does. The books slice measured the entity-keyed-Dictionary trap rather than trusting it and
found it is **worse than CLAUDE.md documents**: `canonicalize` throws and the save is written with
the component present and its contents gone. And the shallow-validator trap reproduced a second time
in a second brand-new block — a `teaches` naming a region `skills.gd` does not have passed
`godot:validate` with `GODOT_CONTENT_OK`.

**One needle broke on merge and the repair is in Traps.** `check_m2_comfort.gd` asserted its key was
in the gear gate's `READ_KEYS` by matching the tail of that list — chosen deliberately, because the
bare word appears in that file's prose too. An hour later the books slice appended `"teaches"` and
the lane went red against a gear gate that was correct. It now isolates the `READ_KEYS` line and
asks for membership inside it, and was re-broken afterwards to prove the repair did not weaken it.

**What neither slice shipped:** no autonomy job. Nobody seeks comfort when their mood drops and
nobody ever picks up a manual unaided, so both categories help a colony exactly as much as the
player remembers to spend them. Named in what's left, once, for both.

**2026-09-12 — cooking, water, and noise you can carry.** The arc's ninth and tenth slices,
both built in isolated worktrees and integrated here. Cooking: ten ingredients had shared one meal
between them, because the cook step spawned a single hardcoded id and boiling was a `baseId` rename
written over the item in place. `cooksInto` and `boilsInto` are the exact grammar of `empties` — the
cheapest reader in the arc, because the shape was already shipping and already read — and
`purifies` is a use count that needs no fire, so a tablet is spent once and a pump filter has forty.
Twenty-four bases in `kitchen.json`, gate `godot:m2:transform`, eight lanes.

**The REACH lane caught a dead socket on its first run**, which is the honest reason to trust it:
`item.filter.pump` was complete, correct, read end to end, and in no loot table — the same shape
`item.floodlight.rigged` had before the light slice reached it. Two loot rows fixed it; nothing else
in the sixty-seven-gate chain noticed.

Noise: a `noise` block with a magnitude, a run length and a fuse, on eight new devices, every
magnitude a rung of docs/03's published table. They are **multi-use** — E picks a placed device back
up and it goes down again on a fresh fuse — deliberately opposite to the light slice's one-way
floodlight, both by owner decision rather than by whichever was written first. Gate
`godot:m2:noise`, eight lanes, of which HORDE is the one worth reading: twelve bodies closed from
18.6 m to 3.0 m over 3600 ticks of siren while an identical siren that never went off left its ring
at 20.9 m. **Half of it did not ship on purpose**: the alarm and the noisemaker are still free world
singletons, because `check_m2_materials.gd`'s PINNED lane asserts both by name and repricing them is
a rebalance, not a content addition. It is named in what's left with the run it owes.

**2026-09-12 — armour, both halves: slots to fit it into, and damage it actually stops.** The arc's
eighth slice and the only one that changes every fight. Coverage stopped nothing anywhere — twelve
garments each carried a number that never met a blow. `SimHealth.armor_damage_factor` is the reader,
applied inside `damage_part`, the one closure in the sim that writes `b[named_part]`. The curve is
**not** a new number: `severity_for` had softened escalation by `1 - 0.5 * coverage` since wounds
landed, and that curve moved one step upstream onto the integrity while `severity_for` dropped its
copy, so no shipped severity band moved. Keeping both would have squared it. `SCALABLE` gains a
third table whose profile is a coverage map; a plate carrier is webbing until there is a plate in
it; a fitted pouch grants a real `container` grid with its mass recursing.

**Read the measurement, because it is a negative result and it matters.** `godot:m2:balance` came
back byte-identical on all four seeds — not the mechanic failing but **the harness dressing
nobody**: no starting kit has armour, the fast tier arms hands only, `searches=0`. A throwaway
driver with everyone dressed measured integrity lost falling **14.35 → 8.97 (37%)** on the one seed
where contact stayed identical, and its bare arm was byte-identical, which is the perfect control.
So the mechanic is real and gated, and **the shipped colony still fights in shirtsleeves**. Armour
acquisition is named as its own piece in what's-left and is bigger than the slice that revealed it.

The health-bar ban is untouched (`godot:ban:healthbar` green): the factor is computed inside
`damage_part` and discarded, never stored or published, and `condition.gd` still says only
`armored: true`. Two more assertions were found unable to fail and rewritten — the fifth and sixth
in this arc. One unasked-for behaviour change is flagged rather than buried: `damage_taken` and wound
severity used to disagree and now do not, so high-CON survivors take slightly milder wounds.

**2026-09-12 — light that burns down, and what feeds it.** The arc's seventh slice and the fifth of
the eight readers. Light was the only resource in a resource game that could not run out: no
`burnTicks`, no fuel key, so the electric lamp was strictly and permanently better than a candle,
`item.battery` sat inert in three loot tables saying "Something here needs one" while nothing did,
and the oil lantern had nothing that could refill it. The burn clock runs at movement order 70, five
ahead of the kernel's own light at 75, so a dead wick is dark in the *same* tick's shadowcast; and
it spends only the lamp actually lighting somebody, so max-not-sum now has a consequence.

Both dead sockets in the reader were reached: `HAND_SLOTS` widened so a headlamp works (the lane
measures the lit radius off the real shadowcast, with a fabricated torso lamp as the control that
must light nothing), and the weapon light got a burn and a feed. **Three orphans adopted** — the
rigged floodlight stands up as furniture through fortify's construct channel, the empty jerrycan is
filled by reading the refuel path backwards, and the battery is what the lamp eats. Burn times are
judged against a **measured** yardstick: the gate computes the fully dark stretch from `SimClock` at
run time (72,020 ticks) rather than quoting it. New gate `npm run godot:m2:light_burn` →
`M2_LIGHT_BURN_OK`, nine lanes.

Two notes. A planted floodlight **cannot be picked back up** — deliberate, matching `_place_bench`,
but a real restriction on a thing from the player's own pack, and named in what's-left. And the
slice corrected a claim in its own brief: `item.attach.underbarrel.light` already declared a `light`
block, so "no attachment declares light" was stale.

**2026-09-12 — clothing: warmth, wet and cooling.** The arc's sixth slice and the fourth of the
eight readers. `needs.gd`'s `wearing_wrap` matched the literal `"item.wrap.cloth"`, and that was the
entire clothing-warmth system — four weather kinds shipped gated with nothing in the roster to price
them. Warmth is per-part now, like `armor`: an open map composed by **max**, with cooling as the
same axis negative so a sun hat and a wool hat are one mechanism. `wearing_armor`'s torso-only key
is generalised to the whole weighed body. Twenty-five new bases, none declaring an `equipSprite`
because `EQUIP_DRAW_ORDER` reaches only six slots and most of them sit outside it. New gate
`npm run godot:m2:warmth` → `M2_WARMTH_OK`, nine lanes.

Two things worth knowing. Its sabotage pass **reproduced the shallow-validator trap live**: a
`warmth` block naming a body part that does not exist passed `godot:validate` clean, and only the
new gate caught it — CLAUDE.md's trap entry now cites it. And one assertion needed **three**
sabotages before it was ever seen to fire, because the first two tripped different assertions than
the one written for it. An open question is named in what's-left: positive warmth moves a body
toward comfortable on *both* sides of the ladder, so a winter coat cools you in a heat wave. That is
the shipped cloth-wrap rule, pinned by `check_m2_heat`'s ROOF lane, not something this slice
introduced — but changing it is the owner's call.

**2026-09-12 — named items, the fourth tier.** The arc's fifth slice. `SimItems.TIERS` shipped three
of docs/10's four; the fourth is Named — hand-authored, fixed rolls, always with a drawback — and
the six items docs/10 specifies are content now. The tier row carries `authored: true` (off the
upgrade ladder) and `weight: 0` (out of the global roll), both routed through a new
`rollable_tiers()`, which is the one place a *climb* and a *lookup* are told apart.

**Three of the six drawbacks needed a reader that did not exist**, and this is the part worth
knowing. `melee.gd` published its connect noise as a **literal**, so no weapon in the game could be
heard further than any other; `connectNoise` is content now, defaulted to that same constant so
nothing shipped moved. `attention_emitter.gd` adds worn scent to what a body gives off — summed
rather than maxed, deliberately unlike `armor_coverage_of`, because two helmets do not armour a head
twice but two filthy things do smell worse. And a wound taken while holding something `filthy` is
flagged and priced as a sixth term in the sepsis product. Three drawbacks could **not** be expressed
and were not faked: there is no bite-risk stat, **no zombie declares armour of any kind**, and
`repair_cost` still resolves against nothing.

Two of its lanes could not fail and the slice caught both itself — one was measuring heft and
reporting handling. And `check_loot.gd`'s `TIER_IDS` was a stale hardcoded copy that refused the new
tier correctly while its message said something untrue; it derives from `rollable_tiers()` now.

**2026-09-12 — build materials, the substance that is not scrap.** The arc's fourth slice. One item
id, `item.scrap.metal`, was welded into a `SCRAP_ID` constant in `fortify.gd` and into a second
identical copy in `jobs.gd`, and between them those two lines made it the only substance in the game
that could build anything. A recipe now names a **kind** and an item declares one in `buildMaterial`
(a flat scalar under a twelve-value enum); the owner's call was typed kinds at **uniform cost**, so
per-recipe quantity stays closed — it is entangled with `repair_cost`, a stat nothing resolves.
Thirty new bases across docs/12's gathered and refined tier. New gate `npm run godot:m2:materials`
→ `M2_MATERIALS_OK`, six lanes, eleven sabotages.

Two things to know. **The loot placement is additive, unlike the two slices before it** — materials
are a new category so there was nothing to split, and every prior category keeps its weight while
losing share (industrial dilutes **+21.3%**, the rest under 8%). That is the one number here worth a
second opinion and the reserved re-baseline is what answers it. And **eleven of the twelve kinds are
unspent**: three recipes exist and all three want metal, so the slice landed a vocabulary rather
than an economy. `check_m2_materials.gd`'s RECIPES lane prints that count on every run rather than
letting it go quiet, and the remainder is its own piece in what's-left.

**2026-09-12 — the mask that filters.** The arc's third slice and the second of the eight readers.
A bloater's contamination cloud rolled every survivor on flat proximity and never looked at what
they were wearing, so a cloth mask was worth exactly a bike helmet against a plume. A `filter`
scalar (0..1, best worn wins) is the reader, and `SimInfection.filter_of` is deliberately
`armor_coverage_of`'s twin — same scan, composed by **max, never sum**, because two masks are one
mask. Five shipped-but-inert bases were adopted rather than deleted and eight new ones ship. New
gate `npm run godot:m2:filter` → `M2_FILTER_OK`, seven lanes, each proven red. Its CLOUD lane
reuses the paired-seed technique the medicine slice established, so a coin flip is asserted
deterministically. Two findings went to docs/23's defect list rather than into the slice: the
once-per-survivor contamination bug **was already fixed and the entry describing it was stale**,
and `_has_open_wound` matches `kind == "bite"` alone, so a deep laceration is no way in for a plume.

**2026-09-12 — the medical quality tiers, and the roster the arc was widened for.** The second slice
of the alpha-roster arc, and the first of eight readers the owner took after a census found the
roster's real problem: it is not small, it is **unread** (docs/30, "The readers ran out before the
content did"). Three supplies were welded to one base id each — `ANTIBIOTICS_ID`, `PAINKILLERS_ID`,
and `item.bandage.cloth` written three times inside the colonist doctor — so a second antibiotic was
a code change and a doctor holding a sterile dressing reported carrying no bandage at all. All three
are now content grades on the `bandageTier` model: `antibioticTier`, `painTier`, `illnessTier`,
ranked best-first by one shared scan (`SimInventory.best_by_content_key`, lifted out of
`treatment.gd` because three modules that treatment preloads all needed it). **Thirty-two new bases,
164 → 196**, loot share divided rather than added to so every table's food, drink and medical weight
is byte-identical. New gate `npm run godot:m2:medicine` → `M2_MEDICINE_OK`, eight lanes, each run
red and green before it was trusted.

Two things in it are worth knowing about on their own. The illness `illnessChance` has been handing
out since food shipped **had no treatment at all** — `illnessTier` is that reader, routed through
`can_use` so the menu and the intake cannot disagree. And `WOUND_KINDS["sprain"]` carried
`closeKind: ""` against docs/05's *"Rest, wrap"*, so the one injury the docs treat with a bandage was
the one injury nothing could treat; `wrap` is now the third closer. What deliberately did **not**
ship is the tourniquet: it is not a dressing grade but a fourth thing the `pressure` channel could
spend, and shipping an item with no reader inside the slice that removed three welds would have been
the joke writing itself. It is named in what's-left with its reader.

**2026-09-12 — ammo types, and the first slice of the alpha roster.** The owner opened an item-roster
arc (docs/30's "The round in the chamber" and "The cartridge on the label"; the pieces are named in
[docs/23's what's-left](docs/23-roadmap.md#whats-left-in-milestone-2) under *Items — the alpha
roster*). A weapon could only ever fire one round, matched by exact base id; it now declares
`ranged.caliber` beside `ranged.ammo` — the set it will take beside the round it prefers — and a
round carries an `ammo` block of multipliers folded over the weapon for the shot that spends it.
**Twelve new rounds, 152 → 164 bases**, and a new gate, `npm run godot:m2:ammo` → `M2_AMMO_OK`,
eleven lanes, every one run red both ways. Preference-first keeps every shipped weapon
byte-identical, which the DEFAULT lane pins as numbers rather than as "it still works", and the loot
share was **divided rather than added to** so per-table ammunition weight is flat. It also fixed
three defects found by reading: arrow recovery named the round the bow *prefers*, the director's
preparedness scan would have gone blind to variant rounds (the third time that function has been
wrong the same way), and the magnum cylinder converted a revolver to its own default round.

The digit ban gained a **narrow item-name clause** in the same commit, by the owner's decision and
recorded as one — a cartridge is called what it is called. One predicate, both lanes, and the true
negative is that the identical string is still refused as a `description`.

**2026-09-11 — the first commissioned body.** The player's rig is the first art here the generator
did not draw: `player_body_authored`, a 32×40 pawn made with PixelLab img2img over the shipped
`player_body`, conformed to the published bounds and declared in `authored.json`. It closed the
last open piece in docs/23's commissioned-sprites group and widened the three gates that group
named — the FLIP lane and `check_worn.gd` now judge the **union** of `PAWN_KEYS` and the
manifest's `rig` keys, via the new `Appearance.authored_rig_keys()`. The one that could have gone
weaker silently was FITS: its envelope is a union, so every body added to it makes "is this
overlay inside" easier to answer yes, and it now asserts the commissioned rigs do not widen it,
with a true negative. Gates: `AUTHORED_OK` at 9 rigs, `WORN_LOOK_OK` at a 9-rig envelope,
`TOPDOWN_OK` at 63 pawn keys, `SPRITES_OK` at 3 authored keys. The owner also supplied a written
Dungeon Settlers style spec and asked for it applied while keeping our theme — docs/30's "The
reference treatment". Two of its clauses were **already met** (it asks for an outline that is not
pure black, and `#161614` is deep charcoal; it asks for 2–2.5 heads, and the skeleton is 2.3), so
no gate was amended; the shading clause was applied by code as despeckle → three-tone-per-family
ramp → family clamp, taking the rig from 17 colours to 6. Three honest halves, all accepted by the
owner before the commit: the gain is invisible at the 2× boot zoom, the shipped rig's diagonal
strap was lost (the open-jacket panel is a different tell in its place), and **the roster is
unevenly treated** — a 6-colour player beside rigs of 27 to 88 colours, which is visible at 6× and
subtle in play. That last one is a named piece in docs/23's what's-left, "the ramp, applied to the
whole roster", and it overlaps "the rig read harder"; whichever lands first should absorb the
other.

**2026-09-09 — gunsmithing, eight slices.** A weapon is an assembly now. Its base is the receiver
and `defaultParts` fits real part items into its slots when it spawns, each with its own
condition; a required slot empty is a gun that will not fire and says so; `structural` parts drag
the whole assembly's condition down, so a tired action is what jams a pistol and fitting a sound
one is a repair that costs no ceiling. Parts wear on the channel they are used on (`wearsOn`
against `WEAR_EVENTS`), a worn part's multipliers walk toward *no effect* rather than toward zero,
and a part worn through comes off and lands somewhere — which closed the "a detached attachment is
lost" defect at both ends. `overrides` replaces `ammo` and `jams` outright, resolved by agreement
rather than by order, so a conversion kit that agrees works and two parts that disagree make a gun
nobody can load. Firearm slots widened to optic · barrel · muzzle · magazine · furniture ·
internal (docs/10's table edited), so a can and a longer barrel stop competing. All of it is
reached at a **gunsmithing bench**, built through the same E-key ladder that boards a window, and
drawn by `ui/bench_panel.gd` in prose plus ▲▼↔ with no magnitude anywhere in the read model.
Fitted parts show on the pawn. Gates: new **`godot:m2:bench`** (nine lanes), `godot:m2:attach`
grew from nine lanes to **twenty**, plus new lanes in `godot:m2:upkeep`, `godot:m2:ranged`,
`godot:m2:npc`, `godot:check:worn` and `godot:check:inventory`. `SAVE_VERSION` 28 → **29**. Six
pieces left docs/23's what's-left, including the attachment-fitting screen it had carried since
attachments landed. Measured with a throwaway driver: a pistol reaches "worn" at ~100 rounds and
"failing" at ~200, the action first. `godot:bench` unchanged.

**2026-09-10 — the outpost earns its keep, and a budget breach it found.** A camp that is not home
is an outpost, and an outpost extends where colonists will work (`godot:m2:camp` at eleven lanes).
Measured: 0 of 14 far items in range without one, 14 of 14 with, and `_haul_work` offers nothing at
all in the first case.
**Read this before trusting the camp slice's record.** That slice claimed `jobs._home_centre` carried
`_post_tile`, `_corpse_dump` and `_stock_drop` with it. **It did not** — all three read
`SimTileMap` directly — so it moved the Haul/Scavenge/Rearm radius and nothing else, and the night
watch posted at an annex nobody lived in. The post and the dump follow home now; the stockpile
deliberately does not, because a camp has no roof to be indoors under. The `ANCHORS` lane is what
the corrected sentence stands on.
**A gate that could not fail, found by proving the negative.** The first `REACH` lane established a
camp far away and called it an outpost — but `SimCamp.create` makes the new camp *home*, so it was
re-testing the previous slice. It stayed green with outpost reach removed entirely. Two camps plus
an explicit "home is not the far one" assertion is the fix. Worth remembering as a shape: a fixture
that accidentally satisfies the previous mechanism tests nothing new.
**And the reason the reach nearly did not ship.** It measured **9.8 ticks/s against 62.8** — under
the 20 Hz clock — caused by **one enclosed item**, not by distance. docs/23's defect list had carried
"an unreachable destination costs a full A* every tick" since the review sweep; `_walk` re-planned
whenever its cached path was empty, and empty is what `SimPath.find` returns for no route. A failing
path costs **132 ms** against 5–11 ms for a reachable one. The owner's call was to fix that first
rather than cap the reach; after the fix the same fixture runs at **78.4**. `godot:m2:jobs` gained a
PATHING lane, proved red against the shipped condition.

**2026-09-10 — the camp the player establishes: the seam** (`npm run godot:m2:camp` /
`M2_CAMP_OK`, nine lanes; the chain is **58** now). Home is relocatable. **C** makes camp where you
stand — a fortify channel, so it is interruptible and emits construction noise all the while —
shift+C strikes it, and the HUD says where camp is in words.
**The finding worth carrying forward:** the hard part was never the camp. "Home" had **seven
independent answers** — `annex_rect`, `gate_a`, `gate_b`, `player_start` read separately by
`director`, `raiders`, `jobs`, `needs`, `recruits`, `fortify` and `boot` across 24 call sites — and
`map.anchors` is never serialised, so a runtime-written anchor would have vanished on load in
silence. `sim/home.gd` is the one answer now, and every resolver's last rung is what its caller did
before, so a world with no camp is byte-identical (the HOME lane).
**Two things that needed no work at all, and the reasons are load-bearing:** the director never
targeted the colony (it places at the map edge and the field pulls), so "hordes come to a camp that
is used" was already true; and a camp needs **no emitter of its own**, because what emits at a camp
is the fire, the light and the people. An all-zero emitter would have been a twelfth dead socket.
**No `SAVE_VERSION` bump** — still 29 — because a new component round-trips through the generic
`component_store.save()`. The night band follows home into its cell on a region, and is a no-op on a
district. Task 8's other halves (labour cost, camp-local pressure inputs, evolving a camp, assigning
survivors to one) are still in docs/23's what's left; the four numbers this slice picked are item
`0f` below and the outpost question is `0e`.

**2026-09-10 — the flip, and a prediction that was wrong** (`godot:m2:region` at ten lanes; the
chain is still **57**). The main area is reachable: `--region=region.main_area` boots Ashgrove,
**400 × 400**, four districts, 240 wanderers, three colonists.
**Read this before trusting anything else written about the director on a region.** This file and
docs/23 both claimed `_edges_by_side` returns a near-empty pool on a region and that "every night
arrives empty with no error". **That was wrong** — `_border` walls one tile and the band is three,
so a region yields 4,157 legal tiles against a district's 1,984. The real fault was the *distance*:
215–432 m from the colony gate against a district's 122–182, which is diluted pressure rather than
none. `SimTileMap.spawn_edges` fixes it (the annex cell's own band; 120–185 m after), and the gate
measures distance rather than count because the count was never the problem.
**The budget picked the district size.** At `cellTiles` 256 the region ran at **0.94× real time** —
under its own 20 Hz clock — so pillar 6 refused it. The owner shrank the cells to 192: **1.48×**
against a shipped district's 4.15×. The cost is real and named: **a region's districts are no longer
the 256 m the balance bands were measured on.**
**The region is opt-in and the default is still one district.** 1.48× is above the clock with much
less room than a district, and this container has measured the same district at 55 and 83 ticks/s on
different days. Making a region the default is item `0b` below.

**2026-09-10 — the region assembler** (`npm run godot:m2:region` / `M2_REGION_OK`, eight lanes; the
`godot:m2` chain is **57** now). The owner answered both of item `0c`'s questions — a 2×2 of full
256 m districts nearly touching, and the colony established anywhere — so that item is off this
list and the region is built. **Ashgrove is 528 × 528**: town centre, forest edge, industrial park
and residential suburb, generated in 3.9 s, carrying 307 buildings, 521 loot sites and all five loot
tables in one map. The colony is ranked across every cell rather than assigned to a district, and on
the canonical seed it picks the town centre unprompted.
**The one thing to read before touching the assembler:** it ranks candidate lots against a
**layout-only** scratch region, not the finished one. The first version ranked on the assembled map
and switching the dressing off moved the colony 45 tiles — `_rubble` heaves patches up through a
street and `_street_frontage` counts paved neighbours. That is docs/30's existing district rule ("a
colony sited off the trees would move when the trees were switched off") broken at region scale, and
the DETERMINE lane was proved red against the old ranking before it was trusted. **The rule
generalises: anything deciding where something is built reads the layout, and only the layout.**
docs/24's district spacing is amended there, carrying the measurement as its reason.
**The game still boots a single district** — only the gate boots a region. The flip is the next
piece, and it is the one that moves the harness; the two silent failures waiting in it (the
director's spawn band, and population scaling off the map side) are in docs/23's what's left.

**2026-09-09 — wading, and telling the two waters apart** (`godot:check:water` at ten lanes with
WADE; `SAVE_VERSION` 27 → 28; chain still **55**). The owner's three asks, which are one mechanic
seen from three sides. **Wading already worked** — a ford is an ordinary Floor on the water surface,
so it has walked at ×0.45 speed and ×1.8 noise since the surface existed, and the lane says so
rather than claiming credit for it. **It soaks you now, at once**: rain has `wetAfterTicks` to soak
through and a body in a river does not, and everything after that is the rain slice's own —
`wetUntilTick`, the same drying clock, the same fire, the same `_colder` step. Measured at
`a_little_cold` on the ford against `comfortable` on dry ground one tile away, and proved red with
the soak disabled before it was trusted. **And the two waters read apart**: the channel darkened
(0.253 → 0.209 against the ford's 0.361) *and* every deep tile draws a lit **shoreline** on each
side whose neighbour is not also deep — the rim is what does the work, because a value gap alone
reads as "darker water" while an edge reads as a bank. `shore_zoom.png` under
`.hermes/plans/2026-09-09_water/` is the 32 px-a-tile view for the owner to judge.
**Worth knowing:** only the shallow half can wet you, and that is geometry rather than a check —
deep water is solid, so no body is ever standing on it. And the channel is bounded from *below* as
well as above: the background is `#15141f` at value 0.122, so a darker channel reads as a hole in
the map rather than as water.

**2026-09-09 — the river, the lake and the yard** (`godot:check:water` at nine lanes,
`godot:m2:jobs` grew RIVER, `godot:check:loot` grew a rebuilt negative; chain still **55**). Three
more pieces of the owner's default town. **The river and the lake are generated**: `worldgen.water`
is layout pass 3.5, from an optional `water` block, and `forest_edge` declares both — 1,541 deep and
1,124 bank tiles at 256. Bridges are derived from the street manifest and cost no draw; fords cost
one each. **The river drinks**: `place_river_sources` stands water sources on the banks and the
whole shipped thirst loop was already correct, so a body on the bank fills there and one at the well
still fills at the well (8 sources in the forest, 1 in the suburb). **The factory**: `industrial`
was the last unauthored slot in docs/12's five-location enum and `district.industrial_park` fills
it, with three new `industrial`-tagged templates where no template carried the tag at all.
**What is worth knowing before you touch the generator.** Three bugs were caught by gates and
guards rather than by review, and each is in docs/30: `water-crossable` first asked whether the
whole map was one component and blamed the water for the woods (it is asked as a *difference* now);
one forced midpoint ford was not enough and the generator burned all 31 candidate lots re-siting a
colony against a fault that was not the colony's; and **the grass discs were the one dressing writer
that never consulted `protected`** — they write a *surface* onto a Floor tile, and a ford is a
Floor, so they turfed 49 of them. `_protected_tiles` now carries the water **and one ring around
it**, the ring because a stand of trees grew across the dry ground leading to a ford. Also:
authoring `industrial` disarmed two of `check_loot.gd`'s own negatives, which both used it as their
example of an unwritten table — a negative that leans on a slot being empty stops being one the day
somebody fills it.

**2026-09-09 — water, and the one cool ground** (one new gate, `npm run godot:check:water` /
`WATER_OK`, six lanes; the `godot:m2` chain is **55** now; `sprites:check` still 151 keys but
`ground_atlas.png` regrew a row). The owner opened a default town — city, forest, factory, river and
lake, with procgen beyond it as the end goal — and most of it turned out to exist already: the city
and the forest are shipped district types and the generator has rolled districts from a seed since
the worldgen arc. **Water existed nowhere**, and it is what landed: one tile and one surface, per
docs/24's two-arrays rule. Deep water is `Tile.Water` carrying exactly `Tile.Window`'s pair (solid,
transparent — a river stops a body and not a sightline), a ford is an ordinary Floor on the same
surface, and the ford is the slowest and loudest ground in the game (×0.45, ×1.8). Nothing in the
pathfinder or the shadowcast changed, and the gate proves that rather than claiming it.
**Two things were caught by guards rather than by review, and both are worth knowing before you add
a surface:** `Appearance.ground_row_for` returns a surface int *as* an atlas row and
`GroundRow.Sidewalk` was already 5, so `Surface.Water = 5` made every river draw as pavement with
the whole chain green — the paints are 6 and 7 now and `check_water`'s ROWS lane was proved red
against the old order; and the first water tint was refused at import by
`tools/sprites/palette.py`'s `guard_against_ground`, because a new ground is bounded from above by
the darkest pawn ramp (nobody had written that down). The blue is an **amendment to the owner's own
2026-09-03 Dungeon Settlers decision** and is a named pin rather than a hole: `COOL_SURFACES` judges
the exempted ground with the cool pin, and the saturation cap is not exempted. Nothing generates
water yet, so the harness's map is untouched — which is the slice's balance claim and is asserted.
docs/30's water entry has the calls; docs/23's record the measurements; docs/24 now has a `### Water`
section and water in its ground table. The pieces it named rather than built — the generated river,
the river that drinks, the factory, the region assembler and the flip — are docs/23's "the main area"
group, in the order they land.

**2026-09-09 — art we did not generate** (one new gate, `npm run godot:check:authored` /
`AUTHORED_OK`, four lanes; the `godot:m2` chain is **54** now; `sprites:check` unchanged at 151
generated keys). The owner opened commissioned sprites — *"we might look into getting proper
sprites"* — and decided the shape of them in three answers (docs/30, "Art we did not generate"):
**commissioned to this project's spec** rather than bought as a pack, **equipment layering a
requirement** of any art we take, and the pawn arc paused while the diagram is not. What landed
is the second tier and the gate that holds it honest. `assets/sprites/authored.json` declares a
key's canvas, kind and reader, and is read by **two** things — `tools/sprites/build.py` so
`--check` does not try to regenerate it, and `appearance.gd`'s `canvas_of` so the renderer knows
its shape — which makes it the first shape table here that is one copy rather than two. The
gate's SPEC lane is the one that matters: it measures the **eight generated rigs** against the
same bounds a commissioned one is held to, so the brief in `assets/sprites/README.md` is a spec
somebody has already hit. READS says so and skips while the tier is empty, which it is until the
first sprite is delivered. Proved both ways before it was trusted — a declared key with no file,
a file at the wrong canvas, a key in both tiers, a non-conforming rig, a lying `reads`, and a
conforming rig with a real reader. What it named rather than built is in docs/23: the guide sheet
an artist draws on, and the three gates the first commissioned body has to widen
(`check_topdown`'s FLIP, `check_worn`'s `_rig_keys()` count of exactly eight, and its FITS
envelope).

**2026-09-09 — the character fixture round, and the four answers it produced** (no gate, no game
code, no game art: `.hermes/plans/2026-09-09_character-fixtures/` only, and `sprites:check` is
still `SPRITES_OK` at 151 keys). The owner opened a character-model overhaul and a replacement
for the paperdoll, and answered *"show examples of art first then I will decide"* — so the round
is four sets of candidate art, every candidate a **transform of the shipped generator** rather
than hand art beside it, with a `comparison.md` that describes each and recommends none. Its one
assertion is `verify.py`: all eight rigs at rest come back **byte for byte identical** to the
shipped PNGs, with the true negative in the same script, which is what makes the animation
answers affordable. The four answers — the rig read harder with banded shading, a four-frame
walk with the weight shift, **four directions**, and the exploded body chart — are docs/30's
"The character overhaul", and the pieces they open are docs/23's "Art & renderer — the character
overhaul", in the order they land. Two of them supersede named pieces: the two-frame walk (drawn,
looked at, close to invisible at six pixels of leg) and the pixel body chart that landed the day
before. Nothing is built yet; the fixture generators are a prototype the first slice promotes.

**2026-09-08 — the inventory and UI overhaul, seven slices in one run** (one new gate,
`npm run godot:check:inventory` / `INVENTORY_OK`, plus new lanes in `check_hud`,
`check_appearance`, `check_loot` and `godot:m2:save`; `SAVE_VERSION` 26 → 27). The owner opened
it from four mockups and decided it in six answers — docs/30's "The inventory sheet". The Tab
screen is a **fixed sheet** (body and twelve slots left, a column of bag grids in the fixed order
pockets, belt, vest, back, an inspect pane of words right, the belt and pockets as a quick strip
along the bottom, a drawn word menu on right-click); `ui/container_window.gd` and the pinnable,
draggable, position-remembering bag windows are **deleted**, and the strip is what buys back what
pinning bought. Every one of the 89 item bases gained a `description` sentence. A **world
container is now a grid** — the same component a pack carries, rolled once on the first open —
so E opens a cupboard into a **small transfer window** beside your pockets without leaving the
district. `item.appearance.sprite` gained its first reader (the milestone's twelfth dead socket)
with a drawn glyph per item class behind it. A short digit-free **tag** reads beside the player's
own body and nowhere else. And the paperdoll is a **pixel body chart** — thirty generated masks,
tinted by state — after the owner judged the drawn figure "too alien". Numbers, gates and the
five screenshot-found defects are in
[docs/23's record](docs/23-roadmap.md#the-record-by-system); screenshots for the owner are under
`.hermes/plans/2026-09-08_inventory-sheet/`. **Two existing gates went red on the refactors and
were made stronger rather than looser**: `check_respond`'s dead-socket needle and
`check_weather`'s ground-item socket both followed a call one file down.

**2026-09-08 — the squat pawn, and the overhaul decided** (no new gate; `TOPDOWN_OK`'s FLIP
lane re-pinned to a 32×40 canvas, `WORN_LOOK_OK`'s skeleton copy moved, GREY re-measured at
+0.018). The owner opened a graphics overhaul toward Zero Sievert from a design brief and
decided it in seven answers — docs/30's "Overcast or torchlight": a hybrid on the Dungeon
Settlers spine, overcast day and warm night, the remembered map dimmed for unseen ground, the
wall's south face hanging a tile into the entity sort, a squat one-tile pawn with a big head,
weapons as the read, and Zero Sievert, Dungeon Settlers, Project Zomboid and RimWorld as the
references. The pawn piece landed the same session: every rig re-authored on a shorter published
skeleton (rows moved, columns did not), all thirty-one overlays refit by re-rendering, four
numbers moved by hand for the things that hang below the hand. docs/23's what's left has the
new group — the grade, the remembered map, the wall face, grime, the two-frame walk — in the
order they land, and the record has the numbers. **Waiting on the owner:** what "when
selecting the character, sprite art will appear" means (item 0a below). Screenshots under
`.hermes/plans/2026-09-08_squat-pawn/`.

**2026-09-08 — fog, the seventh weather kind** (`npm run godot:m2:fog`, `M2_FOG_OK`, eight
lanes; `godot:check:weather` at eight with the VEIL lane; `SAVE_VERSION` 26), the first piece of
"what the weather left behind", picked and shaped by the owner in four answers this session:
autumn-heavy with a spring weight so a ten-day run can draw it, shrunken sight plus a pale veil,
sight both ways and scent muffled and nothing else, `sightMul` 0.25 for two to eight hours. One
content number closes every observer's range and a zombie's sight reach by the same factor
(3.8 m → 0.95 m, under the contact radius: in a fog the dead hunt by nose and ear), the district
edge closes in because the sim stops seeing it, and the veil only says what closed it. docs/30's
"The sky has kinds" has the calls and the one trap the seam is shaped around (the night wash's
alpha is a sight ratio, so the multiplier lives outside the sight rule); docs/23's record has the
measurements, the byte-identical FAST balance lines and why they prove nothing about fog. Three
screenshots under `.hermes/plans/2026-09-08_fog-look/` are for the owner to judge — the one
thing to look at: under fog the *unseen* background goes pale grey rather than staying dark,
which is what a full-screen veil does and may not be what was pictured.

**2026-09-07 — the playable state, thirteen slices in one run** (PR #115, on top of the roadmap
audit): the owner's twelve decisions of 2026-09-06, each a named piece in docs/23 and each
landed with its gate — Guard as the night post, the crisis dead-end and fires that burn down,
colonists scavenging near home, density by district size, eyes and senses as content, two
grace nights then the table (shipped at seven, item 5 below), the dead writing to the field,
torso damage that slows and staggers, doors, pressing, re-arm and withdrawal, the cold, the
heat and sepsis killing, and the screen speaking of the colony with a click that selects. The
record of each, with what the FAST tier did, is in
[docs/23's record](docs/23-roadmap.md#the-record-by-system); the first-cut numbers nobody was
asked about are item 6 below. `SAVE_VERSION` went 21 → 25 across the run; the chain is still
51 gates.

**2026-09-06 — the four weather slices on the spine**, built in parallel worktrees and merged the
same day: **the storm** (`npm run godot:m2:storm`, `M2_STORM_OK`, five lanes — noise masked on
the field's own decay at a half-life ×0.4, lightning striking an open outdoor tile every ten
minutes to two hours as a noise of 60 nobody made plus a `weather.lightning` event, outdoor
work refused at `_pick` and a running outdoor job dropped, Guard exempt); **the cold snap and
snow** (`godot:m2:cold`, `M2_COLD_OK`, eight lanes — the pantry at half rate, a cold-snap night
freezing on its first tick, the dead at ×0.7 / ×0.9 measured on the ground they cover, settled
snow at ×0.8 on the living, cover laying and melting); **the heat wave** (`godot:m2:heat`,
`M2_HEAT_OK`, seven lanes — a hot clock that deepens `a_little_hot` to `very_hot` and no
further on its own, heatstroke only in body armour after two exposures, thirst ×1.5, food
rotting ×2, corpses smelling ×2, the job dropped at the deep band, three digit-free
sentences); and **the look** (`godot:check:weather` at seven lanes — one pure sky function a
kind, snow flakes on their own key, a storm at a higher floor, snow cover lerping every outdoor
ground fill so cover 0 is byte-identical, a lightning strike as one drained-event wash frame;
two screenshots under `.hermes/plans/2026-09-06_weather-look/` for the owner to judge). The
`godot:m2` chain is **51 gates** now. docs/30's "The sky has kinds" carries one bullet a slice;
docs/23's record one bullet a slice with every measured number.

**2026-09-06 — the sky has kinds** (`npm run godot:m2:weather` rewritten, `M2_WEATHER_OK`,
thirteen lanes; `SAVE_VERSION` 21), the spine of the owner's weather session, opened the same
day rain landed and decided in four answers — storm, cold snap with snow, heat wave and a
shifting wind; kinds as content; a five-day-season calendar; snow that lies as well as falls
(ADR 0016). Six kinds under `content/weather/`, the globals in a new `climate` type, a wind
that drifts daily and leans the scent field, the temperature shift that makes the hot bands
reachable, the living slowed through a global modifier and the dead through their one speed
read, and a hot body that seeks a roof rather than the fire. It also closed a defect: NPC
survivors never read `move_speed`, so the limp, encumbrance and blood loss had only ever slowed
the player. docs/30's "The sky has kinds" has the calls; docs/23's record the measurements, the
balance before and after, and the fast tier's blind spot (it cannot see a heat wave). The
storm's noise and lightning, the cold snap's pantry, the heat wave's clock and thirst, and the
look (snow flakes, ground cover, a lightning flash) are the named pieces in what's left.

**2026-09-06 — rain is sim state** (`npm run godot:m2:weather`, `M2_WEATHER_OK`, eight lanes;
`SAVE_VERSION` 20, now 21 under the weather spine), the fourth slice of the survival session and the one the owner opened
against ADR 0002 (ADR 0015 records the reversal): it rains in spans drawn on the sim's own
stream — dry twelve to thirty-six hours, wet two to six, first cuts — a body outdoors in it is
wet and reads one band colder until a roof, an hour, or a fire dries it, scent washes off the
field while it falls, the streak layer draws only while it rains, and the HUD says so in a
sentence. Nothing else from docs/16 came with it. docs/30's "Rain as sim state" has the calls;
docs/23's record the measurements and the balance lines.

**2026-09-06 — well water is untreated** (`npm run godot:m2:needs` WATER; `godot:m2:jobs` WELL
amended), the third slice of the survival session and docs/04's oldest unbuilt sentence: the
well fills `item.water.bottle.untreated`, which drinks like water and rolls the food-poisoning
bout (0.15 a bottle, a first cut for the owner); a lit campfire boils a bottle clean — E at the
fire, or an NPC who walks there, lights it and boils before drinking, and drinks it raw only
below soft thirst with no fire anywhere. docs/30's entry has the four calls; docs/23's record
has the measured rate and the balance lines.

**2026-09-06 — the pantry and the cook's claim** (`npm run godot:m2:needs` PANTRY, `godot:m2:jobs`
COOK CLAIM), the second slice of the survival session, two named defects: `spoilage_rate` has a
reader — every perishable ages at the best living colonist's rate, the owner's call, so the
`surv.cook` web node is finally felt — and Cook claims its raw item and re-checks at completion,
so two cooks make one meal and a vanished raw makes none. `repair_cost` stays dead and the debt
entry says why. Balance lines before and after are in docs/23's record.

**2026-09-06 — the splint, and the limp** (`npm run godot:m2:splint`, `M2_SPLINT_OK`, nine
lanes), the first slice of the owner's survival-systems session. A splint kit on the medical
table immobilises a fracture through the existing `close` rung — the closer is now the wound
kind's own (`WOUND_KINDS.closeKind`), matched to the kit exactly, which is also the fix for a
fracture never having been closable at all — and a leg fracture that knits *without* a splint
leaves a permanent limp: a `lasting` component, `move_speed ×0.90` a leg, a word on the body
screen. The owner's rule (unsplinted → limp, deterministic) and number (ten percent) are in
docs/30's entry; the four FAST balance lines before and after are in docs/23's record.

**2026-09-06 — the gear catalogue** (`npm run godot:m2:gear`'s CATALOGUE lane, `godot:m2:needs`'s
DRINK and STIMULANT lanes, `godot:m2:vehicles`' REFUEL lane, `godot:m2:jobs`' WELL lane, and
`WORN_LOOK_OK` judging fifteen new pictures), at the owner's direction: thirty-one new item
bases — five melee weapons, a pump shotgun and a hunting rifle with their rounds, five pieces of
clothing, four packs and pouches, a fuel bottle and an empty can, an oil lantern and two bench
consumables, four foods and four drinks — every one in a loot table, every drawn-slot base with a
generated overlay. Three shipped dead sockets went live with it: a `drink` block makes the
energy drink a stimulant with a real crash (the word is "wired"), a `fuel` block and the E
ladder let a can at the nose refuel a car, and `empties` makes a drunk bottle leave the empty the
Water job has hunted since it landed. The jerry can, the crash, the shotgun and the rifle are
first cuts for the owner (item 0 below). Balance before and after is in docs/23's record; every
band held.

**2026-09-05 — the light vehicles** (the LIGHT lane of `npm run godot:m2:vehicles`, and
`WRECKS_OK` judging the new pictures), the owner's fourth goal of the driving session: a
bicycle, an electric bike, an electric scooter, a kick scooter and a skateboard park in the
suburb beside the cars and ride the same way — E from the side gets on, WASD rides, E gets off
once stopped — at speeds between a walk and a car (bicycle 6.5 just outruns a sprint's 6.3, a
skateboard's 4.5 does not), each with its own small dash (a handlebar computer or a board's
strip, words and needles, no digit). What they trade for it is the cab: a rider is on the
shambler's menu and a grab or a crash throws them off. A flat e-bike is pedalled at its
unpowered speed; a bicycle has no tank at all. Every call was a first cut taken without an
owner (docs/30's Driving entry, "Light vehicles"), and the halves it named rather than built are
docs/23's "What the light vehicles left behind".

**2026-09-05 — the parked cars drive** (`npm run godot:m2:vehicles`, `M2_VEHICLES_OK`), at the
owner's direction and ahead of the Milestone 3B schedule it sat behind. Every `map.vehicles`
record is an entity at boot; **E** beside a car gets in (after the loot and the people beside
it), E at the nose looks under the hood (fuel and condition, in words, never a number),
WASD drives it on four headings with a makeshift dashboard under the car (a speedo needle
with no numbers, E-to-F fuel, P N D, brake and engine lamps, one line of prose), E again gets
out once it has stopped; a crash at speed costs condition and a dry tank or a wreck will not
run; the engine is loud on the attention field and a body at the
wheel is off the shambler's menu; a driven car survives a save (`SAVE_VERSION` 19 since the
light vehicles, below). The record
is docs/23's, the design calls are docs/30's "Driving" entry, and the halves it named rather
than built — running things over, the door under siege, the driver's hands, NPC drivers, fuel —
are in what's left under "What driving left behind". **Several of those calls were taken as
first cuts because the session had no owner to ask**; they are listed below for the owner.

**2026-09-01 — the bigger colony and the `GRABS_ENABLED` flip**, described in the state section
above; the flag record in docs/23 has the decision, the before/after table, and the gate work.

**2026-09-01 — antibiotics became reachable** (`npm run godot:check:respond`, `RESPOND_OK`), the
surface the flip needed beside it: a clickable word under the condition readout on the Tab body
screen, offered by the sim (`SimTreatment.response_view`) only when a course is in the pack *and*
something is showing that a course might answer — never on `transmitted`, never on `is_septic`, so
a latent bite is offered nothing and a fever from either cause offers the same word. Antibiotics
only; the other four verbs and why each is still unsurfaced are in docs/23's defect list. It also
closed a free-course hole: `use_antibiotics`' zombie-infection path used to record a course with
no item spent, which made antibiotics free for the bitten and priced only for the septic.

**2026-08-25 — a review sweep**: a read of the whole tree looking for defects rather than for the
next feature.
Thirteen fixes, seven gate assertions, each with its true negative, and everything else the sweep found
written down instead of fixed. The record is in
[docs/23 → the record, by system → Kernel & review sweep](docs/23-roadmap.md#the-record-by-system);
what it deliberately did **not** fix is in
[defects found by the review sweep](docs/23-roadmap.md#whats-left-in-milestone-2), named one at a
time so the next session can take one.

Three of the fixes are worth knowing about before you touch anything:

| What was wrong | Gate |
|---|---|
| **Two worlds shared one attention field.** `SimBoot` kept the world its noise/scent handlers wrote into in a `static var`, so the *last* world to call `attach_kernel` received every other world's emissions. Boot A then B, publish 500 at (8,8) on A: A's field read 0.0000, B's read 500.0000. Every gate that boots a positive and a negative world was reading the wrong field for anything about noise or scent | `godot:m2:district`, ISOLATION |
| **`put_down` never put anyone down.** docs/06 response #5 published its two events and returned `ok`; nothing reaps on `entity.killed`, so the survivor walked away from their own mercy kill. The assertion that stood there watched the events go out and stopped | `godot:m2:treatment`, PUT-DOWN |
| **A despawn left its components and modifiers behind**, in every save — a `has_method("removeScope")` guard against a method called `remove_scope`, and five call sites reaching past `world.despawn` to the entity store | `godot:m2:save`, DESPAWN-CLEAN |

The rest: sprint can no longer aim (`CAN_AIM` had been read by nothing), `item.unequip` undresses
one survivor instead of the whole colony, the hidden **M** sheet stopped serialising the entire
world four times a second (measured at 12.58 ms a call), bleeding reads as English in the third
person, and **four gates that could not fail now can** — including one whose armour assertion was
satisfied by a `-1` error sentinel and one that proved a modifier had applied by comparing it
against its own base value.

A read of all thirty-odd check scripts is where those four came from, and it found several more
that are named but not fixed. If you are about to trust a gate, ask it the question that found
them: **what change would turn this red?**

**The sweep's own lesson, if you read nothing else:** three of the thirteen were a guard, a
subscription, or a constant that existed, looked right, and was **read by nothing**. That is the
same dead-socket pattern CLAUDE.md has been recording all milestone; the list is now nine long.
When you add a mechanism, add the assertion that something reaches it.

## What is waiting on the owner, not on code

**Should a wash require soap?** docs/04 says washing needs water *and* soap; only the water half is
enforced. The camping slice shipped `hygiene` as banked charges a dirtying spends, and deliberately
did not make soap mandatory: that is a rebalance of a need every colonist has rather than an
addition, and a district that rolled no soap would have no way back from `filthy`, which
`sepsis_mul` reads. Deciding it means deciding what a soapless colony is supposed to do.

**Is the arc's difficulty increase the difficulty you want?** The re-baseline measured it precisely
(see docs/23): the content is innocent, the armour-acquisition rule costs two of four seeds their
colonists. The ten-day playtest is the right judge, and the lever is one static.

These are design calls. They have been measured, written up, and deliberately **not** decided.
(Sepsis came off this list on 2026-09-06 — **lethal untreated**, one of the owner's twelve
playable-state decisions in docs/30's "The playable state" entry; it lands as the lethality piece
in docs/23's playable-state group. Three long-standing items came off on 2026-09-01, decided by
the owner: colony shape
— a bigger colony, three at boot — and the `GRABS_ENABLED` flip, both landed together and closed
in docs/23's flag record; and the top-down art style, picked 2026-09-01 as **B, the rotating
player** and **superseded 2026-09-03 by the Dungeon Settlers look** — upright face-on pawns
that flip, nobody rotates, a warm dark-fantasy palette, walls with a lit cap and a south face,
roofs cut out where seen. docs/30's "The Dungeon Settlers look" entry records the twelve
decisions and what each earlier clause becomes; the work it forces is docs/23's Dungeon
Settlers arc, whose plan is `.hermes/plans/2026-09-03_dungeon-settlers-arc.md`. **Which of its
slices have landed is docs/23's record, not this file** -- a list here went stale twice in two
days, which is the same drift that took the equivalent list out of `CLAUDE.md` in `e2b94e7`.)

0f. **The camp's four first cuts** (2026-09-10). The seam slice landed home as relocatable
   (`godot:m2:camp`, nine lanes) and took four calls without asking, each one line if re-decided.
   **The key**: camp is **C**, shift+C to strike, rather than a rung on E's context ladder — the
   argument is that moving home by accident is worse than one more key, but E-with-a-confirm is a
   real alternative. **The clock**: establishing costs fortify's ordinary 40-tick channel, because
   the labour cost is the deferred slice; it is currently cheaper than boarding a window and louder
   than one, which is half of the commitment Task 8 asks for. **The footprint**: a camp's rect is
   radius 1 — the tile and everything touching it — which is what the director's quiet floor reads
   as "how loud is it at home"; the 32 m keep-off is `GATE_EXCLUSION`'s and is unchanged.
   **Abandonment reverts home to the annex** rather than to the previous camp, which is the simplest
   reading of "camps are temporary" and not the only one.

0e. **Whether a camp should be assignable, and whether an outpost should draw raiders**
   (2026-09-10). Two questions the seam slice deliberately did not answer. A camp is home or it is
   an outpost, and an outpost currently does nothing at all: nothing is assigned to it, and
   `raiders._objective` walks to *home*, so a colony with three outposts is raided exactly like a
   colony with none. Both are design calls, both are named in docs/23's what's left, and neither is
   a defect — but an outpost that does nothing is the shape of a dead socket, so it should not sit
   unanswered for long.

0b. **Whether a region becomes the default boot** (2026-09-10). Everything is built and gated;
   `--region=region.main_area` reaches it and the default is still a single district. The reason it
   is not flipped is measured: the region runs at **1.48× real time** against a district's **4.15×**,
   which is above the 20 Hz clock but with far less room, and this container has measured the same
   district at 55 and 83 ticks/s on different days — so the margin is real and not comfortable, and
   rendering sits on top of it. Two dials if it needs one: `cellTiles` in
   `content/regions/main_area.json` (already 256 → 192 once, for exactly this reason), and how much
   of a region's population a region boots. **Worth playing before deciding**, which is the one
   thing a table cannot answer.

0c. **The water numbers, and the two the owner has not been asked** (2026-09-09). Every water
   constant was a first cut taken in an autonomous session, each one line: the ford's ×0.45 speed
   and ×1.8 noise, the tint `#424f5c` (bounded from above by the pawn-ramp contrast guard, so it
   cannot simply be brightened), and `WATER_DEEP_SHADE` 0.30. docs/30's water entry records them.
   **Two are genuine questions rather than numbers.** First, the saturation cap: "genuinely blue"
   and `_sat_ok`'s 0.30 pull against each other, and only the *warmth* pin was exempted — the
   shipped tint sits at 0.283, just inside, so a brighter blue needs a second exemption the owner
   has not made. Second, and larger: **the ground is still a player-only mechanic.** `SimJobs._walk`
   resolves `move_speed` but NPC and zombie locomotion do not read `SimSurface`, so today a river
   slows the player and nobody else — half a mechanic in exactly the way noise-only ground was
   before the worldgen arc. Widening it moves NPC pathing balance and is its own measured slice
   (it is in the debt list); until then a ford is a decision only the player makes.

0b. **The idle breath** (2026-09-09). One pixel of pelvis at a quarter of the walk's rate,
   drawn in the fixture round and deliberately left out of the four answers the owner gave that
   day. Small, independent of every other piece, and named in docs/23's character-overhaul group
   rather than decided there.

0a. **The picture on select** (2026-09-08). The owner's answer on the pawn — *"when selecting
   the character, sprite art will appear. However, weapons, clothing, gear will be shown"* —
   names a picture the colony panel does not have. A portrait was refused with the Dungeon
   Settlers HUD on 2026-09-03; a larger picture of the selected pawn, kitted, in the panel is
   not a portrait. Which was meant is the call; docs/30's "Overcast or torchlight" and docs/23's
   what's left name it and do not decide it.

0. **The driving slice's first-cut calls**, each recorded in docs/30's "Driving" entry and each
   a small change if re-decided (the key is decided: the owner chose **E** on 2026-09-05 and it
   landed as a rung of fortify's ladder): four headings with the opposite
   key turning the car round; a moving car passing through bodies (nothing run over); a body at
   the wheel unreachable by shamblers; and the engine's numbers (sedan 24 under way, 4 idling,
   against a sprint's 6) — never measured against the director, because the 64-tile harness
   parks no car. **Added by the second goal of the same day:** the fuel numbers (a sedan's
   40 L, 12 000 m of range, 90 minutes of idle), the crash curve (55 at full speed on the
   square of the speed, a wreck after four runs at a wall), one in ten cars spawning wrecked,
   and the reading of "define the interact key" as *name E once* rather than *add a key for
   the hood* — docs/30's "Fuel and hitpoints" and "One interact key" clauses. **And by the
   third:** a gauge may show a machine's state and never a body's, which is how a dashboard
   with two needles sits beside a HUD that forbids gauges — docs/30's "The dashboard". **And by
   the fourth, the light vehicles:** the five classes and their numbers (bicycle 6.5 / e-bike
   7.5 / e-scooter 6.0 / skateboard 4.5 / kick scooter 4.0, noise 3..5 against a sprint's 6);
   the trade being exposure rather than a speed nerf (a rider is on the shambler's menu, a grab
   or a crash unseats them, the body takes no injury from it); a flat battery riding on at
   `unpowered`; legs costing no stamina; the dash layouts (handlebar, board) and their words;
   parking in the cars' pass on 4-wide spans only, weighted sedan 10 / van 3 / truck 1 /
   bicycle 4 / e-bike 2 / e-scooter 2 / kick scooter 1 / skateboard 1; the car shells as the
   bike paint; and `SAVE_VERSION` 19 — docs/30's "Light vehicles" clause, each a content edit
   or a line. **And by the gear catalogue (2026-09-06):** the pump shotgun (30 damage, 15 m, noise
   220) and the hunting rifle (34, 60 m, 200) against a pistol's 18 / 25 m / 180; the energy
   drink's loan (thirst 15, rest 20 now, 25 back three in-game hours later, chaining
   compounding rather than resetting); a jerry can as ten litres poured whole with the rest
   spilt; and the fuel bottle on a residential shelf until an industrial table exists — docs/30's
   "The gear catalogue", each a content number. **And by the survival session (2026-09-06):**
   the limp at ten percent a leg (owner-picked from three offers), well water's 0.15 illness
   chance a bottle and an instant boil at a lit fire, and NPCs drinking it raw only below soft
   thirst — docs/30's splint and well-water entries; and the rain's numbers (dry 12–36 h, wet
   2–6 h, the scent half-life halved, 200 / 12000 / 2400 ticks to wet, to dry, to dry by a fire) —
   docs/30's "Rain as sim state" and `content/weather/rain.json`, every one a content number.
   **And by the weather spine (2026-09-06):** every duration range and seasonal weight in the
   six kind entries (storm 1–3 h, cold snap and heat wave 1–3 days, snow 4–10 h; rain spring 5
   / summer 2 / autumn 3 / winter 1, and so on), the multipliers (storm scent ×0.35 and noise
   ×0.4, cold shamblers ×0.7 and snow ×0.9, settled snow ×0.8 on the living at half cover,
   heat thirst ×1.5 and spoilage and corpse scent ×2), the wind's daily drift at 0.6 (a
   storm's ×2 and a 240 lightning were the first cuts, and the integration re-measured both:
   docs/23's Weather record), five days a season from spring, and the hot seek walking to a
   roof — docs/30's
   "The sky has kinds", `content/weather/*.json` and `content/climate/temperate.json`. **And by
   its four slices:** body armour for the heat as torso coverage ≥ 0.4 (the jacket and the
   scrap vest, not the wrap) and heatstroke at two exposures in it; snow cover melting under a
   cold snap too (only `snow.json` lays any); lightning's sixteen tries at an open tile; the
   look's `SNOW_COVER_MAX` 0.55, the snow and lightning palette keys, and the flake's fall,
   lean and length — docs/30's per-slice bullets, and two screenshots to judge. **And by fog
   (2026-09-08):** `sightMul` 0.25, two to eight hours, weights spring 2 / summer 1 / autumn 4 /
   winter 1, scent half-life ×0.8, and the veil's alpha (`#c8cdd64d`) — `content/weather/fog.json`
   and one palette key, every one a content number; the season and the veil were the owner's
   calls this session, the numbers were offered and accepted as first cuts.
1. **Whether the wind should be free.** The weather spine's first cut drew each day's wind
   direction anywhere, and the balance harness's four-seed survival floor read that as a coin
   toss: every re-measurement wiped a different seed (docs/23's Weather record has the table).
   Shipped: a prevailing wind — the attention field's calibrated lean, which every district
   siting was measured under — that wanders within `windDriftDeg` (45°) of it, content in
   `climate/temperate.json`; 180° is the free wind back. docs/16's "a base that was safe
   becomes a base that's upwind of the whole district" and a per-seed survival floor pull
   against each other, and which gives is a design call, not a number.
2. **Whether a roof covers a known building's unseen walls too.** The wall-and-roof slice roofs
   the unseen *indoor* tiles of a building the survivor can see part of, as approved, so the
   unseen perimeter walls stay black and the roof reads as a mass inside a black ring
   (`slice5-front-64.png` in the plan's shots). Roofing every unseen tile of the footprint is
   one condition in `RoofLook.roof_tiles` and leaks nothing the footprint does not already;
   the look is arbitrated by screenshot, so it is the owner's.
3. **Whether the one-handed weapons need their own silhouettes at 32 px.** The worn slice found
   that the bat, machete, pipe and kitchen knife share a fist, an angle and a value range: they
   are distinguishable side by side and would not be at a glance mid-fight. The cheapest fix
   gives each primary weapon its own lean rather than sharing the bat's, which re-authors the
   shipped bat -- so it is recorded rather than taken in passing. The service pistol is the
   weakest single key for the same reason of size. Sharper since the second gear catalogue
   (2026-09-09): the weapon hand now holds fifteen melee bases and seven ranged, each new one
   given its own lean and length so none of them added to the pile, but the shipped four are
   still the shipped four and the two rifles are now a pair as well.
4. **Whether a forest stand should ever be as dense as the generator can make it.** In the
   densest one measured -- 44 Tree tiles in a 9x9 -- the player is very nearly invisible: trees
   are Opaque, so sight collapses to a few tiles, and the fade rule cannot help much because
   several trunks overlap the body at once (`slice9-stand-64.png`). That is the forest's
   character rather than a defect in the fade, but the density is content: the knobs are the
   terrain block's `standsMax`, `treesMax` and `treeSpread`.
5. **The two playable-state flips against the compressed tier's survival floor.** Two of the
   owner's own 2026-09-06 decisions are built, gated at both values and shipped at the old
   one: sight as a stimulus (`SimShambler.SIGHT_ENABLED`, decision 3 — since flipped, see the
   end of this item) and the strain table from night 3 (`SimDirector.GRACE_NIGHTS`, decision
   4, ships 7 rather than 2).
   Measured on the FAST tier with each on, a seed or two in four **wiped**, and
   `survivors_end >= 1` is the assertion CLAUDE.md records as considered and rejected for
   relaxing. The eyes and director records in docs/23 carry the diagnostics: a shambler that
   can see re-takes the colonist it just released, and three early packets finish a colony
   that cannot kill a shambler with a knife. The trade is between the owner's pacing and a
   floor measured on a 64-tile district sixteen times the shipped density with the player's
   body unattended. The options, each one line: (a) flip both after the torso slice lands and
   re-measure — the plan's order, and the record's recommendation; (b) let the compressed
   floor be "three seeds of four" and flip now; (c) run the FULL tier at 256 overnight
   (`BALANCE_FULL=1 BALANCE_TILES=256`) before deciding, ~8 hours at the measured rate.
   **Re-measured after the torso slice landed** (docs/23's Lethality record): with both flips
   on, three seeds hold at 3 of 3 and seed 20260805 still wipes (186 grabs, the crowd that saw
   the annex on night one never left), and the harness's over-cap invariant trips on two seeds
   (live 35 / 34 against a cap of 32 for a few hundred ticks — something places past the
   clamp once the table opens on night 3, to be found before the flip). **Sight alone,
   re-measured after the torso slice, holds the floor**: survivors 1 / 2 / 3 / 3 of 3, every
   band green — so sight ships on (decision 3 executed under the standing assertion, the
   commit after the torso slice's) and this item is now the table alone: flip `GRACE_NIGHTS`
   to 2 once the over-cap placement is found and seed 20260805 is re-read with sight already
   on.
6. **The playable-state slices' first-cut calls**, 2026-09-07, each inside one of the owner's
   twelve decisions, each recorded in docs/30's entry for its slice, and each a one-constant
   change if re-decided. The eyes: a zombie's sight reach is `range × sqrt(lightSense)` scaled
   by the light *at the target* (a lit survivor is seen from the dark), the shadowcast recast
   only after two tiles of movement, and a screamer's own groan raises its own noise threshold
   so it does not chase itself. The field: every zombie's base scent is **1**, chosen off
   docs/03's migration drift (6–7 m of centre-of-mass drift in an hour against 19 m at the
   plan's 8, which dominated the field). The doors: a door swings shut sixty ticks after its
   tile empties, breaks at stage four, and zombies never open one; the press: pressure
   `n × (1 + 0.5 × (n − 1))` against stage costs of 40 (board), 160 (door) and 90 (scrap).
   The band: raiders withdraw after 6,000 ticks at the objective with nobody in reach, or at
   once when below half their size. The lethality doses: frostbite at two exposures and death
   at three in the cold, heatstroke at three and death at four in the heat and only in armour,
   sepsis lethal at the third untreated dusk. The screen: a chronicle line stays two game
   hours, three at most; a click selects and never orders; a thin ring marks the selection.
   None of these was asked about, because the session was autonomous; each is the kind of
   number the ten-day playtest is for.

## How a session runs

The loop is [CLAUDE.md's workflow section](CLAUDE.md#the-workflow), in eight steps: orient in the
plan docs; pick **one named piece** from what's left (owner decisions are not pickable); design
inside the seams; build the gate with the thing — true positive, true negative, and the
dead-socket assertion that something *reads* the mechanism; measure any balance claim with a
throwaway driver; verify (`npm run godot:m2`, plus `npm test` for content edits); move the piece
from what's-left to the record in the same commit; and leave every claim naming the gate that
proves it. `CLAUDE.md`'s **Traps** section is the other thing to read before starting — every entry
in it cost someone a session, and three entries were added by the sweep above.

## Picking up

```bash
bash scripts/setup-web-session.sh   # fresh container has no engine
npm run godot:m2                    # ~12 min, the gate that matters
npm run check:routing               # the routing table in AGENTS.md, and every gate reachable
npm run godot:run                   # play it (DISPLAY=:1 on a headless VM)
```

Then read [What's left in Milestone 2](docs/23-roadmap.md#whats-left-in-milestone-2) — every
remaining piece, named so the name alone says what the work is, grouped into: decisions waiting on
the owner, world generation (closed), people, medicine, gear, attention, art, UI, proof, debt,
weather, the defects the review sweep left open, and what is parked for Milestone 3A. Pick a piece,
land it with its gate, delete it from that list and write its record into
[the record, by system](docs/23-roadmap.md#the-record-by-system) in the same commit.
