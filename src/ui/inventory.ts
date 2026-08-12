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
import type { ConditionView, PartView } from "../sim/condition";
import type { SurvivorBodyPart } from "../sim/combat";
import { stanceSpec } from "../sim/stances";

/** Cell size in CSS pixels. Big enough to drop a 1x1 into without fighting the mouse. */
const CELL = 34;
const CELL_GAP = 1;

/** Padding around a panel, and between panels. */
const PAD = 14;
const PANEL_GAP = 12;

/** Height of a panel's title line. */
const TITLE_H = 18;

/**
 * One body in two views. Equipment arranges real drop targets around it; injuries replaces them
 * with the privacy-filtered prose from `ConditionView`. Both draw the same pose and region tints.
 */
const BODY_PANEL_W = 548;
const BODY_PANEL_H = 390;
const DOLL_HEIGHT = 248;
const TAB_W = 112;
const TAB_H = 26;
const EQUIP_SLOT_W = CELL * 2;
const EQUIP_SLOT_H = CELL;
const INJURY_ROW_H = 27;

export type BodyPanelView = "equipment" | "injuries";

export const BODY_PANEL_VIEWS: readonly BodyPanelView[] = ["equipment", "injuries"];

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
  readonly w: number;
  readonly h: number;
};

type HitRect<T> = {
  readonly value: T;
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
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
  private tabs: HitRect<BodyPanelView>[] = [];
  private injuryRows: HitRect<SurvivorBodyPart>[] = [];
  private bodyView: BodyPanelView = "equipment";
  private selectedPart: SurvivorBodyPart = "head";

  /** Exposed for input adapters and focused UI tests; tab clicks call the same method. */
  selectBodyView(view: BodyPanelView): void {
    this.bodyView = view;
    if (view === "injuries") this.drag = null;
  }

  /** The active tab, without exposing any simulation state. */
  currentBodyView(): BodyPanelView {
    return this.bodyView;
  }

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

    const panels = this.layout(view, height);
    const offsetX = Math.max(PAD, Math.round((width - panels.width) / 2));
    const offsetY = Math.max(PAD, Math.round((height - panels.height) / 2));

    this.grids = [];
    this.slots = [];
    this.tabs = [];
    this.injuryRows = [];

    const bodyPanel = panels.bodyPanel;
    const bodyX = offsetX + bodyPanel.x;
    const bodyY = offsetY + bodyPanel.y;
    this.drawBodyPanel(ctx, view, condition, bodyX, bodyY);

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
    height: number,
  ): {
    width: number;
    height: number;
    bodyPanel: { x: number; y: number; w: number; h: number };
    gridPanels: readonly { view: ContainerView; x: number; y: number; w: number; h: number }[];
  } {
    const bodyPanel = { x: 0, y: 0, w: BODY_PANEL_W, h: BODY_PANEL_H };

    const gridPanels: { view: ContainerView; x: number; y: number; w: number; h: number }[] = [];
    const available = height - PAD * 4;
    let x = bodyPanel.w + PANEL_GAP;
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

    const right = gridPanels.reduce((max, panel) => Math.max(max, panel.x + panel.w), bodyPanel.w);
    const bottom = gridPanels.reduce((max, panel) => Math.max(max, panel.y + panel.h), bodyPanel.h);
    return { width: right, height: bottom, bodyPanel, gridPanels };
  }

  private drawBodyPanel(
    ctx: CanvasRenderingContext2D,
    view: InventoryView,
    condition: ConditionView | null,
    x: number,
    y: number,
  ): void {
    this.drawPanel(ctx, x, y, BODY_PANEL_W, BODY_PANEL_H);
    ctx.fillStyle = COLOURS.text;
    ctx.fillText(
      condition === null ? "survivor" : `survivor -- ${stanceSpec(condition.stance).name}`,
      x + PAD,
      y + 7,
    );

    for (const [index, tab] of BODY_PANEL_VIEWS.entries()) {
      const tx = x + BODY_PANEL_W - PAD - TAB_W * (BODY_PANEL_VIEWS.length - index);
      const ty = y + 1;
      this.tabs.push({ value: tab, x: tx, y: ty, w: TAB_W, h: TAB_H });
      ctx.fillStyle = tab === this.bodyView ? COLOURS.cell : COLOURS.panel;
      ctx.fillRect(tx, ty, TAB_W, TAB_H);
      ctx.strokeStyle = tab === this.bodyView ? COLOURS.itemEdge : COLOURS.panelEdge;
      ctx.strokeRect(tx + 0.5, ty + 0.5, TAB_W - 1, TAB_H - 1);
      ctx.fillStyle = tab === this.bodyView ? COLOURS.text : COLOURS.dim;
      ctx.fillText(tab, tx + 12, ty + 6);
    }

    if (condition === null) {
      ctx.fillStyle = COLOURS.dim;
      ctx.fillText("no condition record", x + PAD, y + TITLE_H + PAD);
      return;
    }

    if (this.bodyView === "equipment") this.drawEquipmentBody(ctx, view, condition, x, y);
    else this.drawInjuryBody(ctx, condition, x, y);
  }

  private drawEquipmentBody(
    ctx: CanvasRenderingContext2D,
    view: InventoryView,
    condition: ConditionView,
    x: number,
    y: number,
  ): void {
    const box = outlineMetrics(DOLL_HEIGHT);
    const anchorX = x + Math.round(BODY_PANEL_W / 2);
    const anchorY = y + 52 + box.anchorY;
    drawPaperdoll(ctx, condition, { height: DOLL_HEIGHT, anchorX, anchorY });

    const byName = new Map(view.slots.map((entry) => [entry.slot, entry]));
    const placements: readonly { slot: string; x: number; y: number }[] = [
      { slot: "head", x: Math.round((BODY_PANEL_W - EQUIP_SLOT_W) / 2), y: 43 },
      { slot: "back", x: 24, y: 104 },
      { slot: "vest", x: BODY_PANEL_W - 24 - EQUIP_SLOT_W, y: 104 },
      { slot: "primary", x: 24, y: 220 },
      { slot: "secondary", x: BODY_PANEL_W - 24 - EQUIP_SLOT_W, y: 220 },
      { slot: "belt", x: 24, y: 324 },
      { slot: "torso", x: BODY_PANEL_W - 24 - EQUIP_SLOT_W, y: 324 },
    ];

    for (const placed of placements) {
      const entry = byName.get(placed.slot);
      if (entry === undefined) continue;
      this.drawBodySlot(ctx, entry.slot, entry.item, x + placed.x, y + placed.y);
    }
  }

  private drawBodySlot(
    ctx: CanvasRenderingContext2D,
    slot: string,
    item: ItemView | null,
    x: number,
    y: number,
  ): void {
    this.slots.push({ slot, item, x, y, w: EQUIP_SLOT_W, h: EQUIP_SLOT_H });
    ctx.fillStyle = COLOURS.slot;
    ctx.fillRect(x, y, EQUIP_SLOT_W, EQUIP_SLOT_H);
    ctx.strokeStyle = COLOURS.cellEdge;
    ctx.strokeRect(x + 0.5, y + 0.5, EQUIP_SLOT_W - 1, EQUIP_SLOT_H - 1);
    if (item !== null && this.drag?.item !== item.item) {
      ctx.fillStyle = COLOURS.item;
      ctx.fillRect(x + 2, y + 2, EQUIP_SLOT_W - 4, EQUIP_SLOT_H - 4);
      ctx.strokeStyle = COLOURS.itemEdge;
      ctx.strokeRect(x + 2.5, y + 2.5, EQUIP_SLOT_W - 5, EQUIP_SLOT_H - 5);
    }
    ctx.fillStyle = item === null ? COLOURS.dim : COLOURS.text;
    ctx.save();
    ctx.beginPath();
    ctx.rect(x + 4, y + 2, EQUIP_SLOT_W - 8, EQUIP_SLOT_H - 4);
    ctx.clip();
    ctx.fillText(item === null ? slot : item.name, x + 6, y + 10);
    ctx.restore();
  }

  private drawInjuryBody(
    ctx: CanvasRenderingContext2D,
    condition: ConditionView,
    x: number,
    y: number,
  ): void {
    const box = outlineMetrics(DOLL_HEIGHT);
    drawPaperdoll(ctx, condition, {
      height: DOLL_HEIGHT,
      anchorX: x + 142,
      anchorY: y + 71 + box.anchorY,
    });

    const listX = x + 276;
    const listY = y + 52;
    for (const [index, part] of condition.parts.entries()) {
      const rowY = listY + index * INJURY_ROW_H;
      this.injuryRows.push({ value: part.part, x: listX, y: rowY, w: 248, h: INJURY_ROW_H });
      if (part.part === this.selectedPart) {
        ctx.fillStyle = COLOURS.cell;
        ctx.fillRect(listX, rowY, 248, INJURY_ROW_H - 2);
      }
      ctx.fillStyle = CONDITION_TINTS[part.state] ?? COLOURS.text;
      ctx.beginPath();
      ctx.ellipse(listX + 7, rowY + 12, 4, 4, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = part.state === 0 ? COLOURS.dim : COLOURS.text;
      ctx.fillText(part.part, listX + 18, rowY + 6);
    }

    const selected =
      condition.parts.find((part) => part.part === this.selectedPart) ?? condition.parts[0];
    if (selected !== undefined) this.drawInjuryDetails(ctx, selected, listX, y + 231, 248);
  }

  private drawInjuryDetails(
    ctx: CanvasRenderingContext2D,
    part: PartView,
    x: number,
    y: number,
    w: number,
  ): void {
    ctx.strokeStyle = COLOURS.panelEdge;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + w, y);
    ctx.stroke();
    ctx.fillStyle = CONDITION_TINTS[part.state] ?? COLOURS.text;
    ctx.fillText(part.part, x, y + 13);
    ctx.fillStyle = COLOURS.text;
    this.drawWrappedText(ctx, part.prose, x, y + 39, w, 17);
  }

  private drawWrappedText(
    ctx: CanvasRenderingContext2D,
    text: string,
    x: number,
    y: number,
    maxWidth: number,
    lineHeight: number,
  ): void {
    const words = text.split(/\s+/);
    let line = "";
    let lineY = y;
    for (const word of words) {
      const next = line === "" ? word : `${line} ${word}`;
      if (line !== "" && ctx.measureText(next).width > maxWidth) {
        ctx.fillText(line, x, lineY);
        line = word;
        lineY += lineHeight;
      } else line = next;
    }
    if (line !== "") ctx.fillText(line, x, lineY);
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
      if (x >= slot.x && x < slot.x + slot.w && y >= slot.y && y < slot.y + slot.h) {
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
    if (pointer.pressed && this.drag === null) {
      const tab = this.tabs.find((hit) => this.inside(pointer.x, pointer.y, hit));
      if (tab !== undefined) {
        this.selectBodyView(tab.value);
        return;
      }
      const injury = this.injuryRows.find((hit) => this.inside(pointer.x, pointer.y, hit));
      if (injury !== undefined) {
        this.selectedPart = injury.value;
        return;
      }
    }

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

  private inside(
    x: number,
    y: number,
    rect: { x: number; y: number; w: number; h: number },
  ): boolean {
    return x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h;
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
      this.bodyView === "equipment"
        ? "drag to move   right-click or R rotates   drag onto a body slot to wear   drag out to drop   Tab closes"
        : "select a body region for details   Equipment returns to loadout   Tab closes",
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
