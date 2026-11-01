# Weapons, characters and a bigger world in first person: the plan

Draft, 2026-11-01. A plan, not a record: nothing here has shipped. It follows docs/39 (the pivot)
and docs/40 (the spatial contract), and keeps the content arcs' rule from docs/38: readers before
content, pictures a stage behind.

## Three rules that hold for all of it

1. **The picture is the sim.** A gun on screen is the sim's assembly: the receiver and the parts
   it holds, drawn from the same records the bench reads. A body animates from sim state
   (moving, crouched, swinging, held, dead), never on its own clock. A wall is SimSpace's band.
   Every piece gets a gate that the drawn thing equals the sim's thing.
2. **Anything that blocks, hides or can be taken is sim.** Furniture that stops a body or a
   sightline, a container, a door: sim, through the existing generator and SimSpace. Pure
   decoration (litter, posters, a lamp that gives no light the sim knows of) may be
   presentation, seeded from the map seed so it is the same every time.
3. **Words, not numbers.** Weapon condition shows as wear on the model and words on the bench,
   never a figure. No reticle (docs/40 owner question 6, default none).

## A. Weapons in the game

What exists: 12 firearm receivers with up to ten part slots each (optic, barrel, muzzle,
magazine, furniture, internal, spring, sear, extractor, underbarrel), bows and crossbows with
three (sight, limb, string), 20 parts, 20 attachments, 25 improvised parts, and 20 melee
weapons that are frames in four families (club, blade, polearm, tool) with head, haft, wrap,
stud, guard and weight slots. The sim already assembles, wears, repairs and names them.

The slices, in order:

- **W1. The held weapon.** A first-person view model: arms plus the equipped item, chosen from the
  sim's equipment each frame. One whole mesh per weapon class to start (bat, knife, pipe,
  pistol, shotgun, rifle, bow). Replaces the interim placeholder box from #280. Gate: what is in
  the hand on screen is what the sim says is equipped; bare hands show arms only.
- **W2. Modular firearms.** Each receiver modelled with named sockets (one empty per slot); each
  part a small mesh that snaps to its socket. The drawn gun is built from the sim's installed
  parts. Gate: the drawn part set equals the sim's installed set for every receiver and part
  combination in content (and a planted mismatch fails). This is where the weapons start to
  read as "every number is a sum of its parts".
- **W3. Melee frames.** The same idea for the four melee families: a haft line with head, wrap,
  stud, guard and weight sockets. The 25 improvised recipes become visible: nails in a bat,
  wire on a pipe, glass in a club.
- **W4. Animation from sim timings.** Swing, fire, recoil, reload per magazine type, jam and
  clear, raise and lower, inspect. Animation lengths come from the sim's own durations (swing
  commit ticks, `reload_ticks`), not the other way round. Gate: each animation's key event
  (the blow, the shot, the round seated) falls within one tick of the sim's event.
- **W5. Weapons in the world.** Dropped items, loot on shelves and the dead's weapons drawn as
  their models. The gunsmith bench becomes a physical bench, like the ledger: walk up, E, the
  assembly screen.
- **W6. Wear you can see.** The sim's condition words map to three or four wear tiers of
  texture per part, never a number.
- **Combat geometry** is docs/40's slices 4 to 9 (perception with heights, the shot as a ray,
  parts from geometry, camera and sim agreeing, the balance re-measure). Slices 5 and 6 wait
  on owner questions 1 and 2.
- **Sim-side weapon depth** continues on its own track: the content arcs' "conversions are
  kits" and "Gunsmithing decides field versus bench" (docs/23), and raiders spawning with
  assembled weapons, so a dead marksman drops the rifle as he built it.

## B. Characters and animation

- **C1. The two bodies in the scene.** Integrate the survivor and shambler kit (#288, in art
  review) into body_view: animation state from sim state. Gate: each body's playing clip
  matches its sim state; a dead body plays death once and holds.
- **C2. One rig, many bodies.** A modular survivor (heads, hair, torsos, legs) with clothing
  layers that follow the sim's worn slots, so the jacket you looted is the jacket you see on a
  colonist. Unique people (Mara, Ellis) get authored looks; generated people draw from part
  pools seeded by their identity.
- **C3. The seven zombie kinds.** Shambler, runner, stalker, screamer, bloater, heavy, armored,
  each a variant of the shared rig with its own gait; then the planned kinds as they land
  (crawler first). Wounds read on the body without a health bar: torn cloth, blood, a limp.
- **C4. The full NPC set.** Walk, run, crouch, crawl, hit, stagger, grab, eat, work loops for
  each job (build, cook, haul), sleep, death variants. One rig, retargeted.
- The owner's fluid-animation rule becomes a builder check: loop seam (first and last pose
  equal), bob symmetry left against right, and foot slide at the sim's speed under a measured
  limit.

## C. A bigger world, and procedural generation

What exists: the district is already generated. `godot/sim/map/worldgen.gd` stamps 22 authored
building templates (each a tile grid with doors, indoors, tags, a wall and roof look) into four
district types (town centre, residential suburb, industrial park, forest edge) with streets,
vehicles and loot; `region.gd` tiles districts into 192-tile cells with seams, opt-in through
`--region`. The first-person view draws whatever the sim generated. So the plan builds on the
generator rather than starting over:

- **P1. Dress the generated world.** A deterministic dresser turns each tile class, each
  template's wall and roof look, and each indoor room into kit pieces: wall modules by
  material, roofs, floors by surface, windows and doors by state. Seeded from the map seed and
  tile index, so a street of houses is varied but the same every boot. (Kit integration, now in
  progress, is the first slice of this.)
- **P2. Rooms that are furnished.** Room tags in the templates (kitchen, bedroom, store room,
  workshop) drive furniture and props. Blocking furniture and containers come from the sim's
  loot and container passes; decoration is presentation, seeded.
- **P3. Procedural buildings.** A floor-plan generator that outputs the same template shape
  (tiles, doors, indoors, tags), so every existing gate judges it. Authored templates stay as
  set pieces; generated plans fill the rest, weighted by district type. This is the step that
  makes no two towns alike.
- **P4. Landmarks.** Authored set pieces stamped into the generated world: a police station
  (weapons), a clinic (medicine), a hardware store (materials), a gun shop (parts). They give a
  run its goals.
- **P5. The region as the world.** The five-part main area (city, forest, factory, river, lake)
  becomes the first-person default once the frame and tick budgets hold there, measured. Then
  chunked drawing and, later, streaming (Milestone 3B; docs/23's Risk 7).
- **P6. Procedural loot weapons.** Found weapons assembled from the part tables by district
  and tier, so a gun found in the industrial park differs from one in a suburban closet. The
  same generator arms raiders.

Verticality (stairs, upper floors, roofs to walk on) stays out until the owner decides it
(docs/39 and docs/33 already hold it open).

## D. Who builds what

- **Art (the Kimi terminal):** the view-model arms, weapon receivers and parts with sockets, the
  melee frame kit, the modular character rig and clothing, the zombie variants, the dresser's
  kit (wall materials, roofs, room props). Each piece is a reproducible Blender builder with a
  `--check`, and each gets the independent art review before merge.
- **Presentation code (the OpenCode and Haiku terminals):** view model, socket assembly, the
  animation state from the sim, the dresser, landmark stamping, all with gates that the drawn
  thing equals the sim's thing.
- **Shared sim modules (strongest tier):** the docs/40 slices, the floor-plan generator (it
  feeds worldgen), procedural loot weapons, raider weapons.

### The art pieces, from the art lead's pipeline plan

The current tables imply about 98 weapon meshes to start: 13 receivers, 35 ranged parts, 20
melee bases and 30 melee parts. Each piece below is one session, a reproducible Blender builder
with a `--check`, and an independent in-engine art review. Pieces marked **blocks** gate code.

1. Socket and manifest specification, one receiver and six parts (**blocks** assembly code).
2. The thirteen receivers and the caliber magazine-well jigs.
3. Exterior ranged parts: barrels, muzzles, magazines, furniture, optics, underbarrel.
4. Internal, action and bow parts, and an inspect cutaway for the bench.
5. Twenty melee base silhouettes and the four socket-line jigs (**blocks** melee code).
6. Thirty melee slot models with the legal-combination matrix.
7. Per-part condition variants and wear decals, judged at 0.4 m and 2 m.
8. View-model arms, grips, idle, sway, raise, lower, inspect (**blocks** weapon animation code).
9. Melee swings, firearm fire and recoil, timed to the sim's contact.
10. Reloads per magazine and action type, jam and clear.
11. Third-person locomotion, hit, stagger, grab, eat and death library (**blocks** NPC motion).
12. Modular survivors and clothing that follows the worn slots.
13. The seven zombie silhouettes with retargeted gaits.
14. A building module kit on SimSpace's bands and one whole house (**blocks** world geometry).
15. Room and prop anchors, and the residential and commercial prop kit.
16. Industrial, civic, outdoor and vehicle dressing kits.
17. The 22 templates as art manifests and the four district types assembled (**blocks**
    scalable dressing).
18. A chunked level-of-detail pass with dense-scene and driving benchmarks.

Texel density: 64 per metre for the world and bodies; 128 only on the hand-held weapon's
close-up surfaces, so the view model reads at 0.4 m without making the world look blurry beside it.

## E. Order

First the playable loop, then looks: C1 (bodies in the scene) and W1 (the held weapon) come
first, because they change how the alpha feels most. Then P1 and P2 (a dressed, furnished
town), W2 and W3 (modular weapons), and docs/40's slices 4 to 7. Then C2 to C4, W4 to W6, P3
and P4. P5 and P6 come last, after a measured budget pass.

## F. For the owner

Each has a recommended default; none blocks work.

1. **Arms on screen?** Default: yes. Visible hands holding the weapon, as in Project Zomboid's
   first-person mods.
2. **Generated buildings beside authored ones?** Default: generated plans fill most lots,
   authored templates remain as landmarks and set pieces. The art lead's caution: a floor-plan
   generator needs the module kit to cover every wall, corner and opening it can produce, so
   it comes after art piece 17, with the 22 authored layouts dressed first.
3. **How detailed?** Default: the starter kit's level. Low-poly, 64 texels per metre, pixel
   textures, so a horde stays affordable.
4. **When does the region become the default world?** Default: after a measured frame and tick
   budget pass there, not before.
5. **How much does a weapon's look tell you about its condition?** Default: four worn looks plus
   broken, matching the words the bench already uses, never a percentage.
