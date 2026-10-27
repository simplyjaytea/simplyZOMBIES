# Owner decisions

The list of what only the owner decides, moved out of CLAUDE.md on 2026-10-19 so that CLAUDE.md
stays short. Items keep the numbers they had in the retired `HANDOFF.md`, so a record that says
"HANDOFF item N" means item N here. Never pick one of these up unilaterally.

## Waiting on the owner

This is what only the owner decides. Never pick one of these up unilaterally. Items keep the
numbers they had in the retired `HANDOFF.md` (removed 2026-10-19, see docs/30), so a record that
says "HANDOFF item N" means item N here.

**Does hot reload swap content under a live world, or re-run the seed?** docs/30's "What hot reload
made structural" decides the second — four things capture content at spawn, equip and boot, so a
live swap leaves a world disagreeing with its own content — and `ContentReload.try_reload_world`
has done the first since R5. The 2026-09-13 reload fix kept the swap and added change detection,
by your call for that session; whether the swap stays, or the poll becomes validate-and-report
with a fresh boot to take an edit, is the decision. Nothing measured: it is a question of what
"reload" means, not of a number.

**Should a wash require soap?** docs/04 says washing needs water *and* soap; only the water half is
enforced. The camping slice shipped `hygiene` as banked charges a dirtying spends, and deliberately
did not make soap mandatory: that is a rebalance of a need every colonist has rather than an
addition, and a district that rolled no soap would have no way back from `filthy`, which
`sepsis_mul` reads. Deciding it means deciding what a soapless colony is supposed to do.

**Is the arc's difficulty increase the difficulty you want?** The re-baseline measured it precisely
(see docs/23): the content is innocent, the armour-acquisition rule costs two of four seeds their
colonists. The ten-day playtest is the right judge, and the lever is one static.

These are design calls. They have been measured, written up, and deliberately **not** decided.
(The water question, "where does a colony's water come from over ten days?", came off this list
on 2026-10-21: put to the owner on a decision card from the balance thread, with the player's verb
at the well as the default, and built as that default because cards do not gate work; docs/30's
"Water at the well, 2026-10-21". Its follow-up, "where does a colony drink without walking past the
gate?", came off on 2026-10-22: the owner tapped the card's second lever, **every colonist starts
with an empty bottle**, and it was built as picked (docs/30's "Every colonist starts with a bottle,
2026-10-22"). The well verb stays. More water in the loot, a well inside the wall and a rain
barrel at home stay unbuilt; docs/23's "Balance after the alpha" carries the ten-day numbers.
Sepsis came off this list on 2026-09-06 — **lethal untreated**, one of the owner's twelve
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
slices have landed is docs/23's record, not this section** -- a list here went stale twice in two
days, which is the same drift that took the equivalent list out of `CLAUDE.md` in `e2b94e7`.)

0f. **The camp's four first cuts** (2026-09-10). The seam slice landed home as relocatable
   (`godot:m2:camp`, nine lanes) and took four calls without asking, each one line if re-decided.
   **The key** — **decided 2026-09-16**: camp keeps **C**, shift+C to strike, and the stance
   ladder that had shared the letter (the audit found both arms firing on every press) moves onto
   Ctrl — docs/30's "The alpha shell" and docs/23's group of that name; the fix **landed** with
   the play gate on 2026-09-16 (`npm run godot:check:play`, the CAMP-KEY lane; docs/23's record).
   E-with-a-confirm was offered again and not taken. **The clock**: establishing costs fortify's
   ordinary 40-tick channel, because the labour cost is the deferred slice; it is currently
   cheaper than boarding a window and louder than one, which is half of the commitment Task 8
   asks for. **The footprint**: a camp's rect is
   radius 1 — the tile and everything touching it — which is what the director's quiet floor reads
   as "how loud is it at home"; the 32 m keep-off is `GATE_EXCLUSION`'s and is unchanged.
   **Abandonment reverts home to the annex** rather than to the previous camp, which is the simplest
   reading of "camps are temporary" and not the only one.

0e. **Whether a camp should be assignable, and whether an outpost should draw raiders**
   (2026-09-10). Two questions the seam slice deliberately did not answer. The later outpost
   slice extended where colonists will work, so an outpost is already useful. Assignment and
   raid targeting remain separate: nothing is assigned to a particular outpost, and
   `raiders._objective` walks to *home*, so a colony with three outposts is raided exactly like a
   colony with none. Both remaining design calls are named in docs/23's what's left; the owner
   chose work reach before danger.

0b. **Whether a region becomes the default boot** (2026-09-10). Everything is built and gated;
   `--region=region.main_area` reaches it and the default is still a single district. The reason it
   is not flipped is measured: the region runs at **1.48× real time** against a district's **4.15×**,
   which is above the 20 Hz clock but with far less room, and this container has measured the same
   district at 55 and 83 ticks/s on different days — so the margin is real and not comfortable, and
   rendering sits on top of it. Two dials if it needs one: `cellTiles` in
   `content/regions/main_area.json` (already 256 → 192 once, for exactly this reason), and how much
   of a region's population a region boots. **Worth playing before deciding**, which is the one
   thing a table cannot answer.

0c. **The remaining water mechanics** (first cuts 2026-09-09; colour decision superseded by
   the adopted pack). The ford's ×0.45 speed and ×1.8 noise remain first cuts. The old
   `#424f5c` tint/saturation question was settled by the owner's pack-grade decision: the ford
   now uses the pack's measured `#244e56`, proved by `godot:check:water`'s PACK lane. Do not
   reopen that colour question. **The ground is still a player-only mechanic.** `SimJobs._walk`
   resolves `move_speed` but NPC and zombie locomotion do not read `SimSurface`, so today a river
   slows the player and nobody else — half a mechanic in exactly the way noise-only ground was
   before the worldgen arc. Widening it moves NPC pathing balance and is its own measured slice
   (it is in the debt list); until then a ford is a decision only the player makes.

0b. **The idle breath** -- decided by the owner 2026-10-20: kept (docs/30's "The idle breath,
   kept").

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
   on. **The population arc found what it is, 2026-09-15, and did not act on it**, because the
   flip is yours: *nothing places past the clamp*. `SimDirector` refuses a spawn past
   `live_cap_for(world)` with reason `cap` and always has — but `infection.gd` and
   `SimRecruits._turn_with_kit` create a shambler from a body that dies infected with **no cap
   check at all**, so a colony that loses people to bites grows the horde past a budget the
   director is still honouring. Three separate slices hit it independently (the dormant, the
   camp and the settlers' day, each diagnosing it from the same signature: no identity, no
   allegiance, no corpse). It is in docs/23's defect list. Whether the turn should be clamped,
   or the cap should exclude turned bodies, is a balance call and therefore this item's.
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

7. **Does a raid that can actually connect get to wipe the colony?** The melee-reach fix
   (docs/23's defect list, "A melee raider band cannot reach a body that does not move", built
   2026-09-16, deliberately not landed, and its branch deleted 2026-10-22) is a correctness
   fix, not a difficulty dial — a raider closes to its own weapon's reach instead of standing a
   metre short of everything — but `npm run godot:m2:balance`'s FAST tier measured what it
   costs: seed 404's `mixed` arm was already down to its last colonist before the fix, and after
   it that colonist dies too (`survivors_end` 1→0, `run_over` true). That fails `_assert_bands`'s
   standing `survivors_end >= 1`, the assertion CLAUDE.md says was considered and rejected to
   relax after the `GRABS_ENABLED` flip, so the fix cannot land green as the tree stands. Three
   ways out, none taken unilaterally: the shipped default is meant to absorb a raid this lethal
   (permanent loss is Milestone 2's own exit criterion) and the assertion changes; the assertion
   was unknowingly grading the reach bug rather than the difficulty and the FAST seed set or its
   floor changes; or a raider first-cut number (band size, `HALT_METRES` itself, the withdraw
   rule) moves and is re-measured. The branch that carried the fix, its gate lanes and both
   measurement tables was deleted on 2026-10-22 as too far behind `main`; the record and the
   numbers stay in docs/23, and whichever of the three is picked, the fix is rebuilt from `main`
   and measured again.

8. **The four asks' first-cut numbers** (2026-09-17, docs/30's "What the owner asked for after
   the shell"). The owner picked the shape of each piece; the numbers inside were taken in the
   session and are each one line if re-decided. **Bare hands** (`SimCombat.BARE_HANDS`): reach
   1.0 m, weight 0.6, damage 4 (three to a shambler's head, fifteen to its torso), stagger 6,
   speed 1.3, recovery 0.8, stamina 0.7, the ordinary connect noise. **The afterimage** fades
   over the sim's `FRESH_TICKS` (ten seconds) and the mark over `RECENT_TICKS` (a minute) — those
   are the prose's own bands, deliberately not new constants; if the picture should linger
   longer, the band moves and the HUD's "a moment ago" moves with it. **The mutters**
   (`SimSpeech.MUTTER_EVERY` 400 ticks, `MUTTER_P` 0.15): a colonist in a need band speaks about
   once every two minutes; a line's horizon is `SAY_TICKS` 60 (three seconds), a scream 40.

9. **The needs-assets report's remaining questions**
   (2026-09-25, docs/23's record, "Art — the outpost pack's needs-assets report"). The report the
   outpost-pack arc named for held weapons, utilities, decals and the extra UI icons is done; none
   of its remaining scope should be assumed approved. **Two questions were subsequently
   settled:** container pictures by loot table and held weapons on the pack's bodies were
   approved and shipped (docs/30's "The whole outpost pack", docs/23's corresponding records).
   Containers show closed/searched states; the supplies-visible state remains deferred because
   it would reveal contents at a distance.
   **Do the pack's utilities become new mechanics, or stay decoration?** A generator, a rain
   collector, a stove distinct from the campfire, and a spike trap a raider or a zombie can
   trigger are none of them systems the sim has today; building the art is the smaller half of
   giving any of them a socket, and whether that arc is worth opening at all is the owner's call.
   **Do fences and gates become their own tile kind?** Slice 5's own prose counts all thirteen of
   the pack's wall states, but a fence and a gate have no counterpart in `SimTileMap.Tile` today —
   only a wall, a window and a door do — so landing those five states in full means new sim
   content, not only a renderer change; whether that is worth doing now, or the slice ships its
   other eight and leaves fence and gate for a later piece, is the owner's to pick.
   **Is a footprint decal a certainty the player should have?** A trail rendered where an actor
   walked, unseen by the player, is the kind of information clause 4 refuses; whether the whole
   decal group (`fx-blood-pool-*`, `fx-bullet-hole-*`, `fx-scorch-mark`, `fx-wood-chips`,
   `fx-shell-pile`, `fx-footprint`) is worth a persisted-mark sim fact at all, and whether
   `fx-footprint` specifically would be scoped to ground the player's own sightline has already
   swept, are both open.

10. **The UI's type sizes** (2026-09-25, docs/23's record, "UI — one typeface"). The ladder is
   20 / 25 / 30 / 50 in VT323; the HUD cards, action bar, shell rows and panel titles took 30,
   which keeps their old capital height but is not pixel-exact (strokes land 1 and 2 px wide) —
   crisp 25 reads smaller, 50 reads loud. One line per file if re-decided; the FONT lane holds
   whatever is picked to the ladder.

11. **The antibiotic loot weight** (2026-10-22, docs/23's "Balance after the alpha"). A course,
   `item.antibiotics.course`, drops only from `loot.medical`, at weight 10 of 274 (3.6% a roll).
   The other four tables carry no course. The expired and veterinary grades are the other drops
   (`godot/content/loot/tables.json`). The playtest's survivor took a course
   whenever the response panel offered one, and no course reached its pack on any of three seeds.
   So nothing in a ten-day run treats a bite. Keeping a course rare is the hardcore reading.
   Raising its weight, or adding it to more tables, is a one-line content change and moves the
   balance. Which one is the call.

12. **Whether a held colonist strikes its holder** (2026-10-22, the colonist-combat work). A
   grabbed body cannot swing: `SimMelee.try_begin_swing` refuses it, and `npc_combat.gd` takes a
   grabbed colonist out of play. The answer to a grab is somebody else's weapon, or breaking free.
   Letting a held colonist hit back is a new mechanic. It was offered on an optional card that was
   never answered. The default is **no**, and nothing is built.
13. **The stockpile's five cards (2026-10-24).** The stockpile and hauling feature shipped on
   defaults while its cards wait: (1) **how you mark it**, a dragged rectangle of tiles (built) or
   crates you build, each a container; (2) **where it may go**, any explored ground, indoors or
   out (built) or indoor floor only, the old annex rule; (3) **what you can take standing in it**,
   everything in view on the patch you stand in (built) or arm's reach only; (4) **how the Colony
   screen reads it**, a word per group and up to three names, never a count (built) or exact
   counts; (5) **whether the zone may be emptied**, one right-drag over the annex leaves no
   stockpile anywhere, and the sim stays honest about it -- no haul is offered, a meal lies at the
   fire (built, the review's follow-up `godot:m2:stockpile` EMPTY) -- or the last tile refuses to
   go. One tuning call to object to: `SimStockpile.MAX_TILES` is 1000, set by the coordinator
   (slice S2) from the measured cost of the patch walk, not from play. Each is one line if
   re-decided; the alternatives change readers (1), the camp's stash (2), the window's list (3),
   the information rule for the colony's own stores (4), or one refusal line (5). The plan is
   `planning/2026-10-24_stockpile-hauling.md` section 11 in the project files.


14. **The conversion realism table** (2026-10-26). Which caliber conversions a receiver family
    accepts: the coordinator writes the table into docs/10 as the firearms arc's kit piece lands,
    and the owner vetoes rows. Nothing is built off-table. docs/30's "The release plan and the
    content arcs".

15. **Fire as a sim fact: stage 1 or stage 4?** (2026-10-26). A burning tile, timber that catches,
    a body that carries flame. It unlocks the burner zombie, the arsonist raider and the timber
    wall that burns; it is also a new attention emitter (light) and a new way to die. The default
    is stage 4 (beta), so nothing in the alpha depends on it. Same entry.

16. **May raiders trade before factions exist?** (2026-10-26). The `trade` doctrine approaches
    unarmed and offers barter, which is one verb of Milestone 4's faction seam landed early. The
    default is no: the doctrine ships as probe, raid and siege, and trade waits. Same entry.

17. **Lost limb with its wounds closed, or lost limb and the bleed comes back?** (2026-10-26, the
    tourniquet piece, docs/30's "The tourniquet, and the limb it costs"). When a tie's window runs
    out the part is destroyed. The default is **its wounds are closed with it**, so a forgotten tie
    costs the limb and nothing more. The alternative is that the wounds stay open on the stump and
    the bleed resumes, which makes a forgotten tie a limb and then a death unless the survivor is
    dressed. One lane assertion in `godot:m2:treatment` TOURNIQUET COST changes with the answer.

18. **The tourniquet's loot weight** (2026-10-26, docs/30's "The tourniquet is findable"). It
    drops only from `loot.medical`, at weight 8 of 282, the sterile dressing's weight. The
    ten-seed balance table was not re-run for the line. Rarer keeps the limb-for-a-life choice
    sharp; commoner makes the tie a routine tool. Which table, and how often, is the call.


20. **Can the bloodhound see?** (2026-10-27, the bloodhound piece, docs/30's "The bloodhound,
    2026-10-27"). It follows the scent field and is deaf to noise. The default is that it sees only
    at contact range: its eyes are off, so it finds a body by walking into it, or by the scent it
    follows, and noise and light draw nothing. That is built with `sensory.light` 0. The
    alternatives are normal zombie sight, or fully blind (the same, with contact removed too). One
    value in `godot/content/zombies/bloodhound.json` changes the answer, and the SCENT-ONLY lane in
    `godot:m2:district` holds the default.

23. **What makes a weapon bespoke enough to name?** -- decided by the owner 2026-10-27: **three or
    more** of its slots holding a part it did not come with, on any weapon with slots, melee and
    firearms alike (docs/30's "A weapon you named, 2026-10-27"). The plan's first default was more
    than three; the piece found that only the steel pipe among the twenty melee frames has four
    slots, so the wooden bat, the arc's own example, could never be named, and the card was put
    again with that fact. A factory part and a part swapped back to it count nothing. One constant,
    `SimItems.BESPOKE_PARTS`, holds the answer, and `godot:check:inventory` NAME holds it.

24. **A typed name, or a name the game offers?** -- decided by the owner 2026-10-27: **typed**. A
    one-line field on the inspect pane, up to 24 characters, Enter keeps it, Escape leaves it as it
    was, and an empty name gives the plain name back (docs/30's "A weapon you named, 2026-10-27").
    `godot:check:play` NAME holds the field.

25. **May a name the player types carry a digit?** (2026-10-27, the named-weapon art review). A
    typed name rides the item-name clause of the digit ban, the same one that lets an authored
    round be `.308 Winchester Match`, so "Nailbat 2" is accepted, and when a colonist hauls it
    `SimOrders.hud_clause` reads "Hauling Nailbat 2 to the stockpile.": a digit the player typed,
    on a HUD line. Superscripts and fractions pass too; a name with no letter is still refused, and
    descriptions and every other HUD line stay under the full ban. Built default: **digits
    allowed**, since authored names already put digits on the same lines. The alternatives are
    letters only in a typed name (one change to `SimItems.name_char_allowed`), or a typed name kept
    off the HUD (the order line says the plain weapon name). `godot:check:inventory` NAME holds the
    default.
