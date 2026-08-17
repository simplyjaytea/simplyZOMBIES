# Vertical Slice Design Implementation Plan

> **For Hermes:** Do design decisions first. Do not add Milestone 2 scope until the playable-loop controls and acceptance scenario exist.

**Goal:** Prove the integrated daily ratchet: build by day, defend at dusk, absorb loss at dawn—while validating tension, colony attachment, tactical tradeoffs, and six-survivor automation.

**Architecture:** Preserve deterministic sim authority. The director creates seeded, warned story beats; presentation renders only player-readable signals and submits commands. A settlement remains emergent: any safe site may gradually become home, never a separate mode.

**Tech Stack:** Godot 4.7.1, typed GDScript, deterministic fixed-tick simulation, JSON content, existing Godot checks.

---

## Design decisions captured

- Vertical slice proves all four pillars: attention tension, attachment/loss/succession, defense tradeoffs, viable six-survivor automation.
- Major loop: build by day; defend at dusk; absorb loss at dawn.
- Director is a seeded roguelike storyteller: arrivals, site changes, hard choices, threats.
- Major beats: every 2–3 in-game days. Minor texture: daily.
- Major beats always provide clear warning and meaningful preparation or avoidance.
- Warning reveals threat type, arrival window, likely entry direction—not exact count or outcome.
- Avoidance usually costs opportunity: a site, loot cache, or recruit.
- Successful confrontation yields a lasting capability: person, tool, route, or fortified position.
- Avatar is direct-controlled field leader, mechanically one survivor among others; it levels identically. Colony formation is optional.
- The avatar may explicitly establish a camp at any chosen site. A camp becomes a notable return point and a destination for survivor assignment; its noise, light, and other attention signals drive raider/horde pressure.
- Automated survivors receive an assignment plus priorities: survivor, location, and job; they use local judgment within that direction. Default doctrine preserves life: retreat, abandon task, seek safety. First playable-loop assignment: build/repair at camp; guard, scavenging, rest, recovery, and treatment assignments follow later. Routine projects follow player-set blueprint priority. During a warned threat, builders override it for the valid task best blocking the likely route.
- Bonds are always mutual pairs formed through time together, shared labor, and shared danger; danger counts more than routine time. Each survivor has one strong bond for now; future CHA progression may expand this cap. A strong bond cannot be replaced; non-strong shared history has no current mechanical effect and only progresses toward a future open bond slot. The avatar follows the same rules; its bonds can trigger NPC sacrifice behavior and future rescue. A shared-history threshold alone unlocks strong-bond sacrifice behavior; no authored relationship beat or special crisis is required. Its threshold becomes visible through an immediate prose milestone and ongoing behavior. Before rescue exists, bonds provide trust: better coordination, morale, and willingness to take assignments.
- Morale is broad pressure, not one isolated penalty: low morale slows work, makes dangerous assignments less acceptable, weakens combat, and causes earlier retreat/flee behavior. The strongest rapid loss trigger is seeing a bonded survivor hurt, captured, or die; successful defense or completed rescue restores morale fastest. At breaking point, the survivor refuses dangerous assignments until morale recovers. Near-refusal is communicated by visible behavior, trusted-survivor reports, and authoritative prose explaining cause; morale stays non-numeric.
- Avatar death ends the current run. Future rescue is post-slice scope, restricted to named/bonded survivors.

## Mechanics decisions captured

- The game is real time, driven by the fixed deterministic tick; it is not turn based.
- Director warnings create a real-time preparation window before a threat resolves.
- Construction begins with a placed blueprint. Materials are fully reserved on placement. Assigned builders at that camp claim it first; avatar may assist. Every capable builder contributes full work rate; assistance is always safe, not a crowding hazard. Work pauses for immediate danger, higher-priority care/food/repair, or missing tools, then resumes when safe/possible. Cancellation refunds all reserved materials; destruction before completion returns salvage proportional to construction progress.
- Partially built defenses act as weaker barriers proportional to construction progress.
- Construction is one broad skill: faster work, stronger repairs, higher barrier integrity, access to better blueprints. Level zero permits barricades only. First unlock: short walls for route shaping and choke creation. Second unlock: basic gates for controllable entry, exit, and fallback geometry. Third unlock: raised firing points for superior sightlines. They expose defenders to raider shots, poor cover/slow escape, and stronger noise/light targeting; use requires a fallback plan. Completed construction work ticks grant XP; every contribution advances the skill.
- Repair consumes matching building material and tool condition: real resupply and tool maintenance are part of holding a breach. A broken tool permits hand repair at a severely reduced rate.
- Survival loop begins with any damaging zombie hit creating a severity-based wound at the struck body part; zombie attack type sets its baseline, while hit damage and armor/clothing modify escalation. First-slice wound taxonomy: scratch, laceration, deep wound, bite. All require bleeding control: scratches bleed least, deep wounds most. Bite wounds retain infection exposure on top of the ordinary wound. The first mandatory avatar treatment action is stopping bleeding: any survivor may apply bare-handed pressure immediately. Every wound needs the same brief uninterrupted action to stop bleeding temporarily. Pressure fully occupies participants: self-pressure prevents movement and combat; treating another occupies both treater and patient. Any hit, grab, or player cancellation interrupts pressure and resumes bleeding. Sprinting, melee, hard labor, or climbing reopens an unbandaged wound. Bandaging uses the same brief uninterrupted action and is the durable treatment preventing reopening. Bandage tiers—sterile, cloth, dirty rag—differ in bacterial infection risk. First-slice bacterial-infection risk depends only on wound severity and bandage quality, deterministically fixed when bandaged. A bandaged wound still applies immediate location-based impairment: hurt arms and legs impair their relevant actions; torso wounds impair stamina capacity and breathing; head wounds impair perception and reaction. Recovery advances continuously while hunger remains above the seek threshold and the survivor avoids strenuous work: idling, sitting, or sleeping count. Below that threshold, recovery stops before critical hunger. Overwork reopens wounds or delays healing. Recovery clocks: scratch 1 day, laceration 3 days, deep wound 10 days. Dressing is severity-scaled: scratches need none; lacerations need one replacement after one day; deep wounds need replacement every day. An overdue required dressing pauses recovery until replaced. Reopening from overwork loses only recovery progress accrued since the latest dressing; prior recovery remains. Full recovery clears the wound and its impairment; body-part integrity remains persistent and out of first-slice recovery scope. A bite uses the 3-day laceration clock alongside its infection outcome. First-slice stamina drains from sprinting, melee, climbing, and hard labor; hauling is deferred. It restores while idling, sitting, or sleeping; all exertion pauses recovery. Stamina is an independent short-clock system: hunger, rest pressure, and wounds do not alter its recharge. Wounds still affect action performance. Low stamina gradually slows sprinting and melee. Breathing, weapon drag/sway, and fading sprint response communicate it without a bar. At zero stamina, sprinting and climbing are blocked; walking and melee remain possible, but melee deals less damage with slower wind-up and recovery. Active bleeding is communicated by world feedback first—blood trail and worsening movement/behavior—with authoritative prose confirmation. Treatment begins through the condition view: select survivor and body part, then start the action. The condition view pauses simulation only in single-player; submitted treatment commands remain deterministic.
- Defense preparation is labor-constrained: builders committed to defenses stop food, medicine, and repair work.
- Geometry decides most defense outcomes: choke points, barriers, sightlines, fallback routes.
- Zombies seek the shortest path to the strongest signal and pile up at barriers. Mass compression increases packed-zombie pressure and barrier damage; sustained mass and strikes breach integrity. Killing enough zombies thins the pile and immediately reduces pressure before failure. Once inside, a zombie targets the nearest visible human. Visible damage state plus sound/animation telegraphs imminent failure without numeric integrity. The avatar may repair under attack, exposed at the breach.
- On breach, the avatar decides only whether to fight or leave. NPCs remain autonomous: immediate survival usually overrides assignment and personal disposition. Strong bonds may override survival for otherwise irrational sacrifice: circumstances may cause an NPC to break cover for extraction/protection, hold a route for escape, or refuse abandonment/surrender. At immediate contact, an NPC seeks nearest defensible cover and fights only if the threat closes. Cornered NPCs may surrender to raiders rather than die, creating an immediate pursuit/rescue consequence.
- The avatar's defining warning-window contribution is direct construction and repair.
- A director warning locks threat arrival time and likely direction. Player action can change preparedness only; it cannot cancel, delay, divert, or retarget the incoming threat.
- Player combat rewards positioning: range, facing, terrain, and escape routes. Melee holds a choke but risks grabs when surrounded; ranged combat carries noise, line-of-fire, ammunition, and reload costs while shot placement matters.
- Raiders scout unguarded approaches and blind sightlines. Reliable scout/guard reports warn of them, with uncertainty limited to route and strength. Raiders steal supplies and capture people, then withdraw; immediate high-risk avatar pursuit may save a captive, without direct NPC orders. Raider types exploit, deliberately breach, or use tools/climbing; warnings identify the tactic. At breach, the avatar fights to protect people and supplies.

## Open design decisions

1. Define the first complete 2–3 day story arc and its exact minor daily texture.
2. Define camp creation cost, placement constraints, persistence, abandonment, and what signals raiders versus hordes read.
3. Define non-player survivor order vocabulary, failure modes, and player observability.
4. Define bond thresholds, trust scaling, and loss stakes; bonds provide coordination, morale, and assignment willingness.
5. Define each warning channel: sight, sound, radio, scout report, or visible environmental change.
6. Define slice success/failure outcomes and whether success is a campaign continuation or an explicit scenario completion.

## Phase 0: Repair the playable-loop foundation

### Task 1: Route stance changes through simulation commands

**Objective:** Make crouch/crawl/walk/jog/sprint deterministic simulation state, not presentation mutation.

**Files:**
- Modify: `godot/sim/world.gd` command intake
- Modify: `godot/presentation/main.gd` input mapping
- Modify: `godot/ui/legend.gd` actual bindings
- Retire or reconcile: `godot/sim/stance.gd`
- Test: existing stance-related Godot check, or a narrow new check

**Acceptance:** A queued stance command reaches `SimStances`; transition ticks complete; posture affects movement/noise/aim/swing; repeated seeded command logs resolve identically.

### Task 2: Verify sprint is sim-owned

**Objective:** Remove presentation-only sprint state and make sprint affect locomotion, noise, and stamina only through the current posture.

**Files:**
- Modify: `godot/presentation/main.gd`
- Modify: sim command/movement path as needed
- Test: Godot stance/movement check

**Acceptance:** Holding/releasing sprint produces deterministic posture commands; HUD legend agrees; no gameplay outcome depends on frame timing.

### Task 3: Expose existing infection choices through commands

**Objective:** Make caution, amputation, antibiotics, quarantine, and put-down player-accessible where current scope permits.

**Files:**
- Modify: `godot/sim/modules/infection.gd`
- Modify: `godot/sim/world.gd` command intake
- Modify: relevant UI/presentation files
- Test: `godot/check_m2_lethality.gd` or focused successor

**Acceptance:** Every exposed action uses a command, validates state and resources, produces legible consequence, and preserves deterministic save/replay behavior.

## Phase 1: Specify the slice scenario before expanding systems

### Task 4: Write one acceptance scenario

**Objective:** Turn the design pillars into a reproducible seeded 72-hour playtest.

**Files:**
- Create: `docs/` scenario specification
- Modify: `HANDOFF.md` only after implementation evidence exists

**Scenario shape:**
1. Day 1: establish temporary safety; player choices create readable local pressure.
2. Daily texture: information, scarcity, a small opportunity, or social friction.
3. Day 2/3: director telegraphs a major beat with type/window/likely direction.
4. Player prepares, accepts, redirects, or avoids.
5. Resolution: loss, cost, or lasting capability; dawn exposes consequences.

**Acceptance:** Every step maps to an existing system or an explicitly scoped implementation task. No prose-only mechanic claims.

### Task 5: Define director beat contract

**Objective:** Establish deterministic data shape and lifecycle for a warned beat.

**Files:**
- Likely modify: `godot/sim/modules/director.gd`
- Likely modify: `godot/content/calibration/attention.json`
- Likely create: content data for first beat family
- Test: `godot/check_m2_director.gd`

**Minimum fields:** stable ID, seed stream, trigger eligibility, telegraph tick/window, likely direction, avoidance opportunity cost, resolution conditions, outcome capability.

**Acceptance:** Same seed + command log chooses the same beat and warning. No exact enemy count leaks through player UI.

## Phase 2: Build the smallest story-capable loop

### Task 6: Implement warned zombie-horde defense first

**Objective:** Prove the director contract and core defense loop with one incoming zombie horde; do not create a generic event framework.

**Player contract:** The warning locks arrival time and likely direction. During the real-time preparation window, avatar and NPCs build/repair based on skill and speed. The player can improve preparedness, but cannot delay, divert, cancel, or retarget the horde.

**Horde contract:** Zombies seek the strongest signal along the shortest route, compress at barriers, and progressively damage them. Killing thins the pile and immediately reduces pressure. Once inside, zombies attack the nearest visible human.

**Files:** determined by the horde design pass; likely `godot/sim/modules/director.gd`, `godot/sim/modules/fortify.gd`, zombie behavior module(s), presentation warning/damage feedback, and a focused Godot check.

**Acceptance:** Prepared defense, costly breach, and intentional evacuation resolve from the same seeded scenario. Evacuating leaves an occupied danger zone. The avatar reclaims it after killing enough zombies for survivors to regain control; stragglers may remain. Every damaged camp function stays unavailable until physically repaired. Barrier integrity never appears as a number; damage state and sound/animation remain readable.

### Task 7: Add breach repair exposure

**Objective:** Let the avatar repair an actively attacked barrier at personal risk.

**Acceptance:** Repair progresses through deterministic ticks; avatar exposure at breach changes survivability; packed-zombie pressure and kills produce immediate, testable integrity effects.

### Task 8: Add daily texture only where it changes choices

**Objective:** Add lightweight signals supporting the next major beat.

**Rule:** Reuse existing attention, needs, jobs, recruitment, and field-memory machinery before adding mechanics.

**Acceptance:** Daily texture informs or complicates an upcoming choice. Remove decorative events with no decision impact.

### Task 8: Create explicit camp placement

**Objective:** Let the avatar establish a camp at a chosen world location, without making a colony mandatory or turning it into a separate game mode.

**Likely implementation:** A deterministic `camp.create` command validates tile/site suitability, creates a stable camp ID and location, then exposes it as a return point and survivor-assignment destination.

**Camp pressure:** Camp-local light, noise, scent, occupancy, and defenses form the director’s readable pressure inputs. Hordes and raiders target the camp according to those signals; exact attack strength remains hidden.

**Creation cost:** Establishing camp costs time and labor by the avatar and/or survivors. It is a deliberate, interruptible commitment—not a menu click or disposable item.

**Placement:** Any location can host a camp. There are no hard suitability restrictions; danger, exposure, and time-to-establish are the cost.

**Abandonment:** A camp may be abandoned freely. Its location persists as a known empty site; establish a different camp elsewhere rather than moving camp identity/infrastructure.

**Threat models:** Hordes follow emitted attention signals. Raiders scout camps with valuable signals or resources, then exploit observed weaknesses. Both remain readable and telegraphed; neither exposes exact attack strength.

**Acceptance:** A camp is explicitly player-chosen, save-stable, legible in prose, targetable through attention signals, and optional for a viable run.

## Phase 3: Validate colony stakes and automation

### Task 9: Exercise six-survivor automation

**Objective:** Run one seeded colony with the avatar as field leader and six automated survivors.

**Check:** assignment tuple (survivor/location/job), local priority resolution, loadouts, needs, defenses, warning response, and a loss/recovery state.

**Acceptance:** Automation creates comprehensible tradeoffs; player intervention changes assignment or priority, not precise paths or targets.

### Task 10: Run balance evidence

**Commands:**
- `BALANCE_FULL=1 BALANCE_SEEDS=1 npm run godot:m2:balance:full`
- Then full `BALANCE_FULL=1 npm run godot:m2:balance:full`
- `npm run godot:m2`
- `npm run godot:r6`
- `npm test && npm run typecheck && npm run lint && npm run format:check`

**Acceptance:** Full grid complete, no unexplained deterministic regression, new scenario gate passes repeatedly from clean checkout.

## Risks and guardrails

- Do not add more mechanics until Phase 0 restores actual player control.
- Do not build a generic quest/event engine. One beat family proves the contract.
- Do not turn the colony into a mandatory mode or a menu-driven management game.
- Director warnings must preserve uncertainty without becoming unfair.
- Preserve the condition/infection information barrier; numeric truth stays out of player HUD.
- `SimBoot._KERNEL_WORLD` remains a single-world constraint; defer multi-world work unless a test requires it.

## Current priority

- Pause new NPCs and adjacent feature scope. Keep Mara as the test survivor.
- Survival systems first: wounds, treatment, stamina, and recovery.

## Next action

Finish survival-system design interrogation, then write the 72-hour scenario specification before code changes.
