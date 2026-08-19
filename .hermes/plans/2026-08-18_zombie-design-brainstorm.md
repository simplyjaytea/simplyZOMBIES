# Zombie design brainstorm — filed for post-slice

*2026-08-18. Owner-approved ideas from a design session; parked deliberately. Milestone 2 is
shamblers-only (docs/23), so nothing here is scheduled work. docs/14 remains the authority on the
specced roster (stalker, screamer, armored, heavy, bloater, runner, tracker) — this file holds the
visual language and the speculative types that are NOT yet in any spec.*

## Visual language for the specced roster

At 64×96 in a dark, desaturated world the player reads silhouette → tint → detail. One loud tell
per type, legible in outline alone; the shambler stays deliberately plain because every other type
is a deviation from it.

- **Shambler** — slumped, one hanging arm, head lolling. The baseline body.
- **Screamer** (`#d95947` in content) — the throat is the tell: distended jaw, head thrown back,
  slighter frame (its body is mechanically weak). "Thin one with the open mouth = kill it first,
  silently."
- **Bloater** (`#6b8c47`) — swollen torso dominating the outline, tiny head, ponderous pose. The
  art is its own warning label.
- **Stalker** — head-forward listening posture, lower and longer than a shambler.
- **Armored** — *accumulated* debris (road sign, car door, rebar), bulky and asymmetric. Reads
  "light weapons useless."
- **Heavy** — allowed to break the one-tile footprint; not fitting is the tell.
- **Runner** — mid-stride, forward-leaning, motion in the standing pose.
- **Tracker** — underplayed on purpose: nose-down, deliberate, almost normal. Its horror is
  behavioral.

**Rule:** art must never leak sim state (same clause as the health-bar ban). No "damaged" sprite
variants keyed to integrity; the crawler is the exception because lost legs are already
sim-visible behavior.

## Speculative new types (each named by the habit it breaks)

| Type | Behavior sketch | Breaks the habit of | Build cost |
|---|---|---|---|
| **Feeder** | Lingers on corpses; disturbed → scent burst | Leaving bodies where they fall | Near content-only (emits + corpse-seek); makes Bury matter |
| **Still One** | Near-zero locomotion until nearby noise spikes; reads as a corpse | Looting confidently | Content + a wake behavior; fairness needs a subtle tell |
| **Lamplit** | `light: 1.0`, scent nearly ignored | Free lantern/torch use at night | Pure content (sensory profile) — cheapest |
| **Latcher** | Weak grab (0.2) it never wins, never bites, never lets go; holds you for the crowd | Treating one zombie as zero threat | Small behavior on shipped grab/rescue machinery |
| **Hollow** | No noise, no scent trail; sight-only | Trusting the attention overlay | No new code, heavy tuning; rare + slow or it is unfair |

Sight-triggered behavior (screamer's alarm, any Still One wake-on-seen variant) is downstream of
the visibility system, not of content — docs/14's own caveat.
