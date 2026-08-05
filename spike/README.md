# Attention field spike

**This is throwaway code. It is not the game, and it is not Milestone 0.**

It exists to answer one question before any architecture gets built:

> **Make noise and they come. Go quiet and they don't.** — is that fun?

If the answer is no, [the vision](../docs/00-vision.md) needs revisiting and none of the ECS, event
bus, modifier pipeline, or content registry in
[the architecture docs](../docs/19-architecture.md) should be written yet. That's
[roadmap risk 4](../docs/23-roadmap.md#risks), and this is its cheapest possible mitigation.

## Run it

```bash
npm install
npm run dev      # http://127.0.0.1:5173
```

## Controls

| Key | Action |
|---|---|
| `WASD` | Move |
| `Shift` | Sprint — faster, and six times louder |
| `Space` | Shout — a deliberate 120-magnitude noise event |
| `O` | Toggle the noise heat map |
| `L` | Spawn 500 zombies (the load test) |
| `K` | Spawn 60 more |
| `C` | Clear all zombies |
| `M` | Toggle field memory (milling bodies emitting residue) |
| `J` | Toggle per-individual gradient spread — **turn it off to see the conga lines** |
| `P` | Pause |

Zombie colours: **green** wandering · **red** seeking a noise · **amber** milling at a dead end.

## What it deliberately is not

No ECS. No event bus. No modifier pipeline. No content JSON or schemas. No save/load. No determinism
harness. No CI. No light or scent channels. No injuries, needs, items, survivors, or director.

Every one of those is [Milestone 0 and 1](../TODO.md)'s job. Building them here would be exactly the
bet risk 4 warns about.

**Scent is deliberately absent.** It is the expensive continuous channel and the one
[risk 5](../docs/23-roadmap.md#risks) names. It is only worth paying for if noise reads as fun first.

## The five questions

Written down before running it, so the result isn't graded on vibes:

1. **Is it legible with the overlay off?** If you can only understand the mechanic with a heat map on
   screen, the diegetic cues in [docs/03](../docs/03-attention.md) aren't sufficient — a design
   problem, not a UI one.
2. **Is being quiet tense, or just slow?** The design bets a quiet stretch is frightening. It might
   just be boring.
3. **Does the gradient produce readable horde movement**, or does it look like random drift?
4. **What does 500 zombies actually cost?** The risk 5 checkpoint, arriving two milestones early.
5. **Does field memory matter?** Toggle `M` and see whether anyone notices.

## Measuring it without a human

```bash
node spike/measure.mjs   # scenario sweep + screenshots -> /tmp/spike-shots
node spike/compare.mjs   # conga-line A/B, spread off vs on
```

Both drive Chromium via Playwright and print frame/sim timings.

## Findings

**Written up in full in [docs/23-roadmap.md](../docs/23-roadmap.md#spike-findings-attention-field).**
In short:

- ✅ **The mechanic works.** Convergence is legible with the overlay off.
- ⚠️ **Gradient ascent alone makes conga lines**, not a horde. Fixed here with a per-individual angular
  bias, at no measurable cost. `J` toggles it.
- ⚠️ **Noise magnitudes aren't calibrated to district size** — one shout floods an entire 80×80 district
  for 13+ seconds.
- ⚠️ **Field memory is a no-op** at the specified magnitudes.
- ✅ **Performance is a non-issue for noise**: 0.13 ms sim at 1,560 zombies. Rendering dominates.
- ❓ **Scent is untested**, and it's the expensive continuous channel.

## Design values borrowed from the docs

Magnitudes come from [docs/03-attention.md](../docs/03-attention.md), scaled to this map:
walking `1`, sprinting `6`, shouting `120`. Walls cost an extra 26 attenuation to propagate through,
which is why a building is worth being inside.

Findings get written back into [docs/23-roadmap.md](../docs/23-roadmap.md) under risks 4 and 5. The
checkpoints exist to be answered.
