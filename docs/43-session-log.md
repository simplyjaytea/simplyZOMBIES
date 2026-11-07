# Session log: what each session did and left, newest first

Each entry is the handoff a session wrote when it stopped, moved here from PLAYBOOK.md so the
playbook stays current. Read the newest entry first. Links are relative to this folder.

## Where we left off (2026-11-05 to 06, paused by the owner at night)

The first session with the afternoon roster: the orchestrator plans and dispatches, the lead engineer
reviews every worker change and runs the merge train, two Haiku workers build the pieces and keep the queue
current, Kimi does the art and the art QA signs it off. `PLAYBOOK.md`'s "Where we are" carries the state;
`sz-shared/merge-train-2026-11-05/TRAIN.md` the heads and CI of the open PRs.

**Merged:** #338 (arms art), #348 (the roster), #329 (the crawler), #331 (the arms in the game), #336 (the
bloodhound's scent-led Seek), #327 (the purifier refill), #328 (the clothing layers note, docs/44), #349 (the alarm and noisemaker priced). #346 and
#347 merged first; #322 was closed as a no-op by the owner; fourteen merged remote branches were deleted.

**Opened and queued:** #350 the lurker, #351 the Kei Car, #352 the
bloater's gas decay, #353 the feigner, #354 docs/45 (the wider world by rail), #355 arms polish. The code
pieces are gated on their branches (full chain per shared-module piece); none merged, because the heads need
`main` and CI again.

**Decisions.** 2026-11-05: the roster. Japanese buildings batch A, signed off by the art QA at `db64d031`
after four rounds, was shown to the owner and sent back for a fifth, full character round before any PR.
2026-11-06: all 18 cards on #349, #350, #352, #353, #354 answered; two changed from the built default (the gas
rolls again every 10 s; home is simulated at a coarse tier while away), 16 kept
(`sz-shared/owner-calls-2026-11-06/DECISIONS.md`). The coordinator's engineering call: a merge of `main`
into an art PR keeps the art QA's verdict when the diff of the reviewed paths is empty.

**Art.** Batch A round 5 (the character round) was in progress; its checkpoint is `HANDOFF_round5.md` in
`sz-shared/fp-buildings-jp/`. R4 and batch B wait on batch A. The rifle's round 2 is done and unreviewed. The
arms polish was cleared by the art QA on `67492b7a` (`reviews/fp-arms/confirmation_polish.md`); n1, the skin
tone at the UV seams, stays open. The method is `reviews/fp-buildings-jp/METHOD.md`; the art QA's handoff is
`sz-shared/art-qa/HANDOFF.md`.

**Lessons.**

- Verify a merge with `gh pr view N --json state,mergeCommit` before reporting it: GitHub's GraphQL errors made
  one "merged" report false, and a PR's head view lagged a pushed branch for hours until an empty commit push
  refreshed it.
- Docs-only merges wait until the code queue drains: one early docs merge voided every queued head and cost a
  CI round.
- Two docs PRs that both append `docs/33` cards collide on numbers; number against the queue, not `main`.
- The owner sees the accepted model before the PR: the art QA's sign-off is necessary, not sufficient.
- Small fillers for the queue worker kept both Haiku terminals busy between merges.

## Roster change (2026-11-05 afternoon)

The owner's call: Fable orchestrates and plans, Sonnet is the lead engineer (reviews every worker change, runs the merge train), the rest unchanged; the playbook's team table says so.

## Where we left off (2026-11-04 evening, paused by the owner, usage)

The second session on the Linux machine, the first with the new roster: Claude Fable coordinates,
plans and merges; two Claude Code Haiku terminals do every piece that is not art; Kimi does the art;
Opus subagents did the independent reviews (arms round 2 and its confirmation pass, the rifle), the
clothing design note (docs/44) and the bloodhound's scent-led Seek. The playbook's "Where we are"
section carries the state; this entry is the record of what the session did.

**Merged:** #318, #319, #320, #323 (the setting brief, docs/42), #324, #325 (the trimmed playbook,
one team table, the dispatch workflow for herdr, history moved here), #326 (the organic survivor).

**Opened, all green locally:** #327 the purifier refill (a carried material repacks a spent filter);
#328 the clothing layers design note; #329 the crawler (zombie kind nine, legless from spawn, bites
the legs through a new `grab.bites` reader); #331 and #338 the first-person arms, art and view (the
review's N1, a clip's pose depending on the clip before it, fixed by a deterministic player and an
ARMS-lane assertion); #332 the owner's setting calls (every docs/42 card at its default; the valley is
the first of several; other districts and cities by a train the colony repairs, a plan only); #333
to #344 the renames R1 to R11 (districts and region, templates, food, cartridges, tools and melee,
vehicles, people, descriptions, the playbook and README, the region's cells up-valley with
`SAVE_VERSION` 34); #336 the bloodhound hunts by nose (a Track state on a scent gradient of 20, the
measured ceiling of a body's own smell, so it never tracks itself).

**Art.** Kimi finished the arms round 3 (`7bf7236b`, all 24 plants refused) and the hunting rifle
(`c77c938a`), which the independent review BLOCKED on shape (a receiver that reads as a scope); the
round 2 spec is written. Kimi started the Japanese buildings batch A.

**Lessons.** A pipeline hides a failed `gh pr merge` (`| tail` swallowed the exit code and the next
step deleted the branch; #318 had to be reopened): never pipe the merge. `--match-head-commit` wants
the full 40-character SHA. Deleting a merged PR's head branch closes every PR based on it (#330 became
#338): retarget stacked PRs first. Branch protection wants CI even on docs-only PRs. The Haiku
workers end their turn with a gate shell still running unless told not to; every spec now says so.
CI capacity, not the workers, set the pace once a dozen PRs were open: batch collisions into one
integration PR early.

## Where we left off (2026-11-04, stopped by the owner)

The first session on the owner's Linux machine. The roster above is out of date here. Claude
(Opus 5.5) coordinates. Kimi Code (K3.1 Pro) does the models and now also the final paint; Codex
was dropped and its `codex/fp-survivor-paint` branch deleted. Two OpenCode terminals do mechanical
code. The terminals run in herdr (`hc ls`, `hc send`, `hc read`, `hc wait`), not Orca. The shared
folder is `/home/jtf/sz-shared/`, with worker rules in `WORKER_RULES.md`. The Windows folder's
contents did not carry over, including the owner's survivor concept image. Every Godot and Blender
job runs under `xvfb-run -a`, so no window opens on the owner's desktop. This machine's Blender
links zlib-ng, so rebuilt GLBs and PNGs differ in bytes, not pixels, from Windows-built files.
Compare pixels before calling a byte change a bug.

**The owner's calls today** (docs/30): first person is the game and top-down is legacy; the setting
is Japan, inspired by the Ome–Okutama valley. Remote leftovers were deleted after a bundle backup
(`/home/jtf/sz-shared/backups/`). The archive branch
`archive/topdown-colony-pre-first-person-2026-11-01` is kept.

**Open pull requests, waiting on the owner's go-ahead to merge.** Each passed its local gates. All
of them touch docs/23's record, and most touch this file. Merge one at a time: merge `main` into
the next PR (never rebase), keep both sides of docs conflicts, and wait for CI on the new head.

1. #316: the held weapon hides behind screens and in third person (HIDE lane).
2. #317: every indoor tile gets a ceiling (CEILINGS lane of `godot:check:fp_geometry`).
3. #318: the weapon kit's lathes are smoothed (SHADING check), and the README says what horde use
   costs.
4. #319: zombies and colonists stop reaching for what a wall keeps out. It has one owner question:
   a colonist carrying a melee weapon and a gun now shoots across a fence instead of swinging at it
   (docs/30, "A reach test chooses whom, not whether").
5. #320: the item kit draws liquids, preserves and the bolt correctly (`length` check). The bolt
   model itself is weak art.
6. This docs pull request: the legacy call, the setting call, and this handoff.

**Stacked branches, no pull request yet; the order matters.**

1. `kimi/fp-survivor-base`. The independent review (`sz-shared/reviews/fp-survivor-base/`) found
   three blocking faults, so it is fix-then-merge. The paint follows atlas islands (the back of the
   top is brown while the front and sleeves are charcoal), the density claim does not hold (hands
   73–91 px/m against 128), and the README numbers are stale. Kimi's spec is
   `sz-shared/fp-survivor-base/task-kimi.md`. It starts by merging `main` in, since the branch is
   30+ commits behind. After the fixes, the same reviewer does a confirmation pass.
2. `claude/fp-arms`, the arms art. Round 2 (`cecb4c45`) prints `ARMS_CHECK_OK` and refuses all 22
   plants. Its in-engine comparison is `sz-shared/fp-arms/round-2/in-engine/comparison.png`. A
   first look found the round 1 faults gone: no black streaks on the hands, and charcoal knit
   sleeves instead of the camouflage-like pattern. The formal independent review has not been done.
   The `long` class still shows a placeholder box, because the weapon kit has no rifle.
3. `claude/fp-arms-view`, the arms in the game (`arms_view.gd`, the ARMS lane; head 96c579be). It
   needs the two above first, and will conflict with #316 in `_update_held_weapon`: fold #316's
   hide into `view_covered()`. It has six owner questions, each with a default built: lower behind
   every screen; a swap of 0.3 s lowering then 0.5 s drawing; the hold-class rule; inspect repeating
   while L is held; no aim-down-sights yet; and no weapon in third person.

**Next session, start here, in order.**

1. `gh pr list`, and each PR's CI. If the owner has given the go-ahead, run the merge train in this
   order: #321 (docs, so later sessions read this from `main`), #316, #317, #318, #319, #320. After
   each merge, merge `main` into the next PR, rerun its touched gates, and wait for CI on its new
   head.
2. Ask the owner what is still open: #319's shooting default, the six arms defaults
   (`claude/fp-arms-view`), docs/33's firearms card, and the survivor concept image, which goes in
   `/home/jtf/sz-shared/concept/`.
3. Send Kimi `/home/jtf/sz-shared/fp-survivor-base/task-kimi.md` (the survivor fixes). It has
   not started.
4. Meanwhile, start an Opus subagent on an independent review of arms round 2. It gets the branch,
   its in-engine captures and this file's art rules. If the review is clear, open the arms art PR
   once the survivor's PR has merged, then `claude/fp-arms-view`'s PR.
5. With the workhorses free, write the Ome–Okutama setting brief, a new doc (see docs/23's planned
   piece). Only after the brief come Japanese building templates for Kimi and content renames for
   the workhorses.
6. Then, from the to-do list: a rifle model for the `long` class, the zombie kinds, and the
   clothing note.

**Worktrees left on disk** under `.claude/worktrees/`: `fp-arms`, `fp-arms-view`,
`fp-survivor-base` (with work still to do), and the PR branches `fp-cleanup`, `fp-ceilings`,
`fp-weapon-polish`, `fp-item-polish`, `fp-reach` and `topdown-legacy`. Remove each PR branch's
worktree once its PR merges.

**Lessons.** The OpenCode workers, at the owner's medium effort, did the first easy step and then
reported done. Three times running they skipped the gate, the plant and the docs. A specific list
of what was missing got the fixes done. Pieces that need a new gate went to an Opus worker. Read
every worker's diff and manifest before trusting its report.

## Where we left off (2026-11-01, paused by the owner)

The first-person conversion ([docs/39](39-first-person-pivot.md)) is the work in hand. The
default boot is the first-person scene; the top-down game is reached with
`npm run godot:run:topdown`, and the title's "first person" row returns to first person. This
section is the handoff written when the owner paused the morning's work; the queue it lists has merged since
(#288 to #302, through #306's integration), and the session record below it is the current
state. Read both, then `gh pr list` and each pull request's CI, because both move.

**On `main`.** The pivot plan (docs/39), the spatial contract
([docs/40](40-first-person-spatial-contract.md)), the first-person foundation and its
integration (containers, save and load, death and succession, doors, stance and gait, interim
fighting, the title row, day, night and the carried light, the ledger's Reports page, the shipped
district size, art that loads from a clean checkout), spatial slice 1 (`SimSpace`'s height
profile) and slice 2 (melee and zombie reach stop at walls), game speed, the Blender starter kit
and the weapon kit, the README's first-person section, the owner cards in docs/33, and the
review follow-ups in docs/23's first-person group.

**The queue that has since landed, in the order it merged.** Each merged `main` in and waited
for CI on its new head first (How work flows, step 5); the conflicts were docs/23's record list
(keep both entries) and the lane list and OK sentence of `godot/check_first_person.gd` (keep both
lanes).

1. #292 the starter kit drawn in the scene (walls, boards, shelves), and #290 aim pitch
   (spatial slice 3; the save stays at its version, reasoned in docs/30 "A pitch with no yaw").
2. #294 body animation state, then #297 talking to a colonist (stacked on #294); #295 the F1
   key reference; #296 the end-to-end expedition gate.
3. #299 the loot-item kit (art review clear after three rounds), then #301 the model loader
   (reads every `*.manifest.json`, shares one mipmapped texture per atlas, draws loose items),
   then #300 the held weapon assembled from the sim's installed parts.
4. #288 the survivor and shambler, after the independent art review's round 3. Then the body
   view plays its clips from #294's animation state.
5. #302, docs only: the weapon and item kit polish minors.

**In flight when paused.** The Kimi terminal was researching and prototyping better buildings
and walls (the owner: they look rather large and not good enough; make them look like Project
Zomboid). Its brief: a proposal at the coordinator's scratch path, a prototype on branch
`kimi/fp-buildings-proto` (no pull request), and before-and-after captures. The likely cause is
that a wall is a whole 1 m tile 2.55 m tall where Zomboid's walls are thin and on tile edges;
the proposal separates art-only fixes from sim changes (edge walls, a finer grid, a lower wall
band), which touch shared modules and may be owner calls. Read the branch and its report before
starting anything on buildings.

**Next, in order.** Review Kimi's buildings proposal with the owner. Then
[docs/41](41-weapons-characters-world-plan.md), the plan for weapons, characters and a
bigger world: the bodies and the held weapon in the scene first, then a dressed and furnished
town, modular weapons, and docs/40's slices 4 to 7. The seven zombie kinds are the art lead's
next piece after the characters clear. A small cleanup is owed: `check_first_person.gd` prints
one hand-written OK sentence that every parallel branch edits; generate it from the lane list so
it stops conflicting.

**Waiting on the owner.** docs/33's first-person cards (the seven questions from docs/40 and the
pause policy), and docs/41's "For the owner" list. Every one has a default already being built.

## What the session of 2026-11-01 did

- **The survivor base body.** The box-segment `survivor.glb` was replaced by an organic,
  smooth-skinned woman matching the owner's concept art: 7,810 triangles, a modelled face,
  volumed hair with a high bun, painted pixel textures at 256 px/m (head) and 128 px/m (body).
  Four model rounds and five atlas versions. The modeler began it and handed off for usage; an
  Opus worker finished it. Committed on `kimi/fp-survivor-base`, not yet pushed; the owner
  called it "a good base, it can be improved upon. A lot."
- **The in-engine review driver** (`godot:shots:survivor`), PR #312, merged.
- **First person is the default boot;** F2 toggles a third-person testing view; the top-down
  game opens with `npm run godot:run:topdown`. PR #313.
- **The first-person arms contract** (`sz-shared/fp-arms/CONTRACT.md`) with the owner's answers:
  bare hands (gloves only when worn), inspect on a held `L`, an own view-model FOV with no wall
  clipping, 128 px/m for arms and bodies. The arms art started on `claude/fp-arms`.
- **PR #310** (building finishes) failed its first independent review (windows drawn as
  solid wall, inside-out hip roofs, a CRLF manifest), was fixed by an Opus worker with a
  real-worldgen window gate, and passed its confirmation pass.
- **The merge train, done.** #312, #308, #307, #313, #309, #310 and #311 merged, in that order.
  The owner chose to merge the last five without waiting for CI on their final heads.
- **Repo cleanup:** 41 merged worktrees removed, 37 merged local branches deleted, local main
  fast-forwarded.
- **This playbook.** `CLAUDE.md`, `AGENTS.md` and docs/38 merged into one root file, the
  owner's call, and the roster amendment of the model-identifier rule (docs/30).

## Lessons from the session

- Render the existing asset before judging it; the "blocky" problem was visible in one render.
- The in-engine sheet is the judge; Blender renders flattered the model each round.
- A hand-painted 2D target for first-person arms did not converge; the 3D model sets the pose.
- An independent reviewer catches what a gate misses: the window bug passed its gate because
  the gate stamped templates without real worldgen.
- Stacked PRs (a PR based on another PR's branch) keep dependent work moving; the coordinator
  retargets them to main after the base merges.
