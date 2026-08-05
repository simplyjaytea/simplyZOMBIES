# Handoff

State of the project for whoever picks it up next — a person or a fresh session. Written 2026-08-05,
updated the same day once the spike findings were folded into the docs.

**Read this, then [README.md](README.md), then [TODO.md](TODO.md).**

---

## Where things stand

| | |
|---|---|
| **Phase** | Design complete. One throwaway prototype built. **No production code yet.** |
| **Merged** | [PR #1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) — 27 design docs + the backlog · [PR #2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) — the attention field spike |
| **In flight** | The spike fold-in — the three findings written into the specifying docs |
| **Next real work** | **Milestone 0.** `TODO.md` has it broken into tasks. |

## What's in the repo

```
docs/           27 design documents. The README index is the reading-order authority,
                not the file numbers — 24-26 were written last but belong under "The world".
TODO.md         148 tasks covering Milestones 0-2, with all 8 roadmap risks pinned to the
                specific task that answers each one.
spike/          THROWAWAY prototype. Not Milestone 0 with corners cut — a different
                artifact. Delete it freely once its findings are absorbed.
```

There is no `src/`. That's Milestone 0's job.

## Settled decisions: do not relitigate

These were each decided explicitly by the repo owner. If you're about to "improve" one, don't:

- **Hardcore is the thesis, not a difficulty slider.** Permadeath with succession into another
  survivor; no win condition plus an optional expensive escape.
- **No wave timer.** Horde pacing is attention-driven and director-paced.
- **Blank slates, no classes.** The build lives in found gear (PoE-shaped affixes) plus a classless
  skill web earned by doing. Applies to every survivor, not just the player.
- **Survivors are unlimited and procedurally generated.** Recruits arrive as unskilled nobodies — that
  is the counterweight that keeps permadeath meaningful.
- **Melee and ranged both good**, spending non-convertible currencies (body/bite-risk vs.
  ammo/attention).
- **Fully drivable continuous region**, no abstracted travel legs. **Full nomad play viable.**
- **Performance is pillar 6**, with CI budget gates that fail the build.
- **Stack:** TypeScript + canvas + Vite, no engine, with a portability contract keeping a Godot pivot
  cheap. **Saves may break pre-1.0** — stable IDs and a version stamp, but no migration framework.
- **Vehicles were un-cut** after initially being cut at the vision level. `docs/00-vision.md` records
  the reversal and why the original objection was half right.
- **A district is 256 m, falloff stays linear.** Decided against re-authoring the magnitude table,
  because its ratios are load-bearing in six documents and only the unit was ever missing.
- **Field memory is scent, never noise.** Kept rather than cut, but on the condition that Milestone 1
  proves it does something.

## What the spike settled

The three findings are **folded into the documents that specify the systems**. Don't redo this; the
docs are the authority now and [`docs/23-roadmap.md`](docs/23-roadmap.md#spike-findings-attention-field)
keeps the evidence.

| Finding | What was decided | Now specified in |
|---|---|---|
| Gradient ascent alone makes **conga lines**, not a horde | Persistent per-individual angular bias (±0.62 rad), from the seeded RNG, in save state. No neighbour queries, no measurable cost. | [`docs/14`](docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own) |
| **Noise magnitudes aren't calibrated to district size** | The magnitudes were never wrong — the **unit** was never defined. 1 tile = 1 m, 0.7 attenuation per metre, 4 m field cells, **256 m district**, so one gunshot = one district. **Zero magnitudes changed.** | [`docs/03`](docs/03-attention.md#scale-and-calibration), [`docs/24`](docs/24-world-and-scale.md#how-big-a-district-is) |
| **Field memory is a no-op** | The spike tested it on the wrong channel. It's a **scent** mechanic in both specifying docs; residue-as-noise dies inside its own cell by arithmetic. Kept, on scent, with a Milestone 1 acceptance check that cuts it if nothing observable changes. | [`docs/03`](docs/03-attention.md#field-memory-is-a-scent-mechanic) |
| **Rendering dominates simulation** (~30×) | Draw budget and sim-share-of-frame budget added; every benchmark asserts frame time, not just tick time. | [`docs/22`](docs/22-performance.md#aim-the-budgets-at-the-renderer) |

Also worth keeping: **event-driven noise propagation is vindicated** — 6 live field cells when quiet.

## Do this next

**Milestone 0.** `TODO.md` has it broken into tasks. The exit criterion is: *an entity moves around a
tile map deterministically, and the same seed plus inputs reproduces it byte-identically.*

Nothing blocks it. The fold-in above was the only thing outstanding, and it was blocking Milestone 1
rather than Milestone 0 anyway.

## Open questions nobody has answered

- **Is being quiet *tense*, or just slow?** Needs a human playing. With noise as the only channel,
  quiet is *completely* safe — which is the design as specified, and the strongest argument that scent
  isn't optional.
- **Scent cost.** Untested. It's the continuous channel [risk 5](docs/23-roadmap.md#risks) is actually
  about, so that risk is narrowed, not closed. It now carries a second question too: field memory has
  never been observed working, because it needs scent to exist first.
- **How long is a day, really?** Four hours at 1× is still a guess.
- The rest are listed under "Open questions" in [`docs/23-roadmap.md`](docs/23-roadmap.md).

*"How big is a district?" is no longer among them — it's 256 m, forced by the noise calibration.*

## Conventions and gotchas

- **Never put an em dash in a heading you intend to link to.** GitHub's anchor slugs collapse
  ` — ` into a double hyphen, and it has silently broken links three times in this repo. Use a colon.
  Several headings were rewritten for exactly this reason.
- **Every doc opens with "why this exists" and closes with a cut list.** The cut lists are load-bearing
  — they're what stops scope creep, and `TODO.md` restates them at the end for the same reason.
- **The README index is the reading order.** File numbers reflect authorship order.
- **The container is ephemeral.** Anything uncommitted is gone when the session ends.
- `.claude/settings.local.json` is git-ignored globally and won't travel with the repo.

## Commands

```bash
npm install
npm run dev              # spike at http://127.0.0.1:5173
npx tsc --noEmit         # typecheck
node spike/measure.mjs   # scenario sweep + screenshots -> /tmp/spike-shots
node spike/compare.mjs   # conga-line A/B (gradient spread off vs on)
```

Spike controls: `WASD` move · `Shift` sprint · `Space` shout · `O` overlay · `L` +500 zombies ·
`J` toggle the spread fix · `M` field memory · `P` pause.

There are no tests and no CI yet. Both are Milestone 0 tasks — including the performance budget
harness that pillar 6 requires.
