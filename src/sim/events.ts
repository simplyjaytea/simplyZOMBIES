// The core event vocabulary, from docs/21-extensibility.md#core-events.
//
// docs/21: "an event states *what happened*, never *what should happen next*.
// `bite.landed`, not `apply_infection`. The moment an event carries an imperative, it's a
// function call wearing a costume."
//
// Most of these have no publisher yet -- the systems that fire them arrive in Milestones 1
// and 2. They are declared now because docs/21 also rules out registering event types at
// runtime: the vocabulary is fixed and versioned, because it is part of the replay record.

import type { EntityId } from "./kernel/entities";

export type GameEvent =
  // Time
  | { type: "phase.changed"; phase: string; previous: string }
  | { type: "day.started"; day: number }
  | { type: "night.fell"; day: number }
  | { type: "week.elapsed"; week: number }

  // Combat
  /**
   * A blow landed. `damage` is here rather than left for the consumer to derive because the
   * attacker is the only one who knows what swung: the health module would otherwise have to
   * reach into the melee module's components to find out what hit it, which is exactly the
   * coupling docs/20's ownership rule exists to prevent.
   */
  | {
      type: "attack.connected";
      attacker: EntityId;
      target: EntityId;
      bodyPart: string;
      damage: number;
    }
  | { type: "bite.landed"; victim: EntityId; source: EntityId; bodyPart: string }
  | { type: "grab.started"; victim: EntityId; source: EntityId }
  /**
   * Knocked off balance, and for how long. Duration is on the event for the same reason
   * `damage` is on `attack.connected`: docs/09 says blunt weapons stagger better than blades,
   * so the length of it is a property of what swung, and only the attacker knows that. The
   * target still decides what being staggered *does* to it.
   */
  | { type: "entity.staggered"; entity: EntityId; ticks: number }
  | { type: "entity.killed"; entity: EntityId; killer: EntityId | null }

  // Health
  /**
   * Effort spent. How a system pays for an action without writing to a Health component it
   * does not own -- the same route `noise.emitted` takes to a field its publisher never
   * touches. Melee publishes it per swing; sprinting and the stance ladder will publish the
   * same event, which is the point of it being a fact rather than a melee-shaped call.
   */
  | { type: "stamina.spent"; entity: EntityId; amount: number }
  | { type: "injury.sustained"; entity: EntityId; injury: string; bodyPart: string }
  | { type: "injury.treated"; entity: EntityId; injury: string; treatedBy: EntityId }
  | { type: "bleeding.started"; entity: EntityId; bodyPart: string }
  | { type: "infection.staged"; entity: EntityId; stage: number }
  | { type: "survivor.turned"; entity: EntityId }

  // Attention
  | { type: "noise.emitted"; x: number; y: number; magnitude: number; source: EntityId | null }
  | { type: "light.changed"; entity: EntityId; magnitude: number }
  | { type: "scent.accumulated"; x: number; y: number; magnitude: number }

  // Colony
  | { type: "survivor.joined"; entity: EntityId }
  | { type: "survivor.died"; entity: EntityId; cause: string }
  | { type: "survivor.left"; entity: EntityId; reason: string }
  | { type: "mood.threshold"; entity: EntityId; threshold: string }
  | { type: "relationship.changed"; a: EntityId; b: EntityId; delta: number }

  // Structure
  | { type: "structure.built"; entity: EntityId; structureId: string }
  | { type: "structure.damaged"; entity: EntityId; amount: number }
  | { type: "structure.breached"; entity: EntityId }
  | { type: "trap.triggered"; entity: EntityId; victim: EntityId }

  // World
  | { type: "weather.changed"; state: string; previous: string }
  | { type: "decay.event"; eventId: string }
  | { type: "site.depleted"; siteId: string }
  | { type: "mutation.wave"; wave: number }

  // Items
  | { type: "item.equipped"; entity: EntityId; item: EntityId; slot: string }
  | { type: "item.broke"; entity: EntityId; item: EntityId }
  | { type: "modification.applied"; item: EntityId; consumable: string }
  | { type: "modification.failed"; item: EntityId; consumable: string };

export type EventType = GameEvent["type"];

/** Narrow a GameEvent to a single variant by its type tag. */
export type EventOf<T extends EventType> = Extract<GameEvent, { type: T }>;
