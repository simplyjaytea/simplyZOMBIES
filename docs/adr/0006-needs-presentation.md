# Needs presentation without raw numbers

Same contract as the condition view: sentences, no fills, no pips, no hidden tooltip numbers. The HUD glimpse is one clause at the warning tier; the panel holds the rest.

Lock for [How are needs shown in UI without raw numbers?](https://github.com/simplyjaytea/simplyZOMBIES/issues/38).

**Status:** accepted

HUD: one clause, **worst** Need only, type order thirst > hunger > rest > temperature > hygiene. First person for the player, third for everyone else. Selected survivor only. Floor is the warning tier (pools 40–80 and `a_little_*`), not only soft. `needs.holdMax` is debug, not a player widget.

`a_little_cold` / `a_little_dirty` read as “uncomfortable.” Pools never expose 0–100. Omit a Need from the panel when it is fine (pool >80, `comfortable`, `clean`, mood > −25).

| Need | HUD (worst only) | Panel |
|---|---|---|
| Hunger 40–80 | You’re peckish. | You’re peckish. |
| Hunger soft (<30) | You’re hungry. | You’re hungry — work and aim are off. |
| Starving | You’re starving. | You’re starving. You can’t work. |
| Thirst 40–80 | You’re thirsty. | You’re thirsty. |
| Thirst soft (<30) | You’re thirsty. | You’re thirsty — work and aim are off. |
| Dehydrating | You’re drying out. | You’re drying out. |
| Rest 40–80 | You’re tired. | You’re tired. |
| Rest soft (<30) | You’re exhausted. | You’re exhausted. |
| Passed out | — (they’re down) | Collapsed. Sleeping where they fell. |
| `a_little_cold` | You’re uncomfortable — cold. | You’re uncomfortable — cold. |
| `very_cold` | You’re very cold. | You’re very cold. |
| `a_little_dirty` | You’re uncomfortable — unwashed. | You’re uncomfortable — unwashed. |
| `dirty` | You need a wash. | You need a wash. |
| `filthy` | You’re filthy. | You’re filthy. Don’t cook. Don’t treat. |
| Mood −25 | Mood is turning. | Mood is turning. |
| Mood −80 | They’re going to leave. | They’re going to leave. |

Third-person swaps “You’re” → name (“Mara looks peckish.”).

## Considered options

- HUD only at soft — rejected; the glimpse stayed too quiet for six Needs.
- 4 pips “for scannability” — rejected; pips are a bar with worse resolution.
- Needs tab with bars — rejected; clause 4 and the condition-view ban.

## Consequences

- Condition view still owns injuries; this is a second sentence list on the same selected-survivor panel, not a second body.
- Skill-scaled prose stays an injury feature. You feel your own Needs; there is no examiner skill on this table.
