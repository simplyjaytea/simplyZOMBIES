# First-person GLB art: clean-checkout loading and the M3/M4 fixes

Fixes two findings of the independent art review of PR #275
(`pr275-round1.md`, items M3 and M4). This PR does not contain the art. It lands before #275 so the
art loads when it arrives.

## M3: the GLBs load without the import system

On a clean checkout the repository has no `.import` files, so
`ResourceLoader.exists("res://assets/first_person/desk.glb")` was false, and `assets.gd` silently fell
back to placeholder boxes. The gate passed either way.

- `assets.gd` `load_model(path)` reads the file's bytes with `FileAccess.get_file_as_bytes`, builds the
  scene with `GLTFDocument.append_from_buffer` and `generate_scene` into a `GLTFState`, and returns
  `{node, source}`. `source` is `disk`, `missing` (no file) or `unreadable`. A missing or unreadable model
  gives a null node, and the caller draws the published-size box.
- Every material on a loaded model is set to `TEXTURE_FILTER_NEAREST`, which is nearest filtering with no
  mipmaps, so the pixel art stays crisp. Back-face culling is left as authored.
- `prop_view.gd` uses `load_model` for the desk and ledger. `prop_preview.gd` uses it for all five props.
- `godot/export_presets.cfg`: both presets set `include_filter="assets/first_person/*.glb"`, so the GLBs
  are packed as raw files. They are read at runtime, so they need no import.
- `.gitignore` ignores `godot/assets/first_person/*.import` and `godot/assets/first_person/*_kit_atlas.png`,
  the extracted atlas copies and their import files. It does not ignore the committed GLBs or
  `kit_atlas.png`.

## M4: the preview no longer floats models

`prop_preview.gd` lifted every prop by half its height, a model as well as a placeholder box, so each
GLB hung half its height above the floor. The GLB origins are correct (the floor centre, or the bottom
centre for the ledger). Now only a placeholder box, whose origin is its centre, is lifted; a loaded model
is placed at its authored origin.

## The gate

`npm run godot:check:first_person`, the ART and PREVIEW lanes:

- **ART, with the GLBs on disk.** The playable scene draws `DeskModel` and `LedgerModel`, not the boxes.
  Their world-space boxes match the published sizes within 1 cm (desk 1.20 x 0.78 x 0.62 m, ledger 0.30 x
  0.026 x 0.22 m), the desk's base is on the floor, the ledger's base is on the desk top, and the ledger is
  centred on the desk. Every material is nearest-filtered. True negatives: a planted GLB at half the desk
  size, written through the engine's exporter and read back through the same loader, is refused; a
  linear-filtered material is refused by the same filter test.
- **ART, without the GLBs (a clean checkout before #275).** The lane prints
  `FIRST_PERSON_SKIP ART: desk.glb and ledger.glb are not on disk, ...` and checks that the boxes were drawn.
- **PREVIEW.** Each prop in `prop_preview.tscn` stands on its base: the desk, the shelf, the barricade and
  the wall module on the floor, the ledger on the desk top. This holds whether a prop is a model or a box.
  True negative: a box lifted by half its height (the M4 fault) fails the same floor test.

Mutation tests, each reverted:

| Change | Result |
|---|---|
| Loader skips `_nearest` (linear filtering) | `FIRST_PERSON_FAIL ART: the loaded desk or ledger has a material that is not nearest-filtered` |
| Ledger model raised 0.2 m | `FIRST_PERSON_FAIL ART: the ledger model is ... not the published ... on the desk top` |
| Loaded props lifted by half their height (the M4 bug) | `FIRST_PERSON_FAIL PREVIEW: the preview's desk floats: its base is at 0.390 m, not 0.000 m` |

## Verified

- With the art copied in (not committed) and no `.import` files on disk: `npm run godot:check:first_person`
  prints `FIRST_PERSON_OK` with no skip line, and the run creates no `.import` files.
- With the art absent (the state of this PR): `FIRST_PERSON_SKIP` with the ART line, then `FIRST_PERSON_OK`.
- `npm run godot:smoke` exits 0.
- `npm run check:routing` prints `ROUTING_OK`.

## Not verified

- **The exported build.** A headless `godot --export-pack "Windows Desktop"` was started on the
  worktree with the art copied in. It spent about 30 minutes in the editor's reimport pass, stuck at
  99% on "Executing pre-reimport operations", and was stopped. So the pack is not checked here, and
  the `include_filter` pattern is unproven in a built pack. The first run of the exported build on the
  art PR is the check for it.
- Shelf, barricade and wall module are placed by the preview only. The playable scene reads only the
  desk and the ledger, as before.
