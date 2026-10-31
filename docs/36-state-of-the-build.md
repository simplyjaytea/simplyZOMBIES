# State of the build

The state facts and the dead-socket list, in full. CLAUDE.md keeps the summary. docs/23 is the
authority on what is built and what remains. Moved out of CLAUDE.md on 2026-10-19.

## Where the work is, in full

Milestone 2, the vertical slice — one district, a handful of survivors, enough of every system to
find out whether the loop is fun. Its exit criterion is ten in-game days, permanent loss,
succession, and still wanting another run.

The boot colony is **three by the owner's 2026-09-01 decision** — the player, Mara, and Ellis
(`survivor.unique.ellis`), and further roster growth *at boot* stays there. The pause that
decision put on new NPCs and roster growth was **lifted by the owner on 2026-09-14**
([docs/30](30-decisions.md), "The pause lifted"): generated people, raiders and zombies are
the thirteen-piece population arc landed on 2026-09-15/16. Generated people, individual raiders,
dormant zombies and settler camps are recorded with their gates in docs/23. The three-person
boot colony remains fixed; later recruitment grows it. The **captives arc** (docs/30's "One web,
and the captives", the same
day; docs/23's what's-left names its slices) is named work under that lift rather than the lone
exception to a pause its own entry was written against — a held raider who can be recruited or
put to work, with a recruited captive mid-game growth either way. The design record
captures decisions, not shipped behavior: nothing counts as done until code and a focused Godot
check prove it.

[docs/23](23-roadmap.md) is the authority on what is intended **and**, in its milestone status
sections, on what is built and what remains (the old per-item checkbox `HANDOFF.md` was retired
into it and its itemised history lives in git; there is no `HANDOFF.md` any more (retired 2026-10-19), and the owner list lives under
[Waiting on the owner](33-owner-decisions.md#waiting-on-the-owner), which is not a status ledger). Its
[what's left](23-roadmap.md#whats-left-in-milestone-2) section names every
remaining Milestone 2 piece — small, modular, named so the name alone says the work — and its
[record, by system](23-roadmap.md#the-record-by-system) holds the evidence for what landed;
a landing moves its piece from the first to the second in the same commit.
[docs/30](30-decisions.md) is the authority on why something that looks arbitrary is shaped
that way. Read 30 before changing something that looks arbitrary. This file does not restate their
contents — the one copy of the status lives in docs/23, because every duplicated copy of it has
drifted. Three things about the current state matter enough to repeat anyway:

- **The survival loop is built end to end, gated, and ON.** Grabs, bites, located bleeding
  wounds, pressure and bandaging, rescue, recovery, infection — `SimShambler.GRABS_ENABLED`
  ships `true` since the owner's 2026-09-01 decision (a bigger colony, then the flip; docs/23's
  flag record is the seed-by-seed history and closes with it). The flag stays a gate-drivable
  static: any gate lane that pins it must **restore the previous value**, because one gate
  process shares it across every world it boots. Relaxing `survivors_end >= 1` has been
  considered and rejected — post-flip it is the standing assertion that the shipped default
  survives its own contact loop. Sepsis lethality was decided 2026-09-06 (lethal untreated,
  docs/30's "The playable state") and landed 2026-09-07 with the cold and the heat — three
  dusks septic and the body dies; docs/23's lethality record in the playable-state group.
- **The presentation is flat top-down, not isometric** — an independent track that touched nothing
  under `godot/sim/`. `docs/00-vision.md` carries the reversal, docs/30 what it made structural,
  and the art entries in what's left the ordered next steps. The style is **the Dungeon Settlers
  read, decided by the owner 2026-09-03**: a warm dark-fantasy palette, walls drawn with a lit cap
  and a south face, roofs cut out where the sim sees, three-quarter props and vehicles, 32 px a
  tile at 2×. **Its face-on pawn and its "nobody rotates" clause were reversed by the owner on
  2026-09-11** — docs/30's "The decoupled paperdoll" — and that proposed rotating rig was
  subsequently superseded by the adopted outpost pack. Since 2026-09-26 ("The bodies turn and
  walk", the outpost pack) humans draw the pack's four-direction body; the 2026-10-02 zombie
  pose set replaces its shared shambler with seven animated families and settled corpses.
  Only the screamer and the bloater are still the face-on pawn described below. The 2026-09-03 entry itself
  superseded the 2026-09-01 style-B pick (the rotating player, the overcast mood) and records the
  twelve decisions and what each earlier clause becomes; the 2026-09-11 entry does the same for
  it, which is the third time the bodies have been re-decided — read docs/30 in date order rather
  than trusting any one entry alone. **Decided lands slice by slice, and [docs/23's
  record](23-roadmap.md#the-record-by-system) is the one copy of which ones have.** This file
  deliberately does not list them: that list has now drifted three times, each time a slice landed
  without its copy here being updated, which is the same reason the milestone status lives in one
  place. What the style *is* **as shipped today**: the table is warm; humans use the outpost body and
  zombies use their content-selected families (32×40, the heavy 40×48), four views and an
  eight-frame walk stepped on the render clock by ground covered (docs/23's A7 record), the
  actions and stances the sim publishes played on that clock (the A8 record), never
  mirrored, while the screamer and the bloater are squat face-on pawns that
  flip through a negative-width rect; walls draw their
  material's cap or south face and roofs cover what the sim cannot see; the darker ground draws a
  boundary once onto the lighter tile; a tree is a 32×96 picture standing in the entity sort; a
  parked car is a manifest record the layout wrote, drawn as one three-quarter picture per class,
  variant and axis in that same sort; and equipment draws on the body in one order -- the
  pack's four wearables per view and supported held weapons; the old face-on clothing overlays
  are retired. Where a piece has not landed yet, its code comments say so on purpose. The reference's
  HUD — portraits, bars, numbers, name plates — is explicitly not adopted.
- **The dead-socket pattern.** This milestone has turned up **eleven** pieces of code that were
  complete, correct, often gated, and read by nothing: `crawlFactor`, the `Staggered` state,
  `sepsis.checked`, `injury.sustained`, `item.painkillers.blister`, `SimVisibility` for everybody
  but the player, rule 4's variance floor behind an `if size == 0` that could never be true,
  `SimDirector.snapshot_of`, `SimStances.CAN_AIM` (found by the review sweep — it had said "a
  sprint cannot aim" since the ladder landed while `SimRanged` let a sprinting survivor fire),
  the `move_speed` stat itself for every NPC (found by the weather spine: `SimJobs._walk` never
  resolved it, so the limp, encumbrance and blood loss had only ever slowed the player), and
  `item.appearance.sprite` — in the schema since the appearance pipeline landed, read by nothing,
  so every dropped item was the same ten-pixel square until the 2026-09-08 glyph slice gave it a
  reader.
  **A gate asserting that a helper returns the right number does not assert that anything reads
  it** — and the textual assertion that says something *does* read it has to be able to find the
  reader after a refactor. The inventory overhaul turned two such gates red without breaking
  anything: `check_respond` looked for a call in `_draw` that had moved into `_draw_body`, and
  `check_weather` looked for the ground-item colour in `_draw_entities` after it moved into
  `Appearance.item_look`. Both were fixed by following the call a link further, never by dropping
  the needle. **A third instance, 2026-09-12, a different shape:** `check_m2_comfort.gd` asserted
  its key was in `check_m2_gear.gd`'s `READ_KEYS` by searching for the *tail* of that list,
  `"noise", "comfort"]` — deliberately, because the bare word appears in that file's prose too and a
  needle a comment can satisfy cannot fail. The reasoning was right and the needle was still wrong:
  the books slice appended `"teaches"` an hour later and the lane went red against a gear gate that
  was correct. Isolate the line first (`begins_with("const READ_KEYS")`) and ask for membership
  inside it — no comment can satisfy that and no later key can displace it; `check_m2_teach.gd` is
  the precedent. When you add a mechanism, add the assertion that something reaches it —
  `check_m2_attach.gd`'s "is this findable in any loot table" is the cheapest example, and
  `npm run check:routing` applies the same rule to the gates themselves (a check script no npm
  script reaches is red, which retired `check_r6_bench.gd`). The sweep
  left four sockets named but unfixed; one closed 2026-09-16 — `SimStances.eye_of` now has a
  reader, `SimVisibility.refresh` writing `observer["eye"]` from it every tick
  (`godot:m2:sight`'s EYE and EYE-READER lanes; the record's Attention leftovers entry) — and
  three remain (`sim/spatial/hash.gd` entire, `SimThreat.threat_within`, and
  `SimDirector.snapshot_of` — found, replaced by `world.gd`, and still defined); they are in
  [docs/23's defect list](23-roadmap.md#whats-left-in-milestone-2).

Keep all effects sim-owned and command-driven; player-facing state remains prose/diegetic and must
not weaken the condition-view health-bar ban. The full balance grid and human ten-day playtest are
still required Milestone 2 proof, deferred rather than cancelled.


## Night eyes on restore, 2026-10-24

A save from before the survivors' night-eyes floor (`SimLight.NIGHT_EYES_FLOOR_M`, `sim/vision/light.gd`) has no
`night_eyes` on a person's observer. `SimWorld.restore` sets it on every observer that is neither a
zombie (`zombieType`, `shambler`) nor a raider, as `SimSurvivors.give_eyes` would have, so an old save's survivors
see the floor and no save version was bumped. Gated by `godot:m2:sight` FLOOR (LOAD lane).
