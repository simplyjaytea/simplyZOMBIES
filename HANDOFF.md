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

## State, as of 2026-08-21

Green, and verified this session rather than quoted: `npm run godot:m2` chains **32 gates** and
exits 0, `npm test` is **45 files / 594 tests** passing, and `godot:validate`, `godot:test` and
`godot:smoke` are clean. CI's `check` job runs those plus typecheck, lint and format; its
`performance` job runs the two TypeScript benchmarks.

The game is playable — `npm run godot:run`, needs a display. It boots on day 1 in daylight, and a
shambler in arm's reach will claw you: wounds bleed, and pressure, bandaging and recovery are live
in ordinary play. Grabs — and with them bites, and with bites infection — remain behind
`SimShambler.GRABS_ENABLED`, untouched.

## What landed in the last session

A **review sweep**: a read of the whole tree looking for defects rather than for the next feature.
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

These are design calls. They have been measured, written up, and deliberately **not** decided:

1. **Colony shape: a bigger colony, or one posted closer.** Two survivors spread across a 256 m
   district is why seed 404 still wipes with grabs forced on — rescue is built, gated and correct,
   and a second body is simply never within reach. A design decision about the slice, not a
   tuning one.
2. **Flip `SimShambler.GRABS_ENABLED`.** The whole injury loop is built and gated behind it. Every
   recorded reason has been answered (docs/23's flag record is the seed-by-seed history); what
   stands now is the colony-shape call above. **Do not flip it unilaterally.**
3. **Whether sepsis should be lethal.** It is currently debilitating and permanent-until-treated,
   deliberately not a death path, because lethality balance is the thing standing between
   `GRABS_ENABLED` and its flip. Note the sweep found that sepsis's only cure is unreachable in
   play — `infection.respond` has no producer — which is a missing surface, not this decision.
4. **The top-down art flavour.** The presentation track is unblocked and waiting on a pick;
   docs/23's what's-left section has the three candidates and which picks force a sprite
   regeneration.

One thing about #1 changed shape without being decided: the **worldgen arc** (authorized
2026-08-25; scope decisions in
[docs/30](docs/30-decisions.md#what-the-worldgen-arc-decided), pieces in
[docs/23's what's-left](docs/23-roadmap.md#whats-left-in-milestone-2)) turns the civic annex into
an authored template the generator places, so "a bigger colony building" becomes a content edit
rather than a code change once it lands. The colony-shape call itself — and the `GRABS_ENABLED`
flip behind it — remains the owner's.

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
