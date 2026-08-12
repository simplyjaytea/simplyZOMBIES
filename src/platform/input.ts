// Keyboard input.
//
// docs/19-architecture.md: "Player input goes through platform/ into a command queue that
// the sim consumes on its own tick -- so input is part of the deterministic record."
//
// This layer reports *intent* only. It knows which keys are held; it does not know what a
// direction means in metres, because that is a simulation rule (see modules/player.ts).
// Keeping that split is what makes a recorded input log replayable independently of how
// fast walking happens to be this week.

import type { CommandQueue } from "../sim/kernel/commands";
import { Stance } from "../sim/stances";

/**
 * Movement keys, as world-space directions.
 *
 * **Rotated 45 degrees, so the keys are screen-relative.** Under the isometric projection
 * (src/render/projection.ts) world +x runs down-right on screen and +y runs down-left, so a
 * key bound to world north would send the survivor diagonally and every player would call it
 * broken. W is therefore "up the screen", which is world north-west.
 *
 * **This is the right layer for that rotation, and the only one.** `sim/` must not learn that
 * a camera exists (docs/19-architecture.md#layers), and the `move` command carries these
 * vectors into the deterministic replay record -- so the values recorded stay honest
 * world-space intent, and a log captured before this change still replays correctly. It is
 * just a different set of world vectors than the keys used to produce.
 *
 * Not normalised here: two keys held at once sum to a longer vector, and
 * `modules/player.ts` normalises before applying speed. That split is deliberate and
 * unchanged -- this layer reports intent, the simulation decides what intent means in metres.
 */
const DIAGONAL = Math.SQRT1_2;
/** Exported for the test that pins these against the projection they were rotated to match. */
export const MOVE_KEYS: Record<string, { dx: number; dy: number }> = {
  KeyW: { dx: -DIAGONAL, dy: -DIAGONAL },
  ArrowUp: { dx: -DIAGONAL, dy: -DIAGONAL },
  KeyS: { dx: DIAGONAL, dy: DIAGONAL },
  ArrowDown: { dx: DIAGONAL, dy: DIAGONAL },
  KeyA: { dx: -DIAGONAL, dy: DIAGONAL },
  ArrowLeft: { dx: -DIAGONAL, dy: DIAGONAL },
  KeyD: { dx: DIAGONAL, dy: -DIAGONAL },
  ArrowRight: { dx: DIAGONAL, dy: -DIAGONAL },
};

const SPRINT_KEYS = new Set(["ShiftLeft", "ShiftRight"]);

/**
 * The rungs you can pick outright, as [stance](../../docs/29-movement-and-stances.md) keys.
 *
 * Held Shift stays what it was -- press to target Sprint, release to target Walk -- because
 * that is the input the game shipped with and a five-rung ladder is not a reason to break the
 * one movement key people already know. These four are the rungs a held key cannot express:
 * you *stay* crouched, so crouching is a state you enter rather than a button you hold.
 *
 * Picked rather than held, and that is a design decision rather than a convenience: docs/29
 * makes a stance change a timed, interruptible action, so a hold-to-crouch key would have the
 * player paying that cost again on every accidental keyup.
 *
 * Exported for the test that pins them against the ladder, so a rung added to `Stance` without
 * a way to reach it fails rather than ships.
 *
 * They sit along one keyboard row **in ladder order** -- Z X C V, slowest to fastest, with
 * Shift carrying the top rung. So the physical keys are the ladder, which is one fewer thing to
 * learn than four unrelated letters, and reaching further right is reaching for more speed.
 */
export const STANCE_KEYS: Record<string, Stance> = {
  KeyZ: Stance.Crawl,
  KeyX: Stance.Crouch,
  KeyC: Stance.Walk,
  KeyV: Stance.Jog,
};

export type InputBindings = {
  /** Extra single-press actions, e.g. save and load. */
  readonly onPress?: Record<string, () => void>;
};

export type Input = {
  /**
   * Push this frame's intent onto the queue. Called once per tick rather than per key
   * event, so a burst of keyboard events cannot desynchronise two replays of the same log.
   */
  pump: (commands: CommandQueue) => void;
  detach: () => void;
};

export function attachKeyboard(target: Window, bindings: InputBindings = {}): Input {
  const held = new Set<string>();
  let pendingStance: Stance | null = null;
  let sprinting = false;
  let lastSprinting = false;
  let lastDx = 0;
  let lastDy = 0;

  const onKeyDown = (event: KeyboardEvent): void => {
    if (event.repeat) return;

    const action = bindings.onPress?.[event.code];
    if (action !== undefined) {
      action();
      event.preventDefault();
      return;
    }

    if (MOVE_KEYS[event.code] !== undefined) {
      held.add(event.code);
      event.preventDefault();
    } else if (SPRINT_KEYS.has(event.code)) {
      sprinting = true;
      event.preventDefault();
    } else {
      const stance = STANCE_KEYS[event.code];
      if (stance !== undefined) {
        // Queued rather than latched, unlike sprint. A rung you picked is an event that
        // happened once; there is no held state for the pump to notice a change in, and
        // re-sending it every tick would put a command in the replay log per tick for a
        // decision made in one.
        pendingStance = stance;
        event.preventDefault();
      }
    }
  };

  const onKeyUp = (event: KeyboardEvent): void => {
    if (MOVE_KEYS[event.code] !== undefined) held.delete(event.code);
    else if (SPRINT_KEYS.has(event.code)) sprinting = false;
  };

  // Losing focus with a key down would otherwise leave the survivor walking into a wall
  // forever, since the keyup lands on whatever took focus.
  const onBlur = (): void => {
    held.clear();
    sprinting = false;
    // The pending rung is deliberately *not* cleared. Losing focus should not swallow a
    // decision the player already made -- unlike a held key, which has to be released
    // because nothing will ever tell us it was.
  };

  target.addEventListener("keydown", onKeyDown);
  target.addEventListener("keyup", onKeyUp);
  target.addEventListener("blur", onBlur);

  return {
    pump(commands: CommandQueue): void {
      let dx = 0;
      let dy = 0;
      for (const code of held) {
        const delta = MOVE_KEYS[code];
        if (delta === undefined) continue;
        dx += delta.dx;
        dy += delta.dy;
      }

      // Only emit on change. A held key is already state in the simulation, so re-sending
      // it every tick would bloat the input log a replay has to carry.
      if (pendingStance !== null) {
        commands.push({ type: "stance", stance: pendingStance });
        pendingStance = null;
        // Picking a rung outright also drops the held-sprint latch, or releasing Shift later
        // would yank the survivor back to a walk out of a crouch they had chosen since.
        lastSprinting = sprinting;
      }
      if (sprinting !== lastSprinting) {
        commands.push({ type: "sprint", active: sprinting });
        lastSprinting = sprinting;
      }
      if (dx !== lastDx || dy !== lastDy) {
        commands.push({ type: "move", dx, dy });
        lastDx = dx;
        lastDy = dy;
      }
    },

    detach(): void {
      target.removeEventListener("keydown", onKeyDown);
      target.removeEventListener("keyup", onKeyUp);
      target.removeEventListener("blur", onBlur);
    },
  };
}
