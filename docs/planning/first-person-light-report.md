# Light, night and weather in first person

Day, night, weather and carried light in the first-person scene, read from the sim. Presentation
only: nothing here writes a component or decides what the player can see. The 3D sky follows the
sim's daylight share, the weather kind, fog's sight multiplier and every lamp the sim says is lit
and carried. No sim file changed.

Stacked on `opencode/fp-fight` (PR #280), which carries #278, #274, #271 and #270. Worktree
`fp-light`, branch `opencode/fp-light`.

## What landed

- `godot/presentation/first_person/sky_view.gd` (new):
  - **Tuning block.** Every presentation number is in one labelled block at the top: sun and
    ambient energy and colour at day and night, the overcast grade's saturation/contrast/sun
    multiplier, rain's darkening, fog's begin distance and clear-sight metres, the eye light's
    energy and anchor. The values the sim owns are read, never copied: `Clock.ambient_light_at`,
    `SimWeather.kind`, `SimWeather.raining`, `SimWeather.sight_mul`,
    `SimLightModule.carried_magnitude` / `brightest_carried` / `beam_of` / `light_block_of`.
  - **The sky.** A `WorldEnvironment` with a coloured background, a colour ambient source and the
    overcast grade's desaturation eased in by the daylight share; one shadowless
    `DirectionalLight3D` whose energy and colour lerp from day to night. Rain and storm multiply
    the sun and ambient down and darken the sky; fog turns on depth fog whose `fog_depth_end` is a
    clear 30 m times the sim's `sight_mul` (fog says 0.25, so 7.5 m). No particles and no
    volumetric pass.
  - **The carried light.** The eye's own light is a `SpotLight3D` for a beam (the content's `beam`
    is the half-angle) or an `OmniLight3D` for a round light, attached to the camera along its -Z,
    at `carried_magnitude` metres and in the content's tint. It is hidden when `light_source` is
    absent (nothing lit, or the burn clock spent), and for a corpse and the run-over panel. Both
    lights are shadowless.
  - **Information.** Night ambient is deliberately low (`AMBIENT_ENERGY_NIGHT`) and the sky near
    black; unlit geometry beyond the sim's sight is not readable. Bodies are still drawn only by
    `body_view.gd`'s `world.vision.detail` gate; a torch lights the 3D cone but never makes an
    unseen body's node visible.
- `godot/presentation/first_person/first_person.gd`: the old fixed `_build_environment` is replaced
  by the `SkyView`; the camera calls `build(camera)` after its rig, and every frame calls `update`
  after the identity watch, so the sky changes with the tick and the carried light.
- `godot/check_first_person.gd`: the LIGHT lane (below); `FIRST_PERSON_OK` names it.

## How it is judged

`npm run godot:check:first_person` instantiates the real scene and drives its own frame function.
The LIGHT lane:

- noon (`Clock.tick_on_day(1, 0.5)`): `sun_energy()` above 0.5 and `ambient_energy()` above 0.5
  (the named thresholds are `LIGHT_NOON_SUN_MIN` / `LIGHT_NOON_AMBIENT_MIN`), and the eye light is
  off with nothing lit;
- rain darkens the same noon sun below 0.9 of its clear value; fog from `SimWeather.set_kind`
  turns `fog_enabled()` on;
- midnight (`0.8`): `sun_energy()` below 0.05 and `ambient_energy()` below 0.15
  (`LIGHT_NIGHT_SUN_MAX` / `LIGHT_NIGHT_AMBIENT_MAX`), and still no eye light;
- a `item.torch.handheld` equipped through `SimInventory.equip` turns the eye light on at the
  sim's 25 m range and 22-degree beam, as a spot; the sim's own burn clock set to one tick turns
  it off again;
- a shambler behind an opaque wall, two tiles from the player and inside the torch's cone, is
  unseen by `vision.detail` (0) and its body view is not visible, with the torch on at night.

## Verified

- `npm run godot:check:first_person`: `FIRST_PERSON_OK ... lights noon by the sim's clock and
  darkens midnight, turns a carried torch into the eye's spot at the sim's range and cone and out
  when it burns, and keeps a body behind a wall undrawn ...`
- `npm run godot:check:light`: `LIGHT_LOOK_OK ...` (the top-down light map is untouched)
- `npm run godot:m2:light_burn`: `M2_LIGHT_BURN_OK ...` (the sim's burn, feed, plant and night
  rules are untouched)
- `npm run godot:smoke`: `GODOT_PROJECT_SMOKE_OK`
- `npm run check:routing`: `ROUTING_OK`
- extra: `npm run godot:check:play`: `PLAY_OK` (the title entry still boots the first-person
  scene; the sky view does not disturb the top-down lanes)

## Measured

Headed, `1280x720`, VSync off, 30 warm-up frames discarded, then 300 frames, on the same machine
and the same district (`first_person.tscn`, the shipped 256-tile district), mean frame time:

| | noon | night with a torch |
|---|---|---|
| before (PR #280, fixed environment, no eye light) | 1.144 ms | 1.145 ms |
| after (sky view, day/night, torch spot) | 1.220 ms | 1.317 ms |

The delta is about +0.08 ms at noon and +0.17 ms at night with the torch. The driver was a
temporary `SceneTree` script that booted the scene, set `world.tick`, equipped the torch, and
awaited `RenderingServer.frame_post_draw` 300 times; it was not committed.

## Limits

- No rain or snow particles; rain is a darker grade. No volumetric fog; the depth fog is the
  cheap form.
- All lights are shadowless. Geometry behind an opaque wall is still occluded by the depth buffer,
  and bodies are gated, but the eye light does not cast a shadow of its own.
- Night ambient is low rather than literally zero, so a faint fill remains at the edge of the
  torch; the top-down's 3.5 m eye disc is a 2D construct and is not reproduced as a hard circle.
- The fog's 30 m clear-sight constant is presentation tuning; the sim's `sight_mul` decides the
  ratio.
- No pitch, height or ray in the eye light; docs/40 slices 3, 5 and 6 own the spatial contract.
- No new HUD words or numbers: the light and weather are felt, not reported.
