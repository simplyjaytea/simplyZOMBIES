# Fight back in first person

Interim combat input for the first-person scene, so the alpha is playable before the spatial
contract's shot-as-a-ray slices land. The top-down screen's own buttons and keys now swing, fire
and reload through the same planar sim commands; the sim still decides every hit. The projection
is explicitly INTERIM and names the docs/40 slices that replace it. No sim file changed.

Stacked on `opencode/fp-title` (PR #278), which carries #274, #271 and #270. Worktree `fp-fight`,
branch `opencode/fp-fight`.

## What landed

- `godot/presentation/first_person/first_person.gd`:
  - **The controls** are `input_map.gd`'s own: the left mouse click is "the trigger if a firearm is
    in hand, the swing otherwise"; `F` swing, `G` fire, `R` reload. They push the same `swing`,
    `fire` and `reload` commands the top-down screen pushes.
  - **The aim** is the camera's look yaw, pushed as the ordinary `aim` command. The planar sim
    projects that bearing itself: melee selects a body at the weapon's `reachMetres`, ranged at
    `rangeMetres`, both through `SimAim.radians_of`. The look direction's floor projection is the
    aim; no target point or pitch crosses the boundary because the sim has no height or ray yet.
    The block is marked INTERIM and names docs/40 slices 3 ("Pitch on the aim"), 5 ("The shot as a
    ray") and 6 ("Parts from geometry") as the replacements.
  - **Feedback** is a short camera kick on a swing or shot. There is no reticle and no centre dot
    (docs/40 owner question 6's default), and no hit/miss word: the top-down screen has no such
    word either (it flashes the struck body and shakes), so this scene invents none.
  - **The held weapon** is a placeholder box in the lower right, a child of the camera, sized by
    the weapon's own class cue (a firearm's range, a melee weapon's reach) and hidden for bare
    hands. `SimMelee.is_unarmed` is the one predicate. It has no collision and never moves on its
    own; art comes later.
  - **Refusals.** The ledger, the inventory sheet, the end panel and the dead-and-waiting gap
    swallow the press. A refused swing or shot is the sim's refusal and gets no words from the
    scene.
- `godot/presentation/first_person/hud.gd`: the centre dot is gone (the scene had one from the
  foundation) and the help line names the combat keys.
- `godot/check_first_person.gd`: the FIGHT lane (below); `FIRST_PERSON_OK` names it.

## Controls

Left mouse (or `F`) swings the melee weapon in hand; left mouse with a firearm (or `G`) fires; `R`
reloads. Mouse look is the aim. `E`/`Escape` and the ledger/inventory keep their old meanings.

## How it is judged

`npm run godot:check:first_person` instantiates the real scene and drives its own frame function.
The FIGHT lane:

- true positive, melee: a bat is put in hand and a shambler is spawned 1.2 m ahead with its
  speeds zeroed; `F` pushes `swing`, the sim publishes `attack.connected` with the player as
  attacker and that shambler as target, and the shambler's body total falls. A camera kick is on
  the frame the press lands.
- true positive, ranged: a magazine-fed profile is equipped with six rounds, the left mouse button
  pushes `fire`, and the magazine is one lower after the raise/steady/fire ladder. The same press
  with the ledger open pushes no `swing` and no `fire`.
- true negative, the look: a shambler 1.2 m behind the player, with the look turned away, is not
  hit and its body does not change.
- true negative, the reload: a fed weapon with no rounds in the pack is refused by the sim (no
  `weapon.reloaded`, magazine stays empty) and the scene's alert stays empty.
- the viewmodel: hidden with bare hands, visible with a bat in hand.

## Verified

- `npm run godot:check:first_person`: `FIRST_PERSON_OK ... swings a bat into a shambler and fires a
  round through the top-down commands while the ledger refuses both, misses a body behind the
  look, and leaves a refused reload wordless ...`
- `npm run godot:m2:swipe`: `M2_SWIPE_OK ...` (unchanged sim melee)
- `npm run godot:m2:ranged`: `M2_RANGED_OK ...` (unchanged sim ranged)
- `npm run godot:check:hud`: `HUD_OK ...`
- `npm run godot:smoke`: `GODOT_PROJECT_SMOKE_OK`
- `npm run check:routing`: `ROUTING_OK`

`npm run godot:check:play` was run as an extra (it boots the first-person scene from the title);
`PLAY_OK` on the rerun, after one transient `PLAY_FAIL` with no lane error printed and no change
made between the runs.

## Limits

- This is the planar aim, not the spatial contract: no pitch in the shot, no ray, no height, no
  geometric body-part choice, and no obstruction change. docs/40 slices 3, 5 and 6 replace the
  projection; the INTERIM comment says so.
- Melee can still land through a wall exactly as the planar `_resolve_strike` allows; closing that
  is docs/40 slice 2, not this piece.
- The viewmodel is a placeholder box. There is no sway, recoil animation, muzzle flash or hit
  flash in the 3D view; the sim's own events and the target's body remain the feedback.
- There is no reticle, centre dot, spread display or hit/miss word by design.
- The left mouse click is the attack and also the way back into mouse look; the first click after
  the pointer is released only recaptures, as before.
- No right-click context menu in first person; that is a later interaction slice.
