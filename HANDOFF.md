# HANDOFF

**This is not the old handoff ledger.** The per-item checkbox file of the same name was retired
into [docs/23](docs/23-roadmap.md) after drifting four times, most recently by ~34 shipped-but-
unticked items. Do not put checkboxes back in here.

What this file is: a short note for whoever picks the project up next. **Where the code is** lives
in [where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands), which is the authority
and is updated in the same commit as the work it describes. **Why something is shaped the way it
is** lives in [docs/30](docs/30-decisions.md). **What must not be broken** lives in `CLAUDE.md`.

---

## State, as of 2026-08-19

`main` is green: `npm run godot:m2` chains **30 gates**, and CI's `check` job runs those plus the
frozen TypeScript oracle (45 files / 594 tests), typecheck, lint and format. The last merged change
is PR #91.

The game is playable — `npm run godot:run`, needs a display. It boots on day 1 in daylight.

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

## What is waiting on the owner, not on code

These are design calls. They have been measured, written up, and deliberately **not** decided:

1. **`SimShambler.GRABS_ENABLED` stays `false`.** The whole injury loop is built and gated behind
   it. Six reasons have been recorded and five answered; the sixth is a genuine balance choice
   between three named candidates — give a break-away somewhere to go, let a press bank its
   progress, or cut contact rarity. The seed-by-seed measurement is in docs/23. **Do not pick one
   unilaterally.** Nothing in the last session touched this flag.
2. **Colony shape.** Two survivors spread across a 256 m district is part of why the hard seeds
   end `0/2`. Whether the slice colony should be bigger or tighter is a design decision, not a
   tuning one.
3. **Whether sepsis should be lethal.** It is currently debilitating and permanent-until-treated,
   deliberately not a death path, because lethality balance is the thing standing between
   `GRABS_ENABLED` and its flip.
4. **The top-down art flavour.** The presentation track is unblocked and waiting on a pick;
   docs/23's Art bullet has the ordered next steps.
5. **The equipment-slot taxonomy.** The owner has sketched a layered, realistic slot set (head:
   hat/mask/eyewear/ear; torso: undershirt/shirt/jacket/vest-rig/backpack; arms: gloves; legs:
   underwear/pants/socks/boots). Expanding `SimInventory.EQUIP_SLOTS` touches the sim, the content
   schema (both validators — the Ajv one recurses), armour coverage, and loot; most of those slots
   currently have no items to fill them, which is the dead-socket pattern this milestone keeps
   finding. Needs an owner decision on which slots ship with items now and which wait for the
   systems (temperature, hygiene) that give them meaning.
6. **The Tarkov-style paperdoll.** Slots arranged around the figure with injuries on the same
   body — the inventory window rework landed the chrome for it, but the layout is a design pass
   the owner wants to direct. States stay words and tints; the health-bar ban is not negotiable.

## The pattern worth knowing before you start

This milestone has turned up **eight dead sockets** — code that was complete, correct, often
gated, and read by nothing: `crawlFactor`, the `Staggered` state, `sepsis.checked`,
`injury.sustained`, `item.painkillers.blister`, `SimVisibility` answering for the player alone,
docs/17 rule 4's variance floor sitting behind an `if size == 0` that could never be true, and
`SimDirector.snapshot_of`.

**A gate asserting that a helper returns the right number does not assert that anything reads it.**
When you add a mechanism, add the assertion that something reaches it. `check_m2_attach.gd`'s "is
this findable in any loot table" is the cheapest example of that check.

`CLAUDE.md`'s **Traps** section is the other thing to read first. Every entry in it cost someone a
session.

## Picking up

```bash
bash scripts/setup-web-session.sh   # fresh container has no engine
npm run godot:m2                    # ~6 min, the gate that matters
npm run godot:run                   # play it (DISPLAY=:1 on a headless VM)
```

Then read [docs/23's Milestone 2 status](docs/23-roadmap.md#where-milestone-2-stands) for the open
list. Candidates named there and not yet started: the five remaining modification consumables
(Solvent, Whetstone, Gun Oil, Machinist's Gauge, Salvage Rights — the doc says each is one content
entry plus one operation), weight affecting footstep noise, the fuller survivor generator and trait
conflict rules, supply quality tiers and the wider resource taxonomy, and the UI screens.
