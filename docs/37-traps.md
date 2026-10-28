# Traps

Each of these cost someone a session. Read them before touching the sim. Moved out of CLAUDE.md
on 2026-10-19.

## Traps that have already cost someone a session

Each of these was found the expensive way. They are not style opinions.

- **Packed arrays are values in GDScript.** `(dict["key"] as PackedStringArray).append(x)` appends
  to a *copy* and silently does nothing. This made a four-seed harness report four identical runs.
  Use a plain `Array` for anything you mutate through a Dictionary.
- **A survivor's body parts do not share a scale.** A healthy head is 15, a hand 10, a torso 40 —
  so `body[part] < 15` means "critically injured" on a torso and "perfectly fine" on a head. There
  is exactly one place that normalises: `SimHealth.part_state`, which returns
  Unhurt/Hurt/BadlyHurt/Unusable. Compare states, never raw integrity.
- **`entity.killed` fires more than once for the same individual** — `health.gd` on a destroyed
  head, `infection.gd` on a put-down and again on turning. Counting events counts one death three
  times. De-duplicate by entity id.
- **The content validator will not catch a nested key.** It checks top-level types only. A wrong
  key inside an `armor` block sat in `item.wrap.cloth` for weeks giving zero arm protection, and
  only a purpose-built gate found it. **Reproduced deliberately on 2026-09-12** by the warmth
  slice's sabotage pass, in a brand-new block: a `warmth` map naming a body part that does not exist
  passed `npm run godot:validate` with `GODOT_CONTENT_OK`, and only `check_m2_warmth.gd` refused it.
  That is the whole argument for a purpose-built gate per nested shape, demonstrated rather than
  asserted.
- **But the frozen TypeScript oracle validates the same content with Ajv, and Ajv *does* recurse.**
  The two validators read one shared tree under `godot/content/`, and they disagree about depth:
  `npm run godot:validate` passes a nested violation that `npm test` rejects with a hard
  `ContentError`. So a content edit is not verified until **both** have run — a new enum value, a
  new nested key, anything under `content/schemas/`. This cost a red CI on a change where
  `godot:validate`, `godot:m2` and a purpose-built gate were all green: the map schema's
  `loot[].table` enum still listed two locations and the oracle refused the third.
- **`velocity` uses `dx`/`dy`; `position` uses `x`/`y`.** Writing `vel["x"] = 0.0` adds a key
  nothing reads and raises nothing — a pin that silently does not pin. `shambler.pin` and
  `treatment.pin` are the precedent for both the phase slot (`movement`, order −1) and the names.
- **`events.publish()` only queues; handlers run at `drain()`, at the *end* of `world.step()`.**
  So a fixture that publishes an event and then reads the result without stepping sees nothing
  ("2 hits, 0 wounds" cost a while), and an event published *into* a tick lands after that tick's
  systems have already run — a stagger arriving on the tick a channel completes is genuinely too
  late to stop it. Both are correct behaviour; write the test around them rather than tolerating a
  fudge factor inside the measurement.
- **GDScript lambdas capture primitives by value.** A closure assigning to an outer `int` or
  `bool` mutates its own copy, so an accumulator written inside an event handler reads back
  unchanged. Use an `Array` or `Dictionary` — reference types — for anything a handler accumulates.
  Same family as the packed-array trap above. This one keeps being paid for: it most recently made
  a jam gate report "never cleared" for a jam that had cleared exactly on schedule, because the
  `cleared_at` an event handler assigned to was a captured `int`. The failure mode is the worst
  kind — the gate goes red and blames the code under test.
- **Diagnose the balance harness, do not theorise at it.** Two consecutive guesses at why a flag
  flip wiped colonies (blood loss; then NPCs having no way to treat themselves) were both wrong,
  and each cost a full harness run to disprove. A throwaway `SceneTree` driver that boots
  `SimBoot.playable(seed, …)`, runs the same day count and prints `entity.killed` causes answers it
  in one run. Delete the driver afterwards.
- **A Dictionary keyed by an entity id does not survive a save.** Components round-trip through
  JSON, and JSON has no integer keys — a `{entity: record}` component comes back with String keys
  and the very first `seen[entity]` after a load misses silently, with no error and no wrong
  number, just a memory that is empty for reasons nothing reports. Store per-entity collections
  as an **Array of records** (`{"e": id, …}`) and scan; `sim/modules/sightings.gd` is the
  precedent. Same family as the packed-array and lambda-capture traps above: a value that is
  quietly not what you stored.
- **`entities.despawn` does not remove components, and `components.query` does not check alive.**
  Despawning a body leaves every one of its components in place, so anything counting a population
  by `query` still counts it. This made a director harness report "56 quiet nights in a row" --
  the culled bodies still filled `LIVE_CAP`, so every night after the fourth was refused rather
  than drawn. Remove the component you are counting, not just the entity.
- **`Array.erase()` and `Array.find()` on Dictionaries match by *value*, not by reference.**
  Measured in 4.7.1: with `a` and `b` two different Dictionaries holding identical content and
  `arr = [a, c, b]`, `arr.find(b)` returns **0** and `arr.erase(b)` removes **`a`**. So an array of
  records — a wound list, a sighting list, anything keyed by content rather than by id — cannot be
  edited by handing the element back. Find the index yourself on a field that is unique, or give
  the records an id. `wounds.gd`'s closing loop is safe only because two value-identical wounds
  necessarily close on the same tick; one added field away, it would not be.
- **A `has_method()` guard naming a method that does not exist is silently false forever.** It
  raises nothing, logs nothing, and quietly turns the whole branch into a no-op — `world.despawn`
  guarded its modifier cleanup on `has_method("removeScope")` against a method called
  `remove_scope`, so no despawned entity ever had its modifiers cleared and every save carried
  them. GDScript's `has_method` does **not** convert between snake_case and camelCase for script
  methods. Same family as `vel["x"]`: a name that looks right and reaches nothing. If you write
  one, grep for `func <name>(` before you trust it.
- **A `static var` is shared between the two worlds a gate boots.** docs/30 records this twice for
  components (`putDown`, `mourned`) and it was still live in the kernel: `SimBoot` kept "the last
  world that called `attach_kernel`" in a static, and the attention handlers wrote into *that*
  world's field rather than the publisher's. World A published magnitude 500 and A's own field read
  0.0000 while world B's read 500.0000 — on the spine, under every two-world assertion about noise
  or scent. Per-world state belongs on the world or in a closure over it; a closure over an object
  is safe, because the lambda-capture trap above is about primitives.
- **`main.gd` matches on the tile class twice, and a textual gate that reads the first arm judges
  the wrong one.** `_draw_district` has a `match tile:` that picks a *colour* and a second one that
  *draws*, each with its own `SimTileMap.Tile.Low:` arm. A gate slicing from the first label found
  four lines of colour arithmetic and reported that the draw loop never asks whether a vehicle
  covers the tile — red, and blaming code that was correct, which is the worst thing a gate can do.
  Enumerate every arm and pick the one calling the draw helper; `check_wrecks.gd`'s `_low_arms` is
  the precedent. Same family as proving a scanner on a fabricated body before trusting it: a
  textual assertion needs to be shown it is reading what it thinks it is.
  The 2026-10-03 water repair is the stronger boundary precedent: `check_water.gd` isolates
  `_draw_district`, its two tile matches and each Water arm by indentation, ignoring comments.
  A fixed 4,000-character window broke when valid wall code grew before the water fill; merely
  scanning farther would let another branch's fill hide a missing one. Its positive and negative
  scanner fixtures exercise both failure modes.
- **`sum()` of floats is not the same number on every CPython.** 3.12 sums floats with
  compensated (Neumaier) summation and 3.11 does not, so `sum((0.10, 0.45, 0.30))` is exactly
  `0.85` on one and `0.8500000000000001` on the other. Multiply either by an integer count and a
  result that lands on a **half** goes opposite ways, because `round()` breaks a true half *to
  even* and only one of the two inputs is a true half. This turned `sprites:check` — a byte
  comparison — red on CI over one pixel of a raider's boot, against art that was correct on the
  machine that drew it, and it cost two wrong hypotheses (reach near-ties; hash-order
  dependence, `PYTHONHASHSEED` swept) before the third was found by rendering under both
  interpreters side by side. Anything whose output is compared byte for byte must not decide a
  boundary with float arithmetic: use whole percents and integer division, as
  `palette.tone_ceiling` now does. These containers ship Python 3.11 and CI takes whatever the
  runner image has (3.12 when this was found) — the engine is pinned exactly and Pillow is
  pinned to 12.3.0, but the interpreter is not, so this class of divergence is invisible locally
  until CI says so. Pinning Python was considered and not taken: a generator that renders the
  same bytes on any interpreter is worth more than one that is only ever run on one.
- **A CRLF checkout turns textual gates red against correct code.** With `core.autocrlf true`
  (the Windows default) every working file ends its lines in a carriage return, and a gate that
  matches a whole source line exactly never finds it: on 2026-09-26 `godot:m2:dormant` failed on
  a clean `main` with "the isolator found no Seek arm". The repository's `.gitattributes` now pins
  `* text=auto eol=lf`, so a fresh clone is LF everywhere; an older checkout needs
  `git config core.autocrlf false` and a fresh checkout (`git rm -rq --cached . && git reset
  --hard`, with any work stashed first).
- **A clean git merge can leave a content object with the same key twice.** On 2026-09-26 one
  branch added `"appearance": {"sprite": …}` above an item's `equipSlot` and another added
  `"appearance": {"equipSprite": …}` below it; git saw two different hunks and merged both without
  a conflict. Every JSON reader here, Godot's and Ajv's alike, keeps the *last* duplicate without a
  word, so `godot:validate` and `npm test` were green while the item had silently lost its icon —
  only `godot:check:authored`'s READS lane noticed, because the art it declared was now read by
  nothing. After merging branches that both touched `godot/content/`, scan for duplicate keys
  (Python's `json.load(..., object_pairs_hook=...)` sees them) before trusting a green validator.
- **A tile written before the dressing moves every tree on the map.** `_dress_terrain`
  (`godot/sim/map/worldgen.gd`) draws one jitter from the `terrain` stream per outdoor Floor tile,
  so a change that turns one Floor into anything else *before* the dressing runs takes a draw away
  and shifts every tree, thicket and grass disc decided after it, on every seed and size. The first
  cut of the gate-gap door (2026-10-28) did exactly that from `_write_doors`: the gates stayed green,
  the record claimed the 64 world was byte-identical to main, and a side-by-side boot of the two
  branches found fifty moved tiles at 64 and hundreds at 256. A generator change that must leave
  the dressing alone runs after it (the gap door runs last in `generate`), and the claim is checked
  by hashing `map.tiles` on main and on the branch, not inferred from a green gate.
- **Throughput, measured:** the shipped world measured **34 ticks/second** headless (docs/22,
  "Remaining milestone evidence", 2026-10-03), so a game day (72,000 ticks since the one-hour day
  of 2026-10-19) is about 35 minutes and a no-wipe ten-day campaign (693,000 ticks) about 5.7
  hours. (Before the one-hour day this line said 288,000 ticks and 22.6 hours.) The ~1,085 ticks/second figure
  is the 64-tile district harness, not the world; do not use it for world estimates. Anything
  phrased as "run a few campaigns" is an overnight job — check the arithmetic before promising a
  grid.

