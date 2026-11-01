# First-person Reports page

The ledger gets a Reports page: what happened at the colony while the player was away, in the
chronicle's own words. Presentation only. No file under `godot/sim/` changed, and the page writes
nothing to the world.

## Sources

Every line on the page is `SimChronicle._line_of(world, record)`, the line builder the HUD's world
column and the run-over screen already read. `godot/ui/reports_panel.gd` adds no text of its own
except the labels the brief asks for: "Reports", "since you last looked", "new", "No reports.", and the
chip's "reports". No day counter is shown: the top-down chronicle shows no day, and the page follows it.

## The page

- `ReportsPanel.rows(world, read)` is pure. It walks `world.chronicle` newest first, skips a record
  whose line is empty, and returns `{text, new}` rows. A record is new when its index is at or past
  `read`. The page shows at most `REPORTS_MAX` (12) rows.
- `ReportsPanel.unread(world, read)` counts every record past the mark, not only the rows the page can
  show. The prompt reads this.
- The page is built from the chronicle's font and the chrome helpers (`Chrome.panel`, `Chrome.header`,
  `Chrome.font`, `Chrome.LADDER` sizes 25 and 20), so `godot:check:ui_skin` holds. New rows are drawn in
  the accent colour with a "new" tag (`Locker.chip`), and a single line "since you last looked" heads the
  block when any row is new.
- `ReportsPanel.Chip` is the button on the ledger. It is drawn with `Locker.button` and emits `activated`
  on a left click.

## Read state

`first_person.gd` keeps `_reports_read`, the chronicle index read up to. Opening the page shows the rows
against the old mark, then moves the mark to the end of the record. The mark is presentation state. It
starts at 0 on every boot, and nothing writes it to the sim. The save and load pieces are not on this
branch, so there is no reset on load to describe.

## Prompt and keys

- While the record holds entries past the mark, the ledger's prompt reads
  `E read the ledger, new reports`. Otherwise it reads `E read the ledger`. The prompt is the ledger's
  only, so it appears only when the ledger is in reach and aimed at.
- Escape goes Reports -> work grid -> street, as the Skills web does. The work grid takes no keys while
  the page is up. Closing the ledger hides the page.

## Gate

`npm run godot:check:first_person`, the REPORTS lane:

- The prompt is the plain one with nothing new (the mark is set to the end of the record as a fixture).
- A survivor's death is published as `entity.killed` on the event bus, the event `health.gd` publishes when
  a head is destroyed. The sim's chronicle writes a "died" record for it.
- The prompt then reads `E read the ledger, new reports`.
- E opens the ledger. A real left click on the chip opens the page. The page shows the chronicle's
  `<name> is dead.` marked new.
- True negative: every row on the page is a line the chronicle holds, found by `_line_of` against the
  records, and no row has a digit.
- Reading moved the mark to the end of the record. The first Escape returns to the work grid, and the
  second leaves the ledger for the street. The prompt then does not ask about reports.

Mutation-tested, each reverted after the run:

| Change | Result |
|---|---|
| Opening the page does not move the read mark | `REPORTS: reading the page did not move the read mark to the end of the record` |
| The prompt never asks about new reports | `REPORTS: the prompt did not ask about new reports after a death` |
| Escape from the page leaves the ledger | `REPORTS: Escape from Reports left the ledger or the page up` |
| Rows carry an extra character (an invented line) | `REPORTS: the page shows a line the chronicle does not hold: ...` |

## Verified

- `npm run godot:check:first_person`: `FIRST_PERSON_OK`.
- `npm run godot:check:ui_skin`: `UI_SKIN_OK`.
- `npm run godot:check:hud`: `HUD_OK`.
- `npm run godot:smoke`: exits 0.
- `npm run check:routing`: `ROUTING_OK`.

## Not in this piece

- The page shows the 12 newest entries. Older ones stay in the record and are not paged to.
- The run's epitaph has its own reader (`SimChronicle.epitaph`), and no page shows it.
- The read mark is not saved and not reset on load (no save piece on this branch).
- The gate does not run a death itself. It publishes the event the sim publishes when a head is
  destroyed, so the body stays alive. The chronicle's handling is the real one.
- The chip's place is top right of the screen, chosen so it does not cover the work grid's own buttons.
  No headed screenshot was taken, so the placement is unchecked on screen.
