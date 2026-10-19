# Gates

The full gate list, its timings, and what CI runs. CLAUDE.md's Verifying a change section holds the
policy; this file holds the commands. Moved out of CLAUDE.md on 2026-10-19.

## The gate list

Correctness for a Godot change is the Godot gates. **Policy (decided 2026-10-19, docs/30):** before a commit, run the gates for what the change touched:
its `godot:m2:<name>` lanes, `godot:smoke` and `godot:validate` for a boot or content change, `godot:check:play`
for a scene or input change, `npm test` for anything under `godot/content/`. The full `npm run godot:m2`
chain runs in CI's `godot-m2` job on every pull request and every push to main, and nothing merges red.
A change to a shared sim module or the save format still runs the full chain locally before its commit. The
latest full cloud run took **47m16s for 85 gates** (2026-10-03,
`GATE_TIME_TABLE` total 2835.79 seconds), including **15m29s** for the fast balance tier.
Timings depend on the machine: 30m06s for 84 gates was
measured 2026-09-27 on a four-core Windows desktop, with two worker slices running beside it;
31m29s for 83 gates the day before; 26m45s for 69 gates on a project container on 2026-09-12. It
said twelve here for eight days, measured 2026-09-04 when the chain was 51 gates; the alpha-roster
arc added four gates and took the roster from 152 bases to 362, and a catalogue gate's cost scales
with the roster. Budget for the real
number — an instruction to run a twelve-minute command that actually takes twenty-seven is how a
pre-commit check quietly stops being run:

```bash
npm run godot:smoke      # project boots            → GODOT_PROJECT_SMOKE_OK
npm run godot:validate   # content registry
npm run godot:test       # R1 parity vs the frozen fixture
npm run godot:m2         # all Milestone 2 gates    → M2_LETHALITY_OK et al
npm run godot:m2:balance # the balance harness, fast tier → M2_BALANCE_OK (~15 min here, in godot:m2)
npm run godot:m2:sight   # sightlines and memory     → M2_SIGHT_OK
npm run godot:m2:attach  # attachment slots          → M2_ATTACH_OK
npm run godot:m2:ammo    # calibers, and what a round changes → M2_AMMO_OK
npm run godot:m2:hands   # bare hands, never actually empty  → M2_HANDS_OK
npm run godot:m2:wounds  # severity, the bleed clock  → M2_WOUNDS_OK
npm run godot:m2:treatment # pressure and bandaging   → M2_TREATMENT_OK
npm run godot:m2:medicine  # supply grades: antibiotics, painkillers, a cure for illness → M2_MEDICINE_OK
npm run godot:m2:filter    # what a mask keeps out of a bloater's cloud → M2_FILTER_OK
npm run godot:m2:materials # what a recipe is made of, by kind → M2_MATERIALS_OK
npm run godot:m2:transform # what a thing cooks, boils or purifies into → M2_TRANSFORM_OK
npm run godot:m2:noise     # a device you wind up, put down and pick back up → M2_NOISE_OK
npm run godot:m2:comfort   # something for your own morale that is not a meal → M2_COMFORT_OK
npm run godot:m2:teach     # a book, read once, bounded by what practice pays → M2_TEACH_OK
npm run godot:m2:warmth    # insulation per part, wet, cooling, and what sheds rain → M2_WARMTH_OK
npm run godot:m2:light_burn # a lamp runs out, a headlamp lights, a floodlight stands → M2_LIGHT_BURN_OK
npm run godot:m2:armor     # armour slots, and coverage that stops a blow → M2_ARMOR_OK
npm run godot:m2:recovery  # healing, and what is permanent → M2_RECOVERY_OK
npm run godot:m2:splint    # the splint, and the limp a bad fracture leaves → M2_SPLINT_OK
npm run godot:m2:raiders   # the band at the gate       → M2_RAIDERS_OK
npm run godot:m2:vehicles  # the parked cars and bikes, driven → M2_VEHICLES_OK
npm run godot:m2:weather   # the sky has kinds: seasons, wind, the shift → M2_WEATHER_OK
npm run godot:m2:storm     # noise masked, lightning, outdoor work refused → M2_STORM_OK
npm run godot:m2:cold      # the cold snap's pantry, the snow's cover     → M2_COLD_OK
npm run godot:m2:heat      # the hot clock, heatstroke, thirst, rot       → M2_HEAT_OK
npm run godot:m2:fog       # sight collapsed both ways, one content number → M2_FOG_OK
npm run godot:ban:healthbar  # the health-bar ban   → BAN_HEALTH_BAR_OK
npm run godot:check:appearance # the sprite pipeline → APPEARANCE_OK
npm run godot:check:hud      # HUD speaks in prose   → HUD_OK
npm run godot:check:play     # the gate that plays it: boots the scene, presses keys → PLAY_OK
npm run godot:check:context  # the right-click menu, and walk-here → CONTEXT_OK
npm run godot:check:speech   # speech bubbles: a line said, and who says it → SPEECH_OK
npm run godot:check:respond  # the antibiotics word  → RESPOND_OK
npm run godot:check:camera   # smoothed follow, shake → CAMERA_OK
npm run godot:check:light    # sight-derived wash, lit ∩ seen pools → LIGHT_LOOK_OK
npm run godot:check:memory   # the afterimage, and the remembered map dimmed → MEMORY_LOOK_OK
npm run godot:check:road     # street manifest, paint, palette, rubble → ROAD_LOOK_OK
npm run godot:check:water    # deep water solid and clear, the ford slow and loud → WATER_OK
npm run godot:m2:region      # four districts in one space, each identical to itself → M2_REGION_OK
npm run godot:check:wrecks   # parked vehicles, heaps, debris art → WRECKS_OK
npm run godot:check:weather  # the sky per kind, snow cover, the flash → WEATHER_OK
npm run godot:check:roof     # wall caps and faces, roofs cut out where seen → ROOF_LOOK_OK
npm run godot:check:trees    # tall trees in the entity sort, the fade → TREES_OK
npm run godot:check:worn     # gear layers, order and skeleton fit → WORN_LOOK_OK
npm run godot:check:web_look # the skill web drawn as a web, words only → WEB_LOOK_OK
npm run godot:check:ui_skin  # the UI Field Kit, worn → UI_SKIN_OK
npm run godot:check:fx       # the shot is seen: flash, casing, blood, flame, only where seen → FX_OK
npm run godot:r6         # parity, coverage, mutation, soak, bench, validate
npm run godot:run        # play it (DISPLAY=:1 on a headless VM)
npm run sprites:check    # generated art still matches tools/sprites/ → SPRITES_OK
npm run check:routing    # the routing table resolves; every check_*.gd is reachable → ROUTING_OK
npm run check:timing     # the per-gate timing table names every mode the chain ran → TIMING_OK
```

Those are the ones worth naming, not all of them: `godot:m2` chains **85**, and the authoritative
list is the `godot:m2:chain` script in `package.json` (`godot:m2` itself is
`node scripts/m2-chain.mjs`, which reads that list and runs it) — read it there rather than
trusting a copy here, because a copy here is one more thing that drifts. Run an individual gate
with the `godot:m2:<name>` script beside it when you are iterating; run the chain before you
commit. `godot:m2` prints a `GATE_TIME_TABLE` at the end — every gate it ran, slowest first, with
a total — built from the `GATE_TIME` line `scripts/run-godot.mjs` prints after every mode, success
or failure; `npm run check:timing` is the gate that proves the table cannot come up short.

`sprites:check` is the one gate deliberately **outside** `godot:m2`: it needs Pillow
(`pip install pillow==12.3.0`) and that chain stays engine-only and pip-free, so it runs as its
own step in CI's `check` job. Run it after editing anything under `tools/sprites/` or any PNG
that package generates — it re-renders every registry key and compares decoded pixels against
the committed file, so a palette edited without regenerating is a red build.

`check:routing` is the other gate outside `godot:m2`, and the one that judges the desk rather
than the game: it reads the routing table in CLAUDE.md and fails on any path, npm script or
doc anchor that no longer resolves, then asks the dead-socket question of the gates themselves
(every `godot/check_*.gd` reachable from `scripts/run-godot.mjs`, every runner mode reachable
from `package.json`, every `godot:m2:*` / `godot:check:*` / `godot:ban:*` script inside the
`godot:m2` chain or excused by name). Run it after touching any of those four things. Node only,
about a second.

`check:timing` is a third gate outside `godot:m2`, beside it rather than in it: it self-tests
`scripts/m2-chain.mjs`'s per-gate timing table against fabricated `GATE_TIME` lines (never the
real engine) and checks that `godot:m2` still delegates to it and that `run-godot.mjs` still
prints the line the table is built from. Run it after touching `scripts/run-godot.mjs`,
`scripts/m2-chain.mjs` or the `godot:m2:chain` list. Node only, about a second.

`godot:m2` prints `ObjectDB ... leaked at exit` and `resources still in use` *after* it reports
success. That is engine shutdown noise, not a failure — check the `_OK` line and the exit code.

CI runs `godot:m2` in its own `godot-m2` job (45 min) since 2026-09-12; the `check` job (25 min)
runs the TypeScript side (`npm test`, `typecheck`, `lint`, `format:check`), `sprites:check`,
`check:routing`, `check:timing`, `check:runtime-budget`, the smoke, the validator and the R6 gates.
The `performance` job runs `npm run bench` and `npm run bench:frame`.
Touching a `.ts` file or any prettier-covered path means running those too. Legacy
`npm run godot:bench` prints `BENCH_OVER_BUDGET` and still exits 0 on a synthetic workload.
`npm run godot:bench:runtime` measures the real playable world's tick and
`npm run godot:bench:frame` measures the real scene's world-draw CPU work (a display is required).
These commands fail on overruns or invalid evidence. CI enforces their deterministic runner
contract; actual Godot timing enforcement remains open because the product exceeds its targets.
See docs/22. `npm run bench` is the separate, enforced TypeScript benchmark.

A fresh Claude Code on the web container has no engine; `.claude/hooks/session-start.sh`
installs it. To do it by hand: `bash scripts/setup-web-session.sh`. It does **not** install export
templates, so `godot:export` / `godot:smoke:exports` need `SETUP_EXPORT_TEMPLATES=1`.

