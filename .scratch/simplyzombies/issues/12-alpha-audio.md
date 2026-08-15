# 12 — Alpha audio one-shots (2D, magnitude volume)

Type: grilling
Status: resolved
Blocked by: 04, 08

## Question

Sim noise magnitudes are locked (walk 1 / shout 120 / board 30 / alarm 8 / noisemaker 45 / gunshot 180, 0.7/m). Alpha has no audio bus. Ticket 07’s flank “audio tell” is the **field** (undergrowth ×1.3). Do we ship heard sound for the locked emitters, and how does hearing relate to reach on a 256 m iso map?

## Answer

**Grilled 2026-08-15 with ticket 11 — pick Q9:B. Resolved.**

Alpha ships **five one-shots + one loop**, 2D, volume from magnitude, **no wall occlusion**. Hearing uses the same reach identity as the field (`metres = magnitude / 0.7`) so a gunshot is a district and a board is ~43 m. Footsteps stay silent (they are already the overlay / stance tell). Spatial 3D, surface materials, and voice are out.

| Event | Clip | Mag | Reach | Play |
|---|---|---|---|---|
| Shout | `sfx/shout.wav` | 120 | 171 m | `noise.emitted` mag 120 (Space) |
| Gunshot | `sfx/gunshot.wav` | 180 | 257 m | pistol `noise.emitted` 180 |
| Board / scrap / alarm-place / wind | `sfx/board.wav` | 30 | 43 m | construction 30 sustained → one-shot on **start**, not per tick |
| Alarm trip | `sfx/alarm.wav` | 8 | 11 m | `alarm.tripped` (also the 10× drop) |
| Noisemaker | `sfx/noisemaker.wav` loop | 45 | 64 m | while `expiresAtTick > tick`; stop on expire |

Volume at the listener: `clampf(mag/180, 0, 1)` then distance falloff with the same 0.7/m, **no** extra 18 m wall penalty (Q9:B, no occlusion). Alarm at 8 is quiet on purpose — it is a local wake, not a shout. Own shout/shot/board play at full mag (distance 0).

Files: `godot/assets/sfx/*.wav`, git-tracked, Nearest is irrelevant (audio). Placeholder sine/noise is fine until a take exists. Presentation subscribes; **sim stays mute** (no `AudioStream` in `sim/`). Headless: no gate on the WAV, only that the events still publish.

`ponytail: one AudioStreamPlayer2D (plus one looping player for bait); pan from iso screen x is a later afternoon.`

### Explicitly deferred

Footstep SFX · surface materials · 3D spatial · occlusion pass · WebRTC / doc 27 voice · music · a heard-range widget.

Status: resolved.

## Notes

- Docs: 03-attention.md (reach = mag/0.7), 28-visibility (audio occlusion is extra, skip), 27-multiplayer (audio is not sim).
- HITL: Q9:B on the ticket-11 round. Not a sim gate.
