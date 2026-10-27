# Playbook

For any agent joining this project cold: Claude, Codex, Cursor, or a person. `CLAUDE.md` holds
the rules of the repository. This file is about how the project around it runs: who decides
what, how a piece of work gets from a request onto `main`, where the shared material lives, and
what is open right now. It links rather than repeats. Where it states a fact about the build, it
names the file or gate that proves it. Where it says how the owner works, it records the owner's
standing instructions as of 2026-10-23.

Read `CLAUDE.md` first, top to bottom. Come back here before you pick up a piece.

## What the game is

A hardcore zombie survival colony sim. It takes RimWorld's colony management and work
priorities, Project Zomboid's unforgiving survival, and Zero Sievert's top-down pixel art. One
attention system (noise, scent, light) ties survival to the pressure the dead put on the colony:
the better you live, the harder they come. [docs/00](00-vision.md) is the vision and
[docs/01](01-hardcore-contract.md) is the hardcore contract.

Only the Godot build ships (`godot/`, Godot 4.7.1, typed GDScript). The TypeScript under `src/`
is a frozen oracle: CI keeps it green, and nothing new goes into it.

## Where it stands (2026-10-26)

- **Milestone 2, the vertical slice.** The exit criterion is ten in-game days, permanent loss,
  succession, and still wanting another run.
- **The alpha plan has landed.** All of its pieces, A0 to A24 (written 2026-10-19), are in
  [the record, by system](23-roadmap.md#the-record-by-system), each with its gate.
- **The alpha stopped at a balance wall on 2026-10-21.** The target was a colony alive on day 10
  on 2 of 3 seeds, and it was not met. The numbers, the traces and the next measurement are in
  docs/23's "Balance after the alpha" (under
  [what's left](23-roadmap.md#whats-left-in-milestone-2)). The next measurement is ten seeds and
  a median wipe day, on `main` and on each candidate. No lever is judged on three seeds again.
- **What is open** is [what's left](23-roadmap.md#whats-left-in-milestone-2): the UI overhaul's
  later slices, the balance follow-ups, the content arcs, and the named pieces under them. Which
  stage each belongs to is [the release plan](#the-release-plan) below.
- **For the current `main`,** run `git log origin/main -1` and look at its CI. This file carries
  no commit hash on purpose, because a hash written here is out of date after the next merge.

## Who decides what

- **The owner decides design.** That covers new mechanics, changed rules a player would notice,
  the look, and everything under
  [Waiting on the owner](33-owner-decisions.md#waiting-on-the-owner). Examples of new mechanics
  that went to the owner: quiet hours, noise-free repairs, a new water source, a held colonist
  striking back.
- **Agents decide engineering.** That includes tuning numbers that come out of a measurement. A
  call that is taken gets an entry in [docs/30](30-decisions.md).
- **Ask once, with a default, and keep going.** In a Claude project, a design question goes to
  the owner as a decision card with one recommended option. Elsewhere, put it in the pull
  request. The card never blocks work: build the default, say that you did, and change it if
  the owner picks something else.
- **Steps that cannot be undone wait for the owner's own words.** Merging under the owner's
  standing authorization (below) is the one exception.

## How the owner works

- Mostly autonomous. The owner wants results and decision cards, not progress reports or
  numbered lists of questions.
- The alpha target is "basic mechanics playable, not polished". Sound is not a priority.
- Art follows Zero Sievert, and the outpost pack sets the quality floor. Animation must be
  fluid. A one-sided bob or a loop that pops blocks a merge.
- A colony wiped at home in its first days is an alpha blocker. Ten-day playtest numbers are a
  measurement, not a merge gate.
- `README.md` is for players and `CLAUDE.md` is for agents.
- The owner closes idle threads, and threads whose pull requests have merged get resolved.

## How work flows

In a Claude project, a coordinator talks with the owner in the project chat and opens one thread
per piece of work. The rules below hold for any agent. [docs/34](34-agents-and-environment.md)
covers branch naming and worktrees for agents working outside a project.

1. **One piece, one branch, one pull request.** Branch off `main`, base the pull request on
   `main`, and push only your own branch. Fill in `.github/pull_request_template.md`. For stacked
   work, every pull request still bases on `main` and names the ones it follows. Stacked pull
   requests that conflict go through one integration pull request.
2. **Drive it green** by `.claude/skills/steward/SKILL.md`. Never skip, disable or loosen a gate.
3. **Claude merges, with a merge commit.** The owner authorized this. Re-check the head commit and
   CI right before you merge. Merge in dependency order. After a merge, tell the open threads the
   new `main`.
4. **Follow-ups start fresh.** A merged pull request is finished. New work goes on a fresh branch
   from `main` with a new pull request, never on top of merged history.
5. **Cloud sessions cannot delete remote branches.** The git proxy returns 403 for every ref but
   the session's own. Name the branches that should go, and the owner deletes them. Merged head
   branches come back after each merge unless "Automatically delete head branches" is on in the
   repository settings.
6. **Usage limits and restarts.** Containers restart, and sessions pause at usage limits. Push
   at a clean point before a long run. A thread revived after days can wake with stale context:
   brief it on the current `main` before it acts.

**Art and placement review.** Before an art or placement pull request merges, an independent
read-only reviewer checks the thread's exports. The reviewer is told the folder, the export time,
the previous report and the decisions so far, and verifies every claim against the pixels instead
of trusting the thread. Findings land as commits on the same pull request, and the review repeats
until it is clear. Round 3 is the last full round, and later passes only confirm fixes. Minor
findings in a clear round go into docs/23. Docs-only, gate-only and 1 to 2 px gate-verified
follow-ups need no review.

**Model routing.** The owner assigns models by role. Nothing pushed names a model (`CLAUDE.md`,
Pushing and pull requests), so the current model names live in the project's memory and the
owner's project-chat instruction, not here. The roles:

- The coordinator.
- Working threads, on the fast tier at high effort.
- Planning threads, anything that cannot be undone (merges, deletes), and all art, design and
  visual placement from the start, on the strongest tier at high effort.

## Verifying a change

[Verifying a change](../CLAUDE.md#verifying-a-change) is the policy, and
[docs/35](35-gates.md) has the commands and timings. In short:

- Run the gates for what you touched, locally. CI runs the full `npm run godot:m2` chain on four
  shards for every pull request.
- Run the full chain locally only for a change to a shared sim module or the save format.
- A new gate goes into the `godot:m2:chain` script and into `scripts/m2-shards.mjs` in the same
  commit. `npm run check:shards` fails otherwise.

## Where things are written down

| Question | Answer |
|---|---|
| What is open, and what landed with what evidence | [docs/23](23-roadmap.md) |
| Why something is shaped the way it is | [docs/30](30-decisions.md), oldest first |
| What only the owner decides | [docs/33](33-owner-decisions.md) |
| Containers, MCP servers, running the game, screenshots | [docs/34](34-agents-and-environment.md) |
| Every gate, its command, its timing, the CI shards | [docs/35](35-gates.md) |
| The state of the build, and the dead-socket list | [docs/36](36-state-of-the-build.md) |
| Traps that already cost someone a session | [docs/37](37-traps.md) |
| Performance targets and dated measurements | [docs/22](22-performance.md) |
| Where a system's code lives, and the gate that judges it | `CLAUDE.md`'s routing table |

## The release plan

Decided by the owner on 2026-10-26 ([docs/30](30-decisions.md#the-release-plan-and-the-content-arcs-2026-10-26)).
Five stages, each with the thing it has to prove. Pieces are named in docs/23's what's left;
this section says which stage each group belongs to, and nothing here is ticked. The art style
does not change between stages: flat top-down, 32 px a tile at 2x, the outpost pack as the
floor, the Dungeon Settlers mood (docs/30, 2026-09-03 and 2026-09-17). An isometric view was
asked about and declined on 2026-10-26, for the third time; depth where wanted is oblique
treatment inside this projection.

1. **Alpha closed: it loops.** Milestone 2's exit criterion in code, not balance. Everything in
   flight lands (colonist self-care, the buildables, the floodlight take-down, the Colony screen
   nits), then the sim pieces that need no owner call: round choice and the magazine's memory,
   the tourniquet, the purifier refill, the alarm and noisemaker priced, the plate that wears, the
   ranged affix readers, the repair economy. UI overhaul bullets three to five. The first
   worker-sized pieces of the content arcs below (the readers and the melee frames). Proof: the
   `godot:m2` chain green, `godot:check:play` covering every shell state.
2. **Alpha open: it survives.** The balance wall, judged only by ten seeds and a median wipe day.
   The named levers (a well inside the wall, the antibiotic weight, the six-survivor checkpoint,
   Guard and Scout, the night-3 table) and the speed pieces (sleep fast-forward, 3x and 10x, the
   tick to its 8 ms budget) so ten days fit an evening. The first zombie kinds and raider doctrine
   land here because they move the table. Release: the Windows build plus a Linux preset, and a
   seed you can type on the web build.
3. **The art pass: it looks finished.** Runs beside stage 2, on the art tier. The remaining pack
   wall states, pictures for the buildables and every new kind, part and frame from stage 1,
   remembered marks, the glimpse disc on the art grid, the last two held weapons, aim following
   the cursor, stamina in the world, the re-illustrated anatomy and the 1280x720 drawer, a roster
   for a large colony. Full before-and-after review at both windows. World draw to its 10 ms
   budget by baking chunks.
4. **Beta: people and the world.** Milestone 3A and the near half of 3B: relationships and grief,
   the six attributes, the full work grid, scars and the blind eye, diagnosis by skill, procedural
   people, the captive arc, explosives, the remaining zombie kinds and raider archetypes, the
   camp's labour cost, evolving camps, outposts that draw raiders, the region as the default boot
   if it plays. The save format freezes here and migrates from then on.
5. **1.0: breadth.** The rest of 3B and Milestone 4: streaming and district tiers, breakdowns and
   mobile bases, the industrial yard, factions and trade, the escape endgame, storyteller presets,
   a signed macOS build. Multiplayer (3C) is off this track and is 1.x unless the owner pulls it
   forward.

## The content arcs

Opened by the owner on 2026-10-26, the same entry. Four arcs, each a group in docs/23's what's
left with one piece per line there; this is the shape and the order, not the list. The rule that
binds all four: **readers before content, pictures a stage behind.** A stat nothing resolves is
not authored; a kind, part or frame gets its picture in the stage after its sim piece.

- **Zombies, seven to fourteen kinds.** Shipped: shambler, runner, stalker, screamer, bloater,
  heavy, armored (`godot/content/zombies/`). Planned, in landing order, each a content file and
  one behaviour hook with its own lane: the crawler (under sightline height, grabs ankles), the
  bloodhound (follows scent alone, deaf to noise), the gassed bloater (a lingering tile cloud),
  the lurker (dormant indoors, wakes on indoor noise), the juggernaut (shoves barricades), the
  burner (spreads fire to timber; waits on fire as a sim fact), the feigner (lies among corpses,
  rises on approach). Each re-baselines the ten-seed table and says so.
- **Raiders, four to nine archetypes, and a doctrine on the band.** Shipped: scav, looter,
  lookout, gunhand (`godot/content/raiders/`). A band gains a `doctrine` the director draws by
  day: probe, raid, siege, trade. Siege camps outside the wall and waits; trade approaches
  unarmed and offers barter, the one verb of Milestone 4's faction seam landed early. New
  archetypes: breacher, marksman, medic, arsonist (waits on fire), dog handler (the hound is a
  scent sensor and pairs with the bloodhound). A raider's weapon is assembled from the same part
  tables, so a dead marksman yields the rifle as he built it. The captive arc already in docs/23
  slots here unchanged.
- **Firearms: every number is a sum of its parts.** The assembly model exists: a base is the
  receiver, it spawns holding real parts, a conversion moves caliber, the bench and the field
  swap are split (`godot/sim/modules/gunsmith.gd`, `attachments.gd`, docs/10). The arc deepens
  it, readers first: the three stats that resolve against nothing (`noise_emission`,
  `condition_loss`, `repair_cost`) gain readers in the shot, the wear event and the repair verb;
  the barrel governs velocity, noise, accuracy and wear by length, quality and material;
  conversions become kits (barrel, bolt or cylinder, magazine, all three or it jams) drawn from a
  realism table in docs/10 keyed by receiver family, about twelve across the twelve receivers;
  furniture reads into aim time, recoil recovery and stance; internals are parts with condition
  and jam chance derives from the worst of them; magazines remember their load, the player picks
  the round, hand-loads are worse; Gunsmithing decides what is field work and the botch chance.
  The bench says it in words, never in numbers.
- **Melee: frames, not weapons, and bespoke results.** The nineteen melee weapons become frames
  in four families (club, blade, polearm, tool) and the slots widen from head, haft and wrap to
  add stud (nails, screws, barbed wire, glass), guard and weight. About twenty-five physically
  plausible recipes, each with what the modification costs the frame: nails split an aluminium
  bat and want wood; a pitchfork head on a pipe wants cordage and a fixing; glass cuts the hand
  without a wrap. Wear is specific: studs fall out on hits (the `struck` wear word), an edge
  dulls and wants a whetstone, a lashed head flies off one swing in N. A weapon past three
  modifications may be named by the player, which is how bespoke reads on a screen with no stat
  line.

**Open owner calls from the arcs** (docs/33 carries them): the realism table for conversions
(the coordinator writes it, the owner vetoes); whether fire becomes a sim fact in stage 1 or
stage 4 (it unlocks the burner, the arsonist and timber walls that burn); whether raiders may
trade before factions exist.

## Open owner calls

[docs/33](33-owner-decisions.md#waiting-on-the-owner) is the list, and the only one. This file
names no card on purpose: a list copied here is out of date after the next card, the same reason
it carries no commit hash. Every card has a default that is already built, so none of them blocks
a piece.

## The shared folder

A Claude project shares `/mnt/project-files/` between its threads. The folder is not in the
repository, and agents outside the project do not have it. It holds evidence and plans, not
instructions.

| Folder | What is in it |
|---|---|
| `planning/` | Plans, one subfolder per topic. Dated plans (the 2026-10-19 alpha plan, the 2026-10-24 feature plans) sit at the top. |
| `planning/balance/` | Playtest reports (`report.md`, `report-noise.md`, `report-ten-seed.md`), raw runs, and `ten-seed/`, one file per commit and seed |
| `planning/<topic>/` | One per feature or slice (`stockpile/`, `night-torch/`, `ui-slice-N/` and so on): its review, its before and after shots, its QA rounds |
| `planning/repo-cleanup/` | The branch audit and the 2026-10-23 cleanup plan |
| `a7-animation/` | Walk exports |
| `a8-actions/` | Action strips (`clothed/`, `clothed/falls-roundN/`, `zombies/roundN/`), each round with its QA report `qa-roundN.md` |
| `a9-aim/` | Aim exports |

- Put new files in a topic subfolder.
- The folder is a network mount. Put a trailing slash on its path, and read a shared file again
  before you change it, because the last write wins.
- **Never cite a `/mnt/project-files` path inside `CLAUDE.md`'s routing table.**
  `npm run check:routing` resolves every backticked path in that section against the repository,
  so such a path turns the gate red.

## Art and animation conventions

In the game:

- A tile is 32 art px, drawn at 2x on the boot zoom (`godot/project.godot`'s display comment).
- A body canvas is 32x40 with the soles on row 39. The heavy's canvas is 40x48 with the soles on
  row 47 (`godot/assets/sprites/README.md`).
- A clothing sheet has one row per view (S, E, N, W). Column 0 is the rest picture, columns 1 to 8
  are the walk, and column 9 is the breath (`godot/art/simplyzombies/clothing/README.md`).
- `npm run godot:check:action` holds every fall, lunge and stagger to the art review's bounds.
  Its header in `godot/check_action.gd` is the full list. The main ones:
  - Per step, the mass changes at most 15%, the centre moves at most 4 columns, and no edge moves
    more than 6 px.
  - The sole row is held. A stagger may rise one row for the knock-back.
  - A fall keeps at least half a head on every beat, and the head ends within 4 px of the
    corpse's head.

In the review exports in the shared folder:

- Survivor reload strips use 48x56 cells, with the sole on row 43 and the head top on row 16. In
  the game the same frames use the 32x40 canvas.
- Zombie action strips use 112x60 cells at 4x, with the sole on row 55.

Read the QA report of the previous round before you start a new one.

## Performance

The targets are in [docs/22](22-performance.md#targets):

- **Tick:** at most 8 ms mean and 16 ms worst. `npm run godot:bench:runtime` measures it.
- **Draw:** at most 10 ms mean. `npm run godot:bench:frame` measures it at 1280x720 and needs a
  display.

The shipped game is over both targets, which is recorded as product debt. CI does not run the
two Godot timing commands. It runs only their exit contract (`npm run check:runtime-budget`).
Measure performance on a quiet machine, and take the median of interleaved runs.

## Screenshots for review

```bash
xvfb-run -a npm run godot:shots     # every scene at 1280x720 and 1920x1080
npm run godot:check:shots           # the gate; its PIXELS lane skips without a display
```

The scenes and window sizes are in `godot/review/scenes.gd`. Many branches edit that file, so it
attracts merge conflicts. Add your scene in a small, separate hunk, and rebase onto `main` before
you push.

## Known noise and traps

- **The worldgen gate's own clock.** `godot:check:worldgen` fails past 90 seconds
  (`BUDGET_SECONDS` in `godot/check_worldgen.gd`). On a loaded local machine it can trip on time
  alone. CI is the judge.
- **The Windows export job.** `godot-exports` sometimes crashes on import. A re-run settles it
  (the steward skill).
- **Engine shutdown noise.** `ObjectDB ... leaked at exit` after an `_OK` line is not a failure.
  Read the `_OK` line and the exit code.
- **Everything else.** [docs/37](37-traps.md), before you touch the sim.
