## Destination

Locked planning + **shipped** Milestone 2 people-and-economy vertical: Needs (hunger/thirst/rest/mood/temperature/hygiene), Jobs + Need seek, survivor generator, gate recruits + Inspect, corpse vs turn + Leave, save v12. Hand off via ADRs 0001–0011 and gates `godot:m2:save|needs|jobs|recruits`.

## Notes

- **Domain:** Hardcore colony survival; attention field (noise/scent/light). Docs 00–31 + `docs/adr/*` are source of truth.
- **Engine:** Godot 4.7.1 playable build; TypeScript oracle at `ts-oracle-final`.
- **Mode:** Planning for this map is **complete**. Execution of 0001–0011 merged (PR #50 + Bugbot #51). Do not re-grill locked ADRs.

## Decisions so far

- ADRs [0001](docs/adr/0001-need-meters.md)–[0011](docs/adr/0011-first-implementation.md) accepted and shipped.
- Ticket 10 fortify/director folded into save v12.
- No succession this slice (ADR 0010): player death ends the run.
- Bury = Haul-to-dump; stub Work columns do nothing when raised.
- Corpse haul dumps outdoors; Need seek wakes Rest (PR #51).

## Building now / frontier

**Empty for M2 people-and-economy.** Next product epic (not this map’s destination):

1. Aiming/sway felt cone (docs/09) — no hit %.
2. Shallow six-region skill web ~12–18 nodes + Focus auto-spend (docs/08, docs/23).
3. Then: loadout upkeep / Modify / Repair (need thin ADRs).

Still deferred without new ADRs: weather/rain, succession, Farm/Hunt/Water/Craft/Butcher/Clean/Firefight as real Jobs.

## Not yet specified

- Exact shallow-web node list + point rates (content ADR).
- Sway/cone numbers for aiming presentation.
- Repair / Modify / Clean earliest Job loops.
- Weather-lite vs full weather (ADR 0002 still rejects rain for the Needs slice).
- Succession lift (requires web + relationships per ADR 0010).

## Out of scope (this map)

- Multiplayer (Milestone 3C)
- Z-levels, vehicles, factions, full world decay / mutation waves beyond alpha roster
- Full ~60–100 node web (Milestone 3A)
