// The inventory screen.
//
// The first screen in the game, and the one docs/19-architecture.md#repository-layout
// reserved `src/ui/` for.
//
// Three rules shape everything here, and none of them are about drawing:
//
//   1. **It reads a snapshot, never the world.** `inventoryView` hands over plain data, so
//      this file cannot reach into components even by accident. That is the layer rule from
//      docs/19 made mechanical, and it is also what a networked client would receive.
//   2. **It proposes; the simulation decides.** Every gesture becomes a `Command` on the
//      queue. Nothing here mutates anything, so a drag lands on a tick and goes into the
//      replay record (docs/19#determinism) -- and a bug in this file cannot produce a state
//      the sim would have refused.
//   3. **No numbers except counts.** No kilograms, no capacity bar, no condition percentage.
//      docs/01-hardcore-contract.md clause 4 bans "any UI that would collapse this
//      uncertainty into a number", and the grid is what replaces it: you do not read that
//      the pack is nearly full, you see that the axe will not fit. A stack count stays,
//      because knowing you have three bandages is not uncertainty being collapsed.

import type { CommandQueue } from "../sim/kernel/commands";
import type { EntityId } from "../sim/kernel/entities";
import type { ContainerView, InventoryView, ItemView } from "../sim/modules/inventory";
import type { PointerState } from "../platform/pointer";
import { CONDITION_TINTS } from "../render/palette";
import { drawPaperdoll } from "../render/paperdoll";
import { outlineMetrics } from "../render/sprites/outline";
import type { ConditionView } from "../sim/condition";
import { stanceSpec } from "../sim/stances";

/** Cell size in CSS pixels. Big enough to drop a 1x1 into without fighting the mouse. */
const CELL = 34;
const CELL_GAP = 1;

/** Padding around a panel, and between panels. */
const PAD = 14;
const PANEL_GAP = 12;

/** Height of a panel's title line. */
const TITLE_H = 18;

/** Wide enough for a two-cell slot plus the item's name beside it. */
const SLOT_COLUMN_W = CELL * 2 + 170;

/**
 * How tall the condition paperdoll's figure stands, in pixels, and the width its prose column
 * gets.
 *
 * Larger than the on-canvas glimpse, because this is the tier that is *read* rather than glanced
 * at: docs/05 wants located conditions "sitting on the part they are on", and a reader has to be
 * able to tell which limb a line of prose is about by looking at the figure beside it.
 */
const DOLL_HEIGHT = 168;
/**
 * Wide enough for the longest line the prose table can produce.
 *
 * Sized by measurement rather than by guess: at 12px monospace the widest entry is `hands --
 * steady enough for fine work` at about 260 px, plus the state dot and its gap. It overflowed the
 * panel at 250, which is the kind of thing only running the screen shows.
 */
const DOLL_PROSE_W = 330;
/** Line height for the per-part prose. Matches the 12px monospace the rest of the screen uses. */
const DOLL_LINE_H = 16;

const COLOURS = {
  scrim: "rgba(8, 9, 10, 0.93)",
  panel: "#15181a",
  panelEdge: "#2b3033",
  cell: "#1e2225",
  cellEdge: "#2b3033",
  slot: "#191d20",
  item: "#3a4a3e",
  itemEdge: "#6f8a72",
  itemDragging: "#46583f",
  text: "#c9c4b8",
  dim: "#7b776e",
  good: "rgba(120, 200, 130, 0.30)",
  bad: "rgba(200, 90, 80, 0.34)",
  overload: "#b8564c",
} as const;

/** Where a grid ended up on screen, so a pointer can be turned back into a cell. */
type PlacedGrid = {
  readonly view: ContainerView;
  readonly x: number;
  readonly y: number;
};

type PlacedSlot = {
  readonly slot: string;
  readonly item: ItemView | null;
  readonly x: number;
  readonly y: number;
};

/** What is currently in the player's hand, mid-drag. */
type Drag = {
  readonly item: EntityId;
  readonly view: ItemView;
  /** Which cell of the item was grabbed, so it does not snap its top-left to the cursor. */
  readonly grabX: number;
  readonly grabY: number;
  rotated: boolean;
};

/**
 * Can this item go here?
 *
 * The screen asks so it can tint the drop target, and it deliberately answers with a *local*
 * approximation -- bounds and overlap within the grid it can see. It does not know about
 * nesting depth or containment cycles, and it must not pretend to: the simulation refuses
 * those on the tick, and duplicating the rule here is how the two answers drift apart.
 * A green tint that turns out to be refused is a rare, honest outcome; a rule implemented
 * twice is a bug waiting.
 */
function fitsLocally(grid: ContainerView, drag: Drag, x: number, y: number): boolean {
  const w = drag.rotated ? drag.view.h : drag.view.w;
  const h = drag.rotated ? drag.view.w : drag.view.h;
  if (x < 0 || y < 0 || x + w > grid.w || y + h > grid.h) return false;

  for (const other of grid.items) {
    if (other.item === drag.item) continue;
    if (x < other.x + other.w && other.x < x + w && y < other.y + other.h && other.y < y + h) {
      return false;
    }
  }
  return true;
}

export class InventoryScreen {
  open = false;

  private drag: Drag | null = null;
  private grids: PlacedGrid[] = [];
  private slots: PlacedSlot[] = [];

  /**
   * Rotate what is in hand, from the keyboard.
   *
   * The same gesture as right-click, bound separately because a drag is a held button and
   * some pointers cannot report a second one mid-gesture -- see the note on `contextmenu` in
   * platform/pointer.ts. No-op with nothing in hand, so the key is safe to hold.
   */
  rotate(): void {
    if (this.drag !== null) this.drag.rotated = !this.drag.rotated;
  }

  toggle(): void {
    this.open = !this.open;
    // Dropping the drag on close, so reopening does not resume a gesture whose pointer
    // press happened a minute ago.
    if (!this.open) this.drag = null;
  }

  /**
   * Handle a frame's pointer state and draw.
   *
   * Laid out twice: once to measure, once to draw at an offset that centres the result. The
   * alternative -- packing from the top-left corner -- puts the screen under the HUD and
   * leaves it stranded in a corner on a wide monitor, and a centred layout cannot be faked
   * with a fixed offset because how many panels there are depends on what you are wearing.
   *
   * Input and layout share the pass, because hit-testing needs the same rectangles drawing
   * does. Computing them twice and keeping the two in agreement is how you get a screen you
   * can see but not click.
   */
  draw(
    ctx: CanvasRenderingContext2D,
    view: InventoryView,
    condition: ConditionView | null,
    pointer: PointerState,
    commands: CommandQueue,
    width: number,
    height: number,
  ): void {
    if (!this.open) return;

    ctx.save();
    ctx.fillStyle = COLOURS.scrim;
    ctx.fillRect(0, 0, width, height);
    ctx.font = "12px ui-monospace, SFMono-Regular, Menlo, monospace";
    ctx.textBaseline = "top";

    const panels = this.layout(view, condition, height);
    const offsetX = Math.max(PAD, Math.round((width - panels.width) / 2));
    const offsetY = Math.max(PAD, Math.round((height - panels.height) / 2));

    this.grids = [];
    this.slots = [];

    // ---- worn and held ----
    const slotPanel = panels.slotPanel;
    this.drawPanel(ctx, offsetX + slotPanel.x, offsetY + slotPanel.y, slotPanel.w, slotPanel.h);
    ctx.fillStyle = COLOURS.text;
    ctx.fillText("worn and held", offsetX + slotPanel.x + PAD, offsetY + slotPanel.y + 6);

    let slotY = offsetY + slotPanel.y + TITLE_H + 8;
    for (const { slot, item } of view.slots) {
      const x = offsetX + slotPanel.x + PAD;
      this.slots.push({ slot, item, x, y: slotY });

      ctx.fillStyle = COLOURS.slot;
      ctx.fillRect(x, slotY, CELL * 2, CELL);
      ctx.strokeStyle = COLOURS.cellEdge;
      ctx.strokeRect(x + 0.5, slotY + 0.5, CELL * 2 - 1, CELL - 1);

      if (item !== null && this.drag?.item !== item.item) {
        ctx.fillStyle = COLOURS.item;
        ctx.fillRect(x + 2, slotY + 2, CELL * 2 - 4, CELL - 4);
        ctx.strokeStyle = COLOURS.itemEdge;
        ctx.strokeRect(x + 2.5, slotY + 2.5, CELL * 2 - 5, CELL - 5);
      }

      ctx.fillStyle = item === null ? COLOURS.dim : COLOURS.text;
      ctx.fillText(item === null ? slot : item.name, x + CELL * 2 + 8, slotY + CELL / 2 - 6);
      slotY += CELL + 4;
    }

    // ---- condition ----
    //
    // The paperdoll, and one line of prose per part. **No numbers, and nothing a number could be
    // derived from** -- rule 3 at the top of this file, which docs/05 sharpens into "colour, never
    // fill": a bar with the figure hidden behind a hover is still a bar.
    if (condition !== null && panels.dollPanel !== null) {
      const doll = panels.dollPanel;
      const px = offsetX + doll.x;
      const py = offsetY + doll.y;
      this.drawPanel(ctx, px, py, doll.w, doll.h);

      ctx.fillStyle = COLOURS.text;
      // The title says what posture, because the figure below is drawn in it and a reader should
      // not have to infer a mechanic from a silhouette.
      ctx.fillText(`condition -- ${stanceSpec(condition.stance).name}`, px + PAD, py + 6);

      const box = outlineMetrics(DOLL_HEIGHT);
      drawPaperdoll(ctx, condition, {
        height: DOLL_HEIGHT,
        anchorX: px + PAD + box.anchorX,
        anchorY: py + TITLE_H + PAD + box.anchorY,
      });

      let lineY = py + TITLE_H + PAD;
      const proseX = px + PAD * 2 + box.width;
      for (const part of condition.parts) {
        // A dot in the part's tint, then the part, then what it says. The dot is the same colour
        // the limb is drawn in, which is the whole of how a line of prose is tied to a place on
        // the body -- and it is why the tints have to differ in lightness as well as hue.
        ctx.fillStyle = CONDITION_TINTS[part.state] ?? COLOURS.text;
        ctx.beginPath();
        ctx.ellipse(proseX + 4, lineY + 6, 4, 4, 0, 0, Math.PI * 2);
        ctx.fill();

        ctx.fillStyle = part.state === 0 ? COLOURS.dim : COLOURS.text;
        ctx.fillText(`${part.part} -- ${part.prose}`, proseX + 14, lineY);
        lineY += DOLL_LINE_H;
      }
    }

    // ---- the grids ----
    for (const placed of panels.gridPanels) {
      const px = offsetX + placed.x;
      const py = offsetY + placed.y;
      this.drawPanel(ctx, px, py, placed.w, placed.h);
      ctx.fillStyle = COLOURS.text;
      ctx.fillText(placed.view.label, px + PAD, py + 6);

      const originX = px + PAD;
      const originY = py + TITLE_H + 8;
      this.grids.push({ view: placed.view, x: originX, y: originY });
      this.drawGrid(ctx, placed.view, originX, originY);
    }

    this.handlePointer(pointer, commands);
    this.drawDragGhost(ctx, pointer);
    this.drawFooter(ctx, view, width, height);
    ctx.restore();
  }

  /**
   * Measure the panels, in coordinates relative to the block's own top-left.
   *
   * Grids flow down a column and wrap to a new one when the next would run off the bottom of
   * the viewport, so a survivor wearing a pack, a rig and two pouches gets a second column
   * rather than a panel hanging off the screen.
   */
  private layout(
    view: InventoryView,
    condition: ConditionView | null,
    height: number,
  ): {
    width: number;
    height: number;
    slotPanel: { x: number; y: number; w: number; h: number };
    dollPanel: { x: number; y: number; w: number; h: number } | null;
    gridPanels: readonly { view: ContainerView; x: number; y: number; w: number; h: number }[];
  } {
    const slotPanel = {
      x: 0,
      y: 0,
      w: SLOT_COLUMN_W,
      h: TITLE_H + PAD + view.slots.length * (CELL + 4),
    };

    // Under the slots, in the same column, and that placement is the argument for it: docs/10's
    // armour coverage is per part, so the parts want to be read against the things worn over them.
    // Putting it beside the grid instead would have made it a second inventory.
    const dollPanel =
      condition === null
        ? null
        : {
            x: 0,
            y: slotPanel.h + PANEL_GAP,
            w: Math.max(SLOT_COLUMN_W, outlineMetrics(DOLL_HEIGHT).width + DOLL_PROSE_W + PAD * 3),
            h: Math.max(
              outlineMetrics(DOLL_HEIGHT).height + TITLE_H + PAD * 2,
              TITLE_H + PAD * 2 + condition.parts.length * DOLL_LINE_H,
            ),
          };

    const gridPanels: { view: ContainerView; x: number; y: number; w: number; h: number }[] = [];
    const available = height - PAD * 4;
    // Clear of the *whole* left column, not just the slots. The condition panel is the wider of
    // the two, so measuring from `slotPanel.w` would have run the first grid straight over it.
    let x = (dollPanel === null ? slotPanel.w : Math.max(slotPanel.w, dollPanel.w)) + PANEL_GAP;
    let y = 0;
    let columnW = 0;

    for (const container of view.containers) {
      const w = container.w * CELL + PAD * 2;
      const h = container.h * CELL + TITLE_H + PAD + 8;

      if (y > 0 && y + h > available) {
        x += columnW + PANEL_GAP;
        y = 0;
        columnW = 0;
      }
      columnW = Math.max(columnW, w);
      gridPanels.push({ view: container, x, y, w, h });
      y += h + PANEL_GAP;
    }

    // The left column is as wide as its widest panel and as tall as its last one, so the grids
    // pack beside the pair rather than beside the slots alone.
    const leftW = dollPanel === null ? slotPanel.w : Math.max(slotPanel.w, dollPanel.w);
    const leftH = dollPanel === null ? slotPanel.h : dollPanel.y + dollPanel.h;
    const right = gridPanels.reduce((max, panel) => Math.max(max, panel.x + panel.w), leftW);
    const bottom = gridPanels.reduce((max, panel) => Math.max(max, panel.y + panel.h), leftH);
    return { width: right, height: bottom, slotPanel, dollPanel, gridPanels };
  }

  private drawPanel(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    w: number,
    h: number,
  ): void {
    ctx.fillStyle = COLOURS.panel;
    ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = COLOURS.panelEdge;
    ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
  }

  private drawGrid(
    ctx: CanvasRenderingContext2D,
    container: ContainerView,
    originX: number,
    originY: number,
  ): void {
    for (let cy = 0; cy < container.h; cy++) {
      for (let cx = 0; cx < container.w; cx++) {
        const x = originX + cx * CELL;
        const y = originY + cy * CELL;
        ctx.fillStyle = COLOURS.cell;
        ctx.fillRect(x + CELL_GAP, y + CELL_GAP, CELL - CELL_GAP * 2, CELL - CELL_GAP * 2);
      }
    }

    for (const item of container.items) {
      if (this.drag?.item === item.item) continue;
      this.drawItem(ctx, item, originX + item.x * CELL, originY + item.y * CELL, false);
    }
  }

  private drawItem(
    ctx: CanvasRenderingContext2D,
    item: ItemView,
    x: number,
    y: number,
    dragging: boolean,
  ): void {
    const w = item.w * CELL;
    const h = item.h * CELL;

    ctx.fillStyle = dragging ? COLOURS.itemDragging : COLOURS.item;
    ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
    ctx.strokeStyle = COLOURS.itemEdge;
    ctx.strokeRect(x + 2.5, y + 2.5, w - 5, h - 5);

    // The name, clipped to the footprint. A 1x1 shows a couple of letters, which is enough
    // to tell a bandage from a tin once you have seen both -- and the tooltip on hover is
    // where the full name lives.
    ctx.save();
    ctx.beginPath();
    ctx.rect(x + 3, y + 3, w - 6, h - 6);
    ctx.clip();
    ctx.fillStyle = COLOURS.text;
    ctx.fillText(item.name, x + 6, y + 6);
    if (item.condition !== "sound") {
      ctx.fillStyle = COLOURS.dim;
      ctx.fillText(item.condition, x + 6, y + h - 18);
    }
    ctx.restore();

    // The one number on the screen, and it counts objects rather than measuring anything.
    if (item.count > 1) {
      const label = `x${item.count}`;
      ctx.fillStyle = COLOURS.text;
      ctx.textAlign = "right";
      ctx.fillText(label, x + w - 6, y + h - 16);
      ctx.textAlign = "left";
    }
  }

  /** Turn a pointer position into a container and a cell, or `null` if it is over neither. */
  private cellAt(x: number, y: number): { grid: PlacedGrid; cx: number; cy: number } | null {
    for (const grid of this.grids) {
      const cx = Math.floor((x - grid.x) / CELL);
      const cy = Math.floor((y - grid.y) / CELL);
      if (cx < 0 || cy < 0 || cx >= grid.view.w || cy >= grid.view.h) continue;
      return { grid, cx, cy };
    }
    return null;
  }

  private slotAt(x: number, y: number): PlacedSlot | null {
    for (const slot of this.slots) {
      if (x >= slot.x && x < slot.x + CELL * 2 && y >= slot.y && y < slot.y + CELL) {
        return slot;
      }
    }
    return null;
  }

  /**
   * Pick up, rotate, and put down.
   *
   * Every branch that changes anything ends in a command. The only state this method owns is
   * `this.drag`, which is a fact about the pointer rather than about the world -- exactly the
   * split that keeps `ui/` unable to write to `sim/`.
   */
  private handlePointer(pointer: PointerState, commands: CommandQueue): void {
    // Rotate whatever is in hand. Right-click rather than a modifier because it is the
    // gesture every game in this genre already taught the player.
    if (pointer.secondary && this.drag !== null) {
      this.drag.rotated = !this.drag.rotated;
      return;
    }

    if (pointer.pressed && this.drag === null) {
      const hit = this.cellAt(pointer.x, pointer.y);
      if (hit !== null) {
        const item = hit.grid.view.items.find(
          (candidate) =>
            hit.cx >= candidate.x &&
            hit.cx < candidate.x + candidate.w &&
            hit.cy >= candidate.y &&
            hit.cy < candidate.y + candidate.h,
        );
        if (item !== undefined) {
          this.drag = {
            item: item.item,
            view: item,
            grabX: hit.cx - item.x,
            grabY: hit.cy - item.y,
            rotated: item.rotated,
          };
        }
        return;
      }

      const slot = this.slotAt(pointer.x, pointer.y);
      if (slot !== null && slot.item !== null) {
        this.drag = {
          item: slot.item.item,
          view: slot.item,
          grabX: 0,
          grabY: 0,
          rotated: false,
        };
      }
      return;
    }

    if (!pointer.released || this.drag === null) return;

    const drag = this.drag;
    this.drag = null;

    const slot = this.slotAt(pointer.x, pointer.y);
    if (slot !== null) {
      commands.push({ type: "item.equip", item: drag.item, slot: slot.slot });
      return;
    }

    const hit = this.cellAt(pointer.x, pointer.y);
    if (hit === null) {
      // Released over nothing: put it down. Dropping is the only destructive gesture here,
      // and it is also the one docs/10's "you found more than you can carry" moment needs
      // to be one action rather than a menu.
      commands.push({ type: "item.drop", item: drag.item });
      return;
    }

    commands.push({
      type: "item.move",
      item: drag.item,
      container: hit.grid.view.container,
      x: hit.cx - drag.grabX,
      y: hit.cy - drag.grabY,
      rotated: drag.rotated,
    });
  }

  /** The item under the cursor, plus a tint saying whether it would land there. */
  private drawDragGhost(ctx: CanvasRenderingContext2D, pointer: PointerState): void {
    const drag = this.drag;
    if (drag === null) return;

    const hit = this.cellAt(pointer.x, pointer.y);
    const w = drag.rotated ? drag.view.h : drag.view.w;
    const h = drag.rotated ? drag.view.w : drag.view.h;

    if (hit !== null) {
      const x = hit.cx - drag.grabX;
      const y = hit.cy - drag.grabY;
      ctx.fillStyle = fitsLocally(hit.grid.view, drag, x, y) ? COLOURS.good : COLOURS.bad;
      ctx.fillRect(hit.grid.x + x * CELL, hit.grid.y + y * CELL, w * CELL, h * CELL);
    }

    const ghost: ItemView = { ...drag.view, w, h, rotated: drag.rotated };
    ctx.globalAlpha = 0.9;
    this.drawItem(
      ctx,
      ghost,
      pointer.x - drag.grabX * CELL - CELL / 2,
      pointer.y - drag.grabY * CELL - CELL / 2,
      true,
    );
    ctx.globalAlpha = 1;
  }

  /**
   * The help line, and the one thing that says how loaded you are.
   *
   * A word, not a number and not a bar. docs/01 clause 4 bans the bar; the word is the same
   * treatment injuries get -- "she's favoring that leg" rather than a percentage.
   */
  private drawFooter(
    ctx: CanvasRenderingContext2D,
    view: InventoryView,
    width: number,
    height: number,
  ): void {
    ctx.fillStyle = COLOURS.dim;
    ctx.fillText(
      "drag to move   right-click or R rotates   drag onto a slot to wear   drag out to drop   Tab closes",
      PAD,
      height - 24,
    );

    if (view.overload <= 1) return;
    const word = view.overload > 1.6 ? "you can barely move" : "you are weighed down";
    ctx.fillStyle = COLOURS.overload;
    ctx.textAlign = "right";
    ctx.fillText(word, width - PAD, height - 24);
    ctx.textAlign = "left";
  }
}
