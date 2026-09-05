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

## State, as of 2026-09-05 (the driving slice)

Green, and verified this session rather than quoted: `npm run godot:m2` chains **46 gates**
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

**2026-09-05 — the parked cars drive** (`npm run godot:m2:vehicles`, `M2_VEHICLES_OK`), at the
owner's direction and ahead of the Milestone 3B schedule it sat behind. Every `map.vehicles`
record is an entity at boot; **Q** beside a car gets in, WASD drives it on four headings, Q
again gets out once it has stopped; the engine is loud on the attention field and a body at the
wheel is off the shambler's menu; a driven car survives a save (`SAVE_VERSION` 18). The record
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

These are design calls. They have been measured, written up, and deliberately **not** decided.
(Three long-standing items came off this list on 2026-09-01, decided by the owner: colony shape
— a bigger colony, three at boot — and the `GRABS_ENABLED` flip, both landed together and closed
in docs/23's flag record; and the top-down art style, picked 2026-09-01 as **B, the rotating
player** and **superseded 2026-09-03 by the Dungeon Settlers look** — upright face-on pawns
that flip, nobody rotates, a warm dark-fantasy palette, walls with a lit cap and a south face,
roofs cut out where seen. docs/30's "The Dungeon Settlers look" entry records the twelve
decisions and what each earlier clause becomes; the work it forces is docs/23's Dungeon
Settlers arc, whose plan is `.hermes/plans/2026-09-03_dungeon-settlers-arc.md`. **Which of its
slices have landed is docs/23's record, not this file** -- a list here went stale twice in two
days, which is the same drift that took the equivalent list out of `CLAUDE.md` in `e2b94e7`.)

0. **The driving slice's first-cut calls**, each recorded in docs/30's "Driving" entry and each
   a small change if re-decided: **Q** as the key rather than E; four headings with the opposite
   key turning the car round; a moving car passing through bodies (nothing run over); a body at
   the wheel unreachable by shamblers; and the engine's numbers (sedan 24 under way, 4 idling,
   against a sprint's 6) — never measured against the director, because the 64-tile harness
   parks no car.
1. **Whether sepsis should be lethal.** It is currently debilitating and permanent-until-treated,
   deliberately not a death path. With grabs live it is reachable in ordinary play, which makes
   this decision live too; making it lethal is a balance decision that needs a measurement
   attached. The cure is no longer out of reach: the sweep's "`infection.respond` has no
   producer" is closed for antibiotics — they are a clickable word on the body screen now
   (`godot:check:respond`) — so the decision is about lethality alone rather than about lethality
   with no answer available. The other four infection verbs still have no surface, for the
   reasons docs/23's defect list gives.
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
   weakest single key for the same reason of size.
4. **Whether a forest stand should ever be as dense as the generator can make it.** In the
   densest one measured -- 44 Tree tiles in a 9x9 -- the player is very nearly invisible: trees
   are Opaque, so sight collapses to a few tiles, and the fade rule cannot help much because
   several trunks overlap the body at once (`slice9-stand-64.png`). That is the forest's
   character rather than a defect in the fade, but the density is content: the knobs are the
   terrain block's `standsMax`, `treesMax` and `treeSpread`.

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
npm run godot:m2                    # ~7 min, the gate that matters
npm run godot:run                   # play it (DISPLAY=:1 on a headless VM)
```

Then read [What's left in Milestone 2](docs/23-roadmap.md#whats-left-in-milestone-2) — every
remaining piece, named so the name alone says what the work is, grouped into: decisions waiting on
the owner, content-only entries, people, medicine, gear, attention, art, UI, proof, debt, the
defects the review sweep left open, and what is parked for Milestone 3A. Pick a piece, land it with
its gate, delete it from that list and write its record into
[the record, by system](docs/23-roadmap.md#the-record-by-system) in the same commit.
