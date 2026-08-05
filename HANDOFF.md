# Handoff

State of the project for whoever picks it up next — a person or a fresh session. Written 2026-08-05.

**Read this, then [README.md](README.md), then [TODO.md](TODO.md).**

---

## Where things stand

| | |
|---|---|
| **Phase** | Design complete. One throwaway prototype built. **No production code yet.** |
| **Merged** | [PR #1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) — 27 design docs + the backlog, now on `main` |
| **In flight** | [PR #2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) — the attention field spike, branch `spike/attention-field`, open and mergeable |
| **Next real work** | Milestone 0, but **fold the spike findings into the docs first** (see below) |

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

## Do this next

### 1. Fold the spike findings back into the docs *(blocking Milestone 1, not Milestone 0)*

The spike found three real problems. They're written up in
[`docs/23-roadmap.md`](docs/23-roadmap.md#spike-findings-attention-field) but **not yet reflected in
the documents that specify the systems**:

| Finding | Fix | Lands in |
|---|---|---|
| Gradient ascent alone makes **conga lines**, not a horde | Persistent per-individual angular bias (±0.62 rad). Costs nothing measurable. Working code in `spike/zombies.ts`. | `docs/14-zombies.md` |
| **Noise magnitudes aren't calibrated to district size** — one shout floods an 80×80 district for 13+ s | Either much bigger districts or a steeper-than-linear falloff. Answers the roadmap's open "how big is a district?" question. | `docs/03-attention.md`, `docs/24-world-and-scale.md` |
| **Field memory is a no-op** — residue never propagates past its own cell | Raise the magnitude or cut the mechanic. Don't carry it as decoration. | `docs/03-attention.md` |

### 2. Then Milestone 0

`TODO.md` has it broken into tasks. The exit criterion is: *an entity moves around a tile map
deterministically, and the same seed plus inputs reproduces it byte-identically.*

Two things the spike changed about how to approach it:

- **Aim performance budgets at the renderer, not the simulation.** Measured ~3 ms draw against ~0.1 ms
  sim at 1,560 zombies. The simulation is nowhere near the budget; rendering is the cost.
- **Event-driven noise propagation is vindicated** — 6 live field cells when quiet. Keep that design.

## Open questions nobody has answered

- **Is being quiet *tense*, or just slow?** Needs a human playing. With noise as the only channel,
  quiet is *completely* safe — which is the design as specified, and the strongest argument that scent
  isn't optional.
- **Scent cost.** Untested. It's the continuous channel [risk 5](docs/23-roadmap.md#risks) is actually
  about, so that risk is narrowed, not closed.
- **How long is a day, really?** Four hours at 1× is still a guess.
- The rest are listed under "Open questions" in [`docs/23-roadmap.md`](docs/23-roadmap.md).

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
