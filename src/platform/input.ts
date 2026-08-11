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
