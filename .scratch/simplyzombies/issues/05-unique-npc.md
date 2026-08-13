# 05 — One unique NPC as framework for future

Type: prototype
Status: resolved
Blocked by: 02

## Question

Q1 wants "maybe one unique NPC as framework for the future" — a single hand-authored survivor that proves the pipeline for future unique survivors without building the full trait/backstory generator.

- Who is the NPC (name, backstory hook, stat skew) that demonstrates bounded aptitudes and fixed-budget tradeoffs from stats MVP?
- What does unique vs procedural mean in data: `godot/content/` schema for unique survivor, how it differs from generated pool, where it lives, hot-reload behavior?
- Behavior: does NPC haul/construct/doctor with priority selection, or is alpha behavior "follow + fight + guard" stub? When do CHA/WIS matter?
- Presentation in iso pixel art: paperdoll + condition view integration, dialogue/bark shape (if any) — no branching narrative in alpha?
- Succession/death: is NPC permadeath with same bite/infection rules? What does losing them cost vs generic recruit?
- Prototype artifact: a stub JSON + in-game spawn + paperdoll entry to react to. Framework must allow adding N more uniques without code change.

Decision + linked prototype asset under godot/content/ or .scratch prototype dir.

## Answer

**Grilled 2026-08-13 — picks: 1A · 2A · 3B · 4A · 5B · 6B.**

### Who: Mara Okoro — clinic nurse (failed pharmacy student, grown)

- **CON 7 / STR 3 / DEX 5 = 15** — fixed-budget proof from 02 (3–8, total 15). No one high in all six; CON slows infection (`inf_factor 0.90–1.15`) + bounded injury tolerance, STR 3 hurts carry (19 kg) + grab escape (~0.55 vs 1 shambler) which the player feels immediately. Teaches "bodies cheap, people expensive" (doc07) — losing Mara costs weeks Medicine progress.
- Head start: Medicine bias (reads wounds better than untrained tier — doc05 diagnosis table) + basic treatment capability, not a free cure.
- Liability: **Squeamish + Light sleeper + Steady hands** (3 traits, conflict-safe; Steady hands offsets Squeamish on treatment per doc07 trait table). Genuine drawback: mood penalty on corpse/treatment, worse rest recovery — shapes how you use her (not a front-line hauler). Bounded +1/-1 compensations already accounted in budget.
- Prototype: `godot/content/survivors/uniques/mara.json` — hand-authored, static, build-defining strength with real drawback (doc07 unique rule).

### Data: unique vs procedural

- **Separate uniques folder** (pick 2A): `godot/content/survivors/uniques/<id>.json` — own schema `survivor.schema.json` (`id: survivor.unique.<name>`, `name`, `backstory`, `age`, `appearance{features,portrait}`, `traits[2-4]`, `aptitudes{str,dex,con}` validated sum 15, `kit[item.*]`, `focus`, `jobPriorities`, `spawn{kind,day,locationHint}`, `barks`). Distinct from generator pools — uniques never draw from weighted name/trait tables, procedurals never read this folder.
- Same `aptitudes` component + `SimModifiers` pipeline as 02 (no new singleton, `Directory` in `ComponentStore`, round-trips save/load, missing keys default 5 for upgrade path).
- **Add N without code change:** drop new `*.json` in `uniques/` — loader walks directory (docs/20:166 mod-ready), registry validates, hot-reload re-runs seed (docs/30 hot-reload rule). No CONTENT_TYPES change once `survivor` type registers.
- `ponytail: register "survivor" CONTENT_TYPE + wire validator to godot/platform/content_validator.gd and sim/content/registry.ts; upgrade path is adding CHA/WIS/INT keys when 3A ships.`

### Behavior (alpha): Grid-lite

- **Stub + one priority row:** follow player + fight (Fighter/Medic Focus) + guard position proves framework; plus `Doctor 1 / Guard 2 / Rest 3` using existing 17 job columns (doc07 work grid) proves job selection without building full allocation. Focus auto-allocates minors/notables only, never keystone/aptitude (doc08 rule).
- CHA/WIS deferred per 02 — no relationship/faction effect in alpha. When they ship, same modifier pipeline.
- No haul/construct/doctor full grid in alpha — deferred to slice with building.

### Presentation

- Same paperdoll (doc05: color never fill, four states unhurt/hurt/badly hurt/unusable, prose skill-scaled). Unique portrait sprite + nameplate tint distinguishes Mara without new screen; condition view inherits ambiguity (bite→scratch 30% presentation still).
- Barks: 6–8 short lines (`onSeen`, `onHurt`, `onBite`, `onIdle`) — no branching narrative in alpha (doc07 unique sketches are tone, not dialogue tree). Iso pixel art: portrait is iso-consistent, paperdoll outline unchanged; glimpses use anonymous shape per doc30 (no facing leak via silhouette).

### Death / succession

- **Same bite/infection rules as procedurals** (85% transmitted, 30% scratch, CON 0.75–1.25 — doc06) + permadeath. Cost: weeks Medicine investment + grief mood (pairwise, scaled by closeness — doc07 relationships) + lost medkit kit. Unique flag: **one chance, never respawns** (pick 5B) — finding Mara feels like finding a named weapon (doc07). No inheritance, no respec (doc08).

### Spawn (alpha)

- **Director beat day 1, barricaded annex** (pick 6B): `spawn{kind:"director_beat", day:1, locationHint:"defensible building annex — barricaded exam room"}`. Director-gated, not fixed loot tile — proves director beat pipeline for uniques (doc07: director/faction events only) while staying deterministic per seed. Fixed-tile fallback is one-line swap to `fixed_tile` if playtest wants fixture stability.

### Prototype artifact

- `godot/content/schemas/survivor.schema.json` + `godot/content/survivors/uniques/mara.json` — both hot-reloadable; invalid edit shows HUD `content:` line, doesn't crash run.
- `ponytail: Godot sim still needs "survivor" CONTENT_TYPE registration + ContentValidator schema load + spawn hook in director/world; this is spec + content, not wired runtime yet. Next builder wires those three lines.`

---

## Notes

- Docs: 07-survivors.md, 23-roadmap.md (unique survivors deferred), 05-health-injury.md (condition view), docs/30-decisions.md sunk costs.
- Blocks on stats MVP (aptitudes).
- HITL prototype — needs human reaction to rough take.
