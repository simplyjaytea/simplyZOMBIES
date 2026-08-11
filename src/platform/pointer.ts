// Mouse and touch input.
//
// The keyboard adapter's sibling, and it exists for the same reason: docs/19-architecture.md
// puts host input in platform/ behind an interface, so sim/ never learns what a pointer is
// and a Godot port replaces one small file.
//
// It reports *state*, not events -- where the pointer is, whether a button is down, and
// whether it went down or came up since the last read. A screen that polls this on the frame
// it draws cannot get a different answer than the one it drew, which is what stops a drag
// from lurching when a browser coalesces two moves into one event.

/** Pointer position in CSS pixels relative to the target element, plus button state. */
export type PointerState = {
  readonly x: number;
  readonly y: number;
  readonly down: boolean;
  /** True on the single frame the primary button went down. */
  readonly pressed: boolean;
  /** True on the single frame it came back up. */
  readonly released: boolean;
  /** True on the single frame the secondary button went down. Rotation, in the grid. */
  readonly secondary: boolean;
};

export type Pointer = {
  /**
   * Read the current state and clear the one-frame edges.
   *
   * Called once per frame. Reading twice in a frame is a bug rather than a supported
   * pattern: the second read would see `pressed` false and miss the click.
   */
  take: () => PointerState;
  detach: () => void;
};

export function attachPointer(target: HTMLElement): Pointer {
  let x = 0;
  let y = 0;
  let down = false;
  let pressed = false;
  let released = false;
  let secondary = false;

  const track = (event: PointerEvent): void => {
    const bounds = target.getBoundingClientRect();
    x = event.clientX - bounds.left;
    y = event.clientY - bounds.top;
  };

  const onMove = (event: PointerEvent): void => track(event);

  const onDown = (event: PointerEvent): void => {
    track(event);
    if (event.button !== 0) return;
    down = true;
    pressed = true;
    // Capture, so a drag that leaves the canvas still reports its release. Without it,
    // dragging an item off the window drops the gesture and the item sticks to the cursor.
    target.setPointerCapture(event.pointerId);
  };

  const onUp = (event: PointerEvent): void => {
    track(event);
    if (event.button !== 0) return;
    down = false;
    released = true;
    if (target.hasPointerCapture(event.pointerId)) target.releasePointerCapture(event.pointerId);
  };

  // Losing the pointer with a button held would otherwise leave a drag running forever, the
  // same failure the keyboard adapter's blur handler exists to prevent.
  const onCancel = (): void => {
    if (down) released = true;
    down = false;
  };

  /**
   * The right-click, and the only reliable way to see one mid-drag.
   *
   * `contextmenu` rather than a `pointerdown` with `button === 2`, which is the obvious
   * implementation and does not work: once the primary button has taken pointer capture,
   * Chromium delivers no second `pointerdown` for the additional button -- verified by
   * instrumenting the canvas, which saw `pointerdown:0` and then only `contextmenu:2`.
   * A rotate that silently stops working the moment you are actually dragging something is
   * worse than no rotate at all.
   *
   * It also has to be prevented regardless, or the browser menu covers the grid.
   */
  const onContextMenu = (event: Event): void => {
    event.preventDefault();
    secondary = true;
  };

  target.addEventListener("pointermove", onMove);
  target.addEventListener("pointerdown", onDown);
  target.addEventListener("pointerup", onUp);
  target.addEventListener("pointercancel", onCancel);
  target.addEventListener("contextmenu", onContextMenu);

  return {
    take(): PointerState {
      const state: PointerState = { x, y, down, pressed, released, secondary };
      pressed = false;
      released = false;
      secondary = false;
      return state;
    },
    detach(): void {
      target.removeEventListener("pointermove", onMove);
      target.removeEventListener("pointerdown", onDown);
      target.removeEventListener("pointerup", onUp);
      target.removeEventListener("pointercancel", onCancel);
      target.removeEventListener("contextmenu", onContextMenu);
    },
  };
}
