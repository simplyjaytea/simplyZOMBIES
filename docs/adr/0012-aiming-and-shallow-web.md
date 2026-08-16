# Post-M2: aiming sway + shallow skill web

ADR 0011 shipped. This ADR locks the **next** builder epic: felt aiming (docs/09) and a shallow six-region skill web (docs/08 / docs/23). One PR. Do not re-grill 0001–0011.

**Status:** accepted

## Destination

1. **Aiming/sway** — Raise→Steady already exists. Persist a half-angle that tightens while still and opens on move/exhaustion/hurt arms; presentation draws weapon sway from that angle. No hit %, no accuracy reticle.
2. **Shallow web** — ~12–18 nodes across six regions (Melee, Ranged, Medicine, Craft, Survival, Endurance). Points from doing; Focus Auto/Fighter/Worker/Medic/Scout auto-spend along a fixed path. Dies with the person. No keystones in this PR.

## Still out (need later ADRs)

Weather/rain, succession (ADR 0010 stands), Farm/Hunt/Water/Craft/Modify/Butcher/Clean/Firefight/Bury as real Jobs, loadout upkeep, full ~60–100 web, relationships/grief.

## Gates

| Gate | Asserts |
|---|---|
| `godot:m2:aim` | Cone half-angle tightens on Steady; widens when moving; sway readable from sim state |
| `godot:m2:web` | Kill/haul earn region points; Focus auto-allocates; node modifiers apply |

## Consequences

- Builder reads 0012, implements, ships one PR with both gates.
- Issue #32 wayfinder paste: `.scratch/simplyzombies/issue-32-body.md`.
