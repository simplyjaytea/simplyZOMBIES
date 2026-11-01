# The first-person held weapon, built from the sim's parts

Weapon plan pieces W1 and W2: the first-person view draws the equipped item's kit model, assembled
from the parts the sim says are installed, in place of the interim placeholder box. Presentation
only: nothing under `godot/sim/` or `godot/assets/` changed, and the sim still decides every hit.

## What landed

- `godot/presentation/first_person/held_weapon.gd`, a `Node3D` under the camera:
  - **Held pose.** The kit's models are authored with their origin at `grip_r`, so the model is
    parented at a grip anchor in the lower right (`0.22, -0.20, -0.45`, real scale) with a small
    sway. The camera kick is inherited: the weapon is a child of the camera, so a swing or a shot
    moves it with the view.
  - **What is equipped.** `rangedWeapon.source` or `meleeWeapon.source` is the equipped item entity;
    its base id names the model. A ranged weapon wins when both are held, because that is the one
    the scene's aim and fire use. `SimMelee.is_unarmed` is the bare-hands predicate.
  - **Assembly.** For a ranged weapon, the receiver is drawn, then every installed visible part
    under the receiver's `socket_<slot>`. A muzzle device is parented under the installed barrel's
    own `socket_muzzle` when the barrel carries one, falling back to the receiver's (with the
    standard barrel the two are the same point). The canvas tree is the socket contract itself, so
    the gate can walk it.
  - **Hidden parts.** `internal`, `spring`, `sear` and `extractor` are skipped in the held view: the
    first three are inside the receiver shell, and the extractor is a slide detail the held angles
    do not reward. That is 324 of a default pistol's 1,430 triangles.
  - **Melee.** The whole model is drawn and no parts are added: the fire axe already draws its own
    head and haft, so the content's `defaultParts` must not be stacked on it. Separate melee part
    models are art piece 6.
  - **Absent is absent.** A part with no model leaves its socket empty and its base id is listed by
    `missing_parts()`; it is never replaced by a default. An item with no model keeps the interim
    placeholder box, sized by its profile, so the screen still says something is in hand. Bare
    hands draw nothing.
  - **Rebuild only on change.** The assembly is compared by base ids (receiver plus visible parts);
    an equip, a field swap or a bench changes it, and a still frame does no model work.
  - **`verify(world)`.** The view can answer whether what it drew is what the sim holds now. The
    gate's mismatch negative uses it: detach a part in the sim, and the view that has not repainted
    fails its own check.

## The model seam

The manifest loader is `godot/presentation/first_person/models.gd`, written in parallel
(`claude/fp-manifest`). It was not on origin when this piece needed it, so this branch calls only
the agreed interface:

- `resolve(item_id) -> {glb: String, sockets: {slot: node name}, grip: String, ...}`, empty for an
  unknown id.
- `instance(item_id) -> Node3D`, a fresh instance (or null).

There is no second loader in the committed branch. If `models.gd` is absent, `held_weapon.gd`
models nothing, the placeholder box stays, and the HELD lane prints
`FIRST_PERSON_SKIP HELD: models.gd (the manifest loader) is not on this branch, so the placeholder
box is under test`. For local verification and the captures an untracked stand-in implementing only
that interface was used; it is not part of the commit. On the merged branch the real loader runs
the same two functions.

## The gate

`npm run godot:check:first_person` gains a HELD lane and prints `FIRST_PERSON_OK`:

- A real service pistol is spawned (`SimItems.spawn_item` assembles its default parts) and equipped
  through `SimInventory.equip`, which the sim's own handler turns into `rangedWeapon` with its
  `source`. The view draws the receiver, barrel and magazine -- exactly the sim's installed visible
  set -- each part parented on `socket_<slot>` under the receiver.
- The suppressor is fitted through the sim's own `item.attach` command; it appears on the barrel's
  `socket_muzzle`.
- True negative: the suppressor is detached in the sim and the view is not repainted, so
  `verify(world)` returns false; one `_process` later it is true again, and the drawn set no longer
  holds the muzzle part.
- Bare hands draw nothing. The bat is drawn whole, with no added head and no parts.
- Hidden slots are never drawn, and every drawn slot sits on a `socket_` node.

## Measured

Headed, 1280x720, Compatibility, 300 frames after 30 warmup at the spawn of the shipped district
with the service pistol held, same driver both sides:

| Run | Before, placeholder (ms) | After, assembled model (ms) |
|---|---:|---:|
| 1 | 1.464 | 1.785 |
| 2 | 1.456 | 1.716 |
| 3 | 1.724 | 1.530 |
| Median | **1.464** | **1.716** |
| Mean | **1.548** | **1.677** |

The assembled pistol costs about 0.25 ms at spawn (three textured meshes and a small node tree in
place of one box), and both sides are far under docs/22's 10 ms draw target. A fourth after run with
the captures in the same process measured 1.838 ms.

## Captures

Viewport-only (`get_viewport().get_texture()`), no OS input and no desktop screenshot, saved outside
the repository:

- Default service pistol: `C:/Users/jtf/AppData/Local/Temp/opencode/held-weapon/pistol_default.png`
- Suppressed: `C:/Users/jtf/AppData/Local/Temp/opencode/held-weapon/pistol_suppressed.png`
- The wooden bat: `C:/Users/jtf/AppData/Local/Temp/opencode/held-weapon/bat.png`

## Not in this piece

- No hands or arms: the weapon floats at the grip anchor until the arms art lands.
- NPCs get no view model; this is the player's held view.
- No mesh merge: the parts stay separate nodes so each socket is legible to the gate, and each GLB
  embeds its own atlas copy anyway. A merged world LOD for NPCs is later work.
- The bench cutaway of the internals, and separate melee part models, are later.
- The loader is the parallel manifest piece; when it merges, the seam and the HELD lane run for
  real with no change here.
