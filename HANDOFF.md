# HANDOFF

**This is not the old handoff ledger.** The per-item checkbox file of the same name was retired
into [docs/23](docs/23-roadmap.md) after drifting four times, most recently by ~34 shipped-but-
unticked items. Do not put checkboxes back in here.

What this file is: a short note for whoever picks the project up next. **Where the code is** lives
in [where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands), which is the authority
and is updated in the same commit as the work it describes. **Why something is shaped the way it
is** lives in [docs/30](docs/30-decisions.md). **What must not be broken** lives in `CLAUDE.md`.

---

## State, as of 2026-08-20

`main` is green: `npm run godot:m2` chains **32 gates**, and CI's `check` job runs those plus the
frozen TypeScript oracle (45 files / 594 tests), typecheck, lint and format. The last merged code
change is PR #95 (the basic-combat slice); since then the changes are docs only — the plan was
renamed and split ([what's left](docs/23-roadmap.md#whats-left-in-milestone-2) /
[the record](docs/23-roadmap.md#the-record-by-system)) and the workflow written into `CLAUDE.md`,
with the duplicated status copies in `CLAUDE.md` and `AGENTS.md` trimmed to pointers. No code,
content, or gates touched.

The game is playable — `npm run godot:run`, needs a display. It boots on day 1 in daylight — and
as of the basic-combat slice, **zombies can hurt you**: a shambler in arm's reach claws on a
three-second cadence, wounds bleed, and the treatment loop is live in ordinary play. Grabs — and
with them infection — remain behind `GRABS_ENABLED`, untouched.

## What landed in the last session

Six slices, working down docs/23's open list. Each names the gate that proves it:

| Slice | Gate | What it is |
|---|---|---|
| Sepsis, and injury kinds as a table | `godot:m2:wounds` | A wound can go septic and stops healing until antibiotics. `WOUND_KINDS` made fracture/sprain/burn/concussion rows instead of four `if kind == …` branches |
| Pain and exhaustion | `godot:m2:wounds` | docs/05's four continuous conditions are all four now. Pain is derived, never stored |
| Sightlines and memory | `godot:m2:sight` | A wall refuses a shot; a body that walked out of sight is remembered for two minutes with prose that degrades. **Every survivor has eyes now** — before this, only the player did |
| Attachments | `godot:m2:attach` | Five findable attachment items and a reader. An attachment declares what it multiplies, so nothing in the module names a suppressor |
| Grief | `godot:m2:needs` | A death costs every other survivor mood, more if they watched it |
| Varied nights | `godot:m2:director` | A night is *drawn* from a strain-weighted table rather than computed. docs/17 rule 4's floor and ceiling are mechanical |

After those, one presentation-only slice: the **inventory/UI rework** — moveable, pinnable bag
windows, the Esc settings sheet, the shared `ui/chrome.gd` skin, the paperdoll glimpse to the
bottom-left. No sim files were touched; docs/23's UI bullet has the detail and what remains.

Then the **basic-combat slice** (`godot:m2:swipe`, plus INSTINCT in `godot:m2:npc`): the swipe —
a part-scaled claw on a cadence, the one zombie damage path outside the grab flag — mouse aim and
click-to-attack, boot wanderers 12 → 20 with night packets `[0,3,6,9]` under a cap of 32, and the
three rules the diagnosis driver forced (a hit interrupts a first-aid channel and banks; self-aid
refuses to kneel with a claw in reach; break-off narrows to cornered defense instead of surrender,
and an unattended player defends on instinct). docs/23's "Basic combat is live" entry carries the
seed-by-seed measurement.

## What is waiting on the owner, not on code

These are design calls. They have been measured, written up, and deliberately **not** decided:

1. **Colony shape: a bigger colony, or one posted closer.** Two survivors spread across a 256 m
   district is why seed 404 still wipes with grabs forced on — rescue is built, gated and correct,
   and a second body is simply never within reach. A design decision about the slice, not a
   tuning one.
2. **Flip `SimShambler.GRABS_ENABLED`.** The whole injury loop is built and gated behind it. Every
   recorded reason has been answered (docs/23's flag record is the seed-by-seed history — the last
   two answers, escape routing and press banking, landed since this list was first written); what
   stands now is the colony-shape call above. **Do not flip it unilaterally.** Nothing in the last
   session touched this flag.
3. **Whether sepsis should be lethal.** It is currently debilitating and permanent-until-treated,
   deliberately not a death path, because lethality balance is the thing standing between
   `GRABS_ENABLED` and its flip.
4. **The top-down art flavour.** The presentation track is unblocked and waiting on a pick;
   docs/23's what's-left section has the three candidates and which picks force a sprite
   regeneration.

## How a session runs

The loop is [CLAUDE.md's workflow section](CLAUDE.md#the-workflow), in eight steps: orient in the
plan docs; pick **one named piece** from what's left (owner decisions are not pickable); design
inside the seams; build the gate with the thing — true positive, true negative, and the
dead-socket assertion that something *reads* the mechanism; measure any balance claim with a
throwaway driver; verify (`npm run godot:m2`, plus `npm test` for content edits); move the piece
from what's-left to the record in the same commit; and leave every claim naming the gate that
proves it. `CLAUDE.md`'s **Traps** section is the other thing to read before starting — every
entry in it cost someone a session.

## Picking up

```bash
bash scripts/setup-web-session.sh   # fresh container has no engine
npm run godot:m2                    # ~6 min, the gate that matters
npm run godot:run                   # play it (DISPLAY=:1 on a headless VM)
```

Then read [What's left in Milestone 2](docs/23-roadmap.md#whats-left-in-milestone-2) — every
remaining piece, named so the name alone says what the work is, grouped into: decisions waiting on
the owner, content-only entries, people, medicine, gear, attention, art, UI, proof, debt, and what
is parked for Milestone 3A. Pick a piece, land it with its gate, delete it from that list and write
its record into [the record, by system](docs/23-roadmap.md#the-record-by-system) in the same
commit.
