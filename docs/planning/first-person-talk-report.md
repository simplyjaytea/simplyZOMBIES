# First-person conversation: one of your colonists

The first slice of docs/39's conversations: look at one of your own colonists, press E, and they tell
you, in words, how they are and what they are doing. No new mechanics -- every line is a read model
the top-down screens already show. Presentation only: nothing under `godot/sim/` or `godot/content/`
changed, and the panel writes nothing to the world.

## What landed

- `godot/ui/talk_panel.gd`, a `Control` in the kit chrome (`Chrome`/`Locker`, the same as the
  Reports page and the work grid):
  - **Name.** `identity.name`, the name the Colony drawer and the HUD use, as the header.
  - **How they feel.** One line that combines two read models:
    - `SimCondition.view`'s worst part, in the first-person HUD's own words: `hurt`, `badly hurt`,
      `barely standing`, and `bleeding` when a wound is open. A healthy body contributes nothing.
    - `SimNeeds.worst_band` picks the worst need band. If `content/speech/lines.json` has a
      `speech.mutter.<band>` entry, one of its first-person lines is used ("I could eat."). Otherwise
      the read model's own panel sentence is used (`SimNeeds.hud_clause(world, ent, true)`, e.g.
      "Mara looks hungry."). A body with nothing wrong says "I feel steady.", the first-person HUD's
      own fallback for an empty needs clause.
    - The two are joined when both exist: "I'm hurt. I could eat." The mutter line is chosen
      deterministically by entity, so a conversation does not change its sentence every frame.
  - **What they are doing.** `WorkRead.doing` (`sim/work_read.gd`), the Colony row's own phrase, drawn
    after the same `now ` lead the work grid uses. Idle, a job, a need's errand, an order, a hold or a
    crisis: whatever that read model says.
  - **One action.** `Goodbye` (Escape, or a click on the button). Nothing else: no orders,
    recruitment, delegation or foreman. docs/39 keeps the foreman undecided and this slice keeps it
    out. The ledger is physical, so "open the ledger on <name>" is deliberately not offered.
- `godot/presentation/first_person/first_person.gd`:
  - **E's ladder.** Ledger, then an openable container, then a colonist in reach and on the aim, then
    the tile verb (a door or window), then the refusals. Inserting the person above the verb is the
    order the task names; a door in reach no longer wins over a person you are talking to.
  - **Reach and aim.** 1.8 m from the sim's position (the ledger's reach), the ledger's aim cone, and
    the sim's own `vision.detail` for a wall. The ray starts at the camera's eye (`_eye_m`, itself
    `SimSpace.eye_of` of the player's posture) and ends at the colonist's own `SimSpace.eye_of` point.
  - **Who is talkable.** `SimAllegiance.is_colony`, an `identity` (a name), alive, not a corpse, not
    the player, and not a shambler. A raider and a settler have an identity and are not the colony; a
    zombie has no allegiance component and would otherwise read as colony, so the zombie check is
    explicit too.
  - **Prompts and refusals.** `E talk to <name>` when the person is in reach and on the aim. In reach
    but not aimed at: "Turn to <name>.", ranked after the container's own away line. Refusals on E
    say which rule failed, in the ledger's words: out of reach, behind a wall, or near but not looking
    at them.
  - **Capture.** The panel swallows every key: walking, the aim, the fight buttons, the stance ladder
    and the save keys never reach the world. Escape closes it and recaptures the mouse. The clock
    keeps running -- the inventory's reversible default (docs/33 leaves the pause policy open): the
    body is stopped with `_clear_held` + `_push_zero_move` and nothing pauses. A click on the panel's
    Goodbye button is the same close.
  - **While it is up.** The HUD is hidden (the panel carries the words) and the panel re-reads the
    models every frame, so a need or an injury that changes while the player listens is said as it is
    now. A colonist who dies or stops being talkable closes the panel. Succession and the end panel
    close it like the ledger and the inventory.
  - **The scene API the gate reads:** `talkable`, `talk_target`, `talk_verdict`, `talk_focus`,
    `talk_in_sight`, `open_talk`, `close_talk`, `talk_panel_node`, and the `talk_open` flag.

## The gate

`npm run godot:check:first_person` gains a TALK lane and prints `FIRST_PERSON_OK`:

- True positive: a healthy, fed colonist placed in reach and aimed at, E opens the panel with the
  sim's `identity.name`, the `I feel steady.` line and exactly `WorkRead.doing`'s phrase; every line
  the panel draws is digit-free; W moves the body nowhere while it is up; Escape closes it and
  recaptures the mouse. A hungry colonist then says one of the `speech.mutter.hungry` content lines.
- True negatives: a colonist out of reach, one the look is turned away from, one through an opaque
  wall (the verdict reads `blocked`), a shambler and a raider all open no panel.
- The lane restores the colonist's needs, body and injuries, and is staged before the ANIM lane so the
  colony still has its people.

## Not in this piece

- No orders, recruitment, delegation or foreman; Goodbye is the only action.
- No new speech content: the mutter lines already exist in `godot/content/speech/lines.json`.
- The panel does not stop the clock; the inventory's pause policy default is copied.
- A colonist cannot start a conversation; only the player can. Their own greetings are later.
- No portrait, no voice, no animation: the panel is words and chrome.
