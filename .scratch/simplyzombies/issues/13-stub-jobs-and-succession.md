# 13 — Stub Jobs as real work + succession lift

Type: grilling
Status: resolved
Blocked by:

## Question

Early-alpha wayfinder (01–12) and ADRs 0001–0012 are shipped. Map fog still names **stub Job columns** and **succession** (ADR 0010 kept player death as run-end). This ticket picks *what lifts next* so a builder does not invent Farm/Bury/succession by feel.

### Context (locked already)

- **Consumers today:** Haul, Construct, Cook, Doctor (+ Inspect), Rest, Patient (idle injured), Guard (Mara leftover only). Raising a stub column does nothing ([ADR 0011](../../../docs/adr/0011-first-implementation.md)).
- **Stubs (17-column grid, no consumer):** Firefight, Hunt, Repair, Farm, Water, Craft, Modify, Butcher, Clean, Bury. Bury is documented as “Haul-to-dump” for corpses — not a separate Job yet ([ADR 0010](../../../docs/adr/0010-death-corpse-and-leave.md)).
- **Succession:** docs/01 camera handoff + recovery run is design canon. ADR 0010 rejected handoff for the slice playtest. Shallow skill web now exists (ADR 0012) — grief/relationships still thin.

Decision is: which stub Jobs get real work this slice, and whether succession lifts now or stays deferred.

## Grill

### Q1 — Scope of this ticket

- **A.** Jobs only (succession stays ADR 0010: player death ends the run).
- **B.** Succession only (stub Jobs stay stubs).
- **C.** Both in one ticket / one PR epic.
- **D.** Neither yet — park fog; do art bodies or playtest polish instead.

### Q2 — Which stub Jobs become real (if Jobs are in scope)

Pick a set (recommend one letter):

- **A. Colony hygiene:** Clean + Bury (as a real column, not only Haul-to-dump) + Water (fetch/fill bottles from a world source).
- **B. Food loop:** Farm + Hunt + Butcher (+ Cook already ships).
- **C. Workshop:** Craft + Modify + Repair.
- **D. Combat support:** Firefight only (extinguish Campfire / scrap fire).
- **E. Minimal pair:** Bury + Clean only (closes corpse path + hygiene without new resources).
- **F. Custom list** — name columns in the answer.

### Q3 — What “real work” means for a lifted Job

- **A.** Full consumer: find target → A* walk → timed channel → world/inventory mutation + gate in `godot:m2:jobs` (or a new `godot:m2:jobs2`).
- **B.** Thin consumer: walk + one instant mutation; no new content types; extend existing gate.
- **C.** Content-first: author JSON/items/tiles only; AI consumer follows in a second PR.

### Q4 — Succession lift (if in scope)

- **A.** docs/01 lite: on player death, auto-handoff to nearest living survivor (prefer Mara if alive); run continues; gear stays on corpse; no pick UI.
- **B.** docs/01 with pick: pause/chooser among living survivors, then handoff; empty roster → run over.
- **C.** Soft succession: handoff only if ≥1 recruit accepted; else run over (solo+Mara still ends on player death).
- **D.** Keep ADR 0010 — no handoff this milestone.

### Q5 — Save / director impact if succession lifts

- **A.** Save stays single-slot; handoff updates `player` id in the live world; F5/F9 continue the colony after handoff.
- **B.** New save version bump; handoff invalidates mid-death F9 until next autosave.
- **C.** N/A (succession deferred).

### Q6 — Gate shape

- **A.** Extend `godot:m2:jobs` (+ `godot:m2:needs` if Water/Clean touch meters).
- **B.** New `godot:m2:jobs2` / `godot:m2:succession` so failures name the slice.
- **C.** Informational scripts only (print; no CI hard-fail) until playtested.

## Answer

**Grilled 2026-08-16 — picks: Q1:C · Q2:A · Q3:A · Q4:A · Q5:A · Q6:A. Resolved.**

One epic: lift **Clean + Bury + Water** as full Job consumers, and lift **succession** as auto-handoff to the nearest living survivor (prefer Mara).

### Q1:C — Both

Stub Jobs and succession ship together. Weather stays deferred.

### Q2:A — Clean + Bury + Water

- **Water:** walk to a world water source (authored well / outdoor water tile in annex), fill empty bottle into pockets or Stockpile; thirst Need seek can still drink filled bottles.
- **Clean:** wash at water (or Campfire+water if already required by hygiene sources); lowers hygiene dirt / restores hygiene band; dirties only when work says so.
- **Bury:** real column — haul corpse to a dump/grave tile and bury (despawn corpse, clear scent); replaces “only Haul-to-dump leaves a rotting bag” for corpses assigned Bury. Haul-to-dump may remain for overflow if Bury is disabled.

### Q3:A — Full consumer + gate

Find target → A* → timed channel → mutation. Extend `godot:m2:jobs` (and needs assertions if Water/Clean touch meters).

### Q4:A — Auto nearest handoff

On player death: if another living survivor exists, camera/`player` id swaps to nearest (Mara preferred when tied or when she is the only unique). No chooser UI. Gear stays on the corpse. Empty roster → run over (ADR 0010 end path).

### Q5:A — Same save slot

Live handoff updates controlled entity; F5/F9 continue the colony. No version bump required unless serialize shape must name the new player id (prefer reuse existing player field).

### Q6:A — Extend `godot:m2:jobs`

Add Clean/Bury/Water cases + a succession handoff case (or a thin assert in the same script). Failures stay under that gate name.

### Explicitly deferred

Farm/Hunt/Butcher/Craft/Modify/Repair/Firefight · succession chooser UI · grief/morale from docs/01 · weather.

Status: resolved.

## Notes

- Docs: ADR 0003, 0010, 0011, 0012; docs/01 succession; docs/07 survivors; `.scratch/simplyzombies/map.md` fog.
- Code: `godot/sim/modules/jobs.gd` (`COLUMNS`, stub `pass` / `_` stop); death/Leave paths in needs/survivors modules.
- Wayfinder: map “Not yet specified” → this ticket.
