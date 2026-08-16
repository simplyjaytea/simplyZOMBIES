# 12 — Alpha audio one-shots (2D, magnitude volume)

Type: grilling
Status: resolved
Blocked by: 04, 08

## Question

Sim noise magnitudes are locked (walk 1 / shout 120 / board 30 / alarm 8 / noisemaker 45 / gunshot 180, 0.7/m). Alpha has no audio bus. Ticket 07’s flank “audio tell” is the **field** (undergrowth ×1.3). Do we ship heard sound for the locked emitters, and how does hearing relate to reach on a 256 m iso map?

## Answer

**Grilled 2026-08-15 (Q9:B) + 2026-08-16 builder round — picks: Q1:A · Q2:B · Q3:B · Q4:B · Q5:B · Q6:A. Resolved.**

Alpha ships **six clips** (five one-shots + noisemaker loop), 2D, volume from magnitude, **no wall occlusion**. Hearing uses the same reach identity as the field (`metres = magnitude / 0.7`). Footsteps stay silent. Spatial 3D, surface materials, and voice are out.

| Event | Clip | Mag | Reach | Play |
|---|---|---|---|---|
| Shout | `sfx/shout.wav` | 120 | 171 m | `noise.emitted` mag 120 (Space) |
| Gunshot | `sfx/gunshot.wav` | 180 | 257 m | pistol `noise.emitted` 180 |
| Bow | `sfx/bow.wav` | 4 | ~5.7 m | bow `noise.emitted` 4 (Q3:B) |
| Board / scrap / alarm-place / wind | `sfx/board.wav` | 30 | 43 m | one-shot on **construct start**, not per tick |
| Alarm trip | `sfx/alarm.wav` | 8 | 11 m | `alarm.tripped` |
| Noisemaker | `sfx/noisemaker.wav` loop | 45 | 64 m | while live; **stop out of reach, restart on re-enter** (Q5:B) |

Volume at the listener: `clampf(mag/180, 0, 1)` then distance falloff with the same 0.7/m, **no** extra wall penalty (Q9:B). Listener is **camera centre** (Q2:B), not the controlled body. Own shout/shot/board at distance 0 is full mag.

### Builder picks (2026-08-16)

- **Q1:A** — Commit tiny generated WAVs under `godot/assets/sfx/` (placeholder sine/noise until a take exists).
- **Q2:B** — Listener = camera / viewport centre.
- **Q3:B** — Soft bow clip at mag 4.
- **Q4:B** — Pool of 3 one-shot `AudioStreamPlayer`s (overlap allowed).
- **Q5:B** — Noisemaker: stop when out of reach; restart on re-enter.
- **Q6:A** — No new gate; fortify/ranged gates still own event publish. Dummy ALSA cannot prove hearing in CI.

Files: `godot/assets/sfx/*.wav`, git-tracked. Presentation: `godot/presentation/sfx.gd` (child of main). **Sim stays mute** (no `AudioStream` in `sim/`).

### Explicitly deferred

Footstep SFX · surface materials · 3D spatial · occlusion pass · pan from iso screen x · WebRTC / doc 27 voice · music · a heard-range widget · WAV CI gate.

Status: resolved.

## Notes

- Docs: 03-attention.md (reach = mag/0.7), 28-visibility (audio occlusion is extra, skip), 27-multiplayer (audio is not sim).
- HITL: Q9:B on the ticket-11 round; Q1–Q6 builder round 2026-08-16.
