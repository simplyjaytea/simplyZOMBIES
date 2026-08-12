import { describe, expect, it } from "vitest";
import { InventoryScreen } from "../../src/ui/inventory";
import { CommandQueue } from "../../src/sim/kernel/commands";
import type { InventoryView } from "../../src/sim/modules/inventory";
import type { ConditionView } from "../../src/sim/condition";
import { PartState } from "../../src/sim/modules/health";
import { Stance } from "../../src/sim/stances";
import type { PointerState } from "../../src/platform/pointer";

type Label = { text: string; x: number; y: number };

function recordingContext(labels: Label[]): CanvasRenderingContext2D {
  const state: Record<PropertyKey, unknown> = {};
  return new Proxy(state, {
    get(target, property) {
      if (property === "fillText") {
        return (text: string, x: number, y: number): void => {
          labels.push({ text, x, y });
        };
      }
      if (property === "measureText")
        return (text: string): TextMetrics => ({ width: text.length * 7 }) as TextMetrics;
      if (property in target) return target[property];
      return (): void => undefined;
    },
    set(target, property, value) {
      target[property] = value;
      return true;
    },
  }) as unknown as CanvasRenderingContext2D;
}

const IDLE: PointerState = {
  x: 0,
  y: 0,
  down: false,
  pressed: false,
  released: false,
  secondary: false,
};

const VIEW: InventoryView = {
  actor: 1,
  slots: ["back", "vest", "belt", "primary", "secondary", "head", "torso"].map((slot) => ({
    slot,
    item: null,
  })),
  containers: [{ container: 1, label: "pockets", w: 4, h: 2, items: [] }],
  overload: 0,
};

const CONDITION: ConditionView = {
  entity: 1,
  stance: Stance.Walk,
  changingStance: false,
  worst: PartState.Hurt,
  parts: [
    { part: "head", state: PartState.Unhurt, prose: "clear-eyed" },
    { part: "torso", state: PartState.Unhurt, prose: "breathing easily" },
    { part: "arms", state: PartState.Hurt, prose: "a ragged scratch" },
    { part: "hands", state: PartState.Unhurt, prose: "steady enough for fine work" },
    { part: "legs", state: PartState.Unhurt, prose: "walking easily" },
    { part: "feet", state: PartState.Unhurt, prose: "sound" },
  ],
};

function draw(screen: InventoryScreen, labels: Label[], pointer: PointerState = IDLE): void {
  screen.draw(recordingContext(labels), VIEW, CONDITION, pointer, new CommandQueue(), 1280, 720);
}

describe("the unified survivor panel", () => {
  it("opens on equipment with every real worn and held slot around the shared body", () => {
    const screen = new InventoryScreen();
    screen.toggle();
    const labels: Label[] = [];
    draw(screen, labels);

    expect(screen.currentBodyView()).toBe("equipment");
    expect(labels.map((label) => label.text)).toEqual(
      expect.arrayContaining([
        "equipment",
        "injuries",
        "head",
        "back",
        "vest",
        "belt",
        "primary",
        "secondary",
        "torso",
      ]),
    );
  });

  it("switches tabs by pointer and shows only the selected region's diagnosis details", () => {
    const screen = new InventoryScreen();
    screen.toggle();
    const labels: Label[] = [];
    draw(screen, labels);

    const injuries = labels.find((label) => label.text === "injuries") as Label;
    draw(screen, [], { ...IDLE, x: injuries.x + 2, y: injuries.y + 2, down: true, pressed: true });
    expect(screen.currentBodyView()).toBe("injuries");

    const injuryLabels: Label[] = [];
    draw(screen, injuryLabels);
    const legs = injuryLabels.find((label) => label.text === "legs") as Label;
    draw(screen, [], { ...IDLE, x: legs.x + 2, y: legs.y + 2, down: true, pressed: true });

    const selected: Label[] = [];
    draw(screen, selected);
    expect(selected.map((label) => label.text)).toContain("walking easily");
    expect(selected.map((label) => label.text)).not.toContain("clear-eyed");
  });
});
