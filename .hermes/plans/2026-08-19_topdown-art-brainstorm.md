# Top-down art brainstorm — pawns for a flat district

**Status: parked design thinking, post-slice. Nothing here is scheduled work.** The projection
reversal (docs/00) and the 64×64 centre-anchored canvas are decided and shipped; everything below
is candidates for the *flavour* on that canvas, for the owner to pick from. This file supersedes
the visual-language half of `2026-08-18_zombie-design-brainstorm.md`, whose tells were authored
as profile silhouettes ("head thrown back", "forward-leaning mid-stride") that an overhead camera
mostly destroys. Its invariants are kept whole:

- The player reads **silhouette → tint → detail**, in that order, at speed, in the dark.
- **One loud tell per type**, legible in outline alone. The shambler stays deliberately plain
  because every other type is a deviation from it.
- **Art must never leak sim state** (same clause as the health-bar ban). No "damaged" sprite
  variants keyed to integrity. The crawler stays the sole exception because lost legs are
  already sim-visible behaviour.
- A peripheral glimpse is one anonymous shape — no posture, no limbs, no facing. Whatever the
  art style, it only ever applies to Focal bodies (`docs/30`, now enforced at the draw site).

## The shipped baseline

The regenerated set (Mara, shambler, three equip overlays) is a **RimWorld-proportioned upright
pawn on the Zero Sievert palette**: oversized head (~40% of figure height), rounded shoulder-mass
torso, stub legs, 1 px near-black outline, desaturated mid-tones, light speckle grit on cloth.
Equip overlays composite at the body's rect: `back` peeks over the shoulders and past the sides,
`primary` hangs at the hand, `equipSpriteFront` carries straps that cross the chest.

## Three flavour directions

### A. Pure RimWorld read (non-rotating pawns) — the shipped default, taken further
Figures stay upright and face-on at every heading; motion is position change alone, facing is
the sim's thin indicator line. Tells live in **mass, colour, and headgear** — the three things
RimWorld proves survive an overhead camera.
- Cheap: one sprite per type, no rotation support, the equip pipeline works as-is.
- Risk: combat readability leans on the facing line; a shambler "lunging" looks identical to
  one idling until it moves.

### B. Zero Sievert read (true overhead, rotating player)
The avatar is drawn from straight above (shoulders, head crown, weapon held forward) and
**rotates to its facing**; NPCs and zombies stay non-rotating pawns (ZS itself does this split).
- Buys: the player's facing and aim become the body itself; the aim cone grows out of the
  gun barrel. Strongest combat feel of the three.
- Costs: rotation support in the renderer (`draw_set_transform` around the blit — a contained
  change, the centre anchor was chosen so this stays possible); equip overlays must be authored
  on the rotated rig; and the peripheral-anonymity rule must not be weakened — only the
  *player's own* body rotates, other Focal bodies keep the pawn read, or their facing leaks.
- Note: mixing a rotating top-down player with face-on pawns is a real aesthetic seam; ZS ships
  it and it reads fine in motion, but it must be a deliberate pick, not a drift.

### C. Hybrid high-3/4 (the mash-up the owner sketched)
Keep A's non-rotating pawn but pull the camera-angle *implied by the art* down a few degrees:
slight foreshortening, visible boot-fronts, gear silhouettes breaking the outline (slung rifle,
pack frame). Closest to "RimWorld body, Zero Sievert wardrobe".
- Buys: grit and identity without rotation machinery.
- Risk: half-perspectives age badly if different artists (or different generator prompts) pick
  different implied angles; wants a one-page rig sheet before more than five sprites exist.

## Zombie tells, re-authored for overhead

| Type | Profile tell (old, dead) | Overhead tell (candidate) |
|---|---|---|
| Shambler | slumped, one hanging arm | deliberately plain; one arm's mass hangs lower in the outline |
| Screamer | head thrown back, distended jaw | head pale circle split by a black open-mouth void, `#d95947` tint |
| Bloater | swollen torso dominating profile | sheer girth — outline wider than any survivor's, `#6b8c47` tint |
| Stalker | head-forward, lower and longer | prone-length figure, limbs out — reads as crawling mass |
| Armored | bulky and asymmetric | hard rectangular plates breaking the rounded pawn silhouette |
| Heavy | allowed to break the one-tile footprint | still allowed to break it — drawn wider than its tile |
| Runner | mid-stride, forward-leaning | legs scissored mid-stride where every other pawn stands square |
| Tracker | underplayed | underplayed — the tell is behaviour, not the body |

## What decides it

Pick A/B/C from the screenshot fixtures (day, night, indoors, combat) with the candidate art
dropped in — legibility and layout, not pixel identity, per the docs/31 R4 practice. The
decision gates nothing in Milestone 2; the slice ships on the baseline either way.
