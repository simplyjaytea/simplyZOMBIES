// The handoff's own bookkeeping.
//
// HANDOFF.md is the engineer's document and its backlog groups every task under a
// `**Done (n):**` / `**In progress (n):**` / `**Open (n):**` header. Those headers are a summary of
// the checkboxes beneath them, which means they are a second copy of a fact -- and a second copy
// nothing checks is a copy waiting to disagree.
//
// It disagreed within one session of being written. Ticking four boxes for the light channel left
// them sitting inside `Open` groups with stale counts, which is the same class of drift that
// deleting TODO.md was meant to end. So the counts are asserted here rather than maintained by
// hand: a document is not exempt from the rule that a guard nobody runs is not a guard.

import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HANDOFF = resolve(dirname(fileURLToPath(import.meta.url)), "../../HANDOFF.md");

/** `[x]` -> Done, `[~]` -> In progress, `[ ]` -> Open. */
const LABEL: Record<string, string> = { x: "Done", "~": "In progress", " ": "Open" };

type Group = { label: string; declared: number; line: number; section: string; marks: string[] };

/**
 * Every group header in the file, with the checkbox marks that belong to it.
 *
 * A group owns every top-level checkbox until the next group header or the next heading, whichever
 * comes first. That boundary matters: the "Beyond the slice" section lists tasks with no group
 * header at all, and without the heading boundary they would be counted into the last group of the
 * previous section.
 */
function groups(): Group[] {
  const out: Group[] = [];
  let current: Group | null = null;
  let section = "(top)";

  for (const [index, line] of readFileSync(HANDOFF, "utf8").split(/\r?\n/).entries()) {
    const heading = /^#{1,6}\s+(.*)$/.exec(line);
    if (heading !== null) {
      current = null;
      section = heading[1] as string;
      continue;
    }

    const header = /^\*\*(Done|In progress|Open) \((\d+)\):\*\*$/.exec(line);
    if (header !== null) {
      current = {
        label: header[1] as string,
        declared: Number(header[2]),
        line: index + 1,
        section,
        marks: [],
      };
      out.push(current);
      continue;
    }

    const item = /^- \[([x~ ])\]/.exec(line);
    if (item !== null && current !== null) current.marks.push(item[1] as string);
  }
  return out;
}

describe("HANDOFF.md's backlog groups", () => {
  it("has groups to check in the first place", () => {
    // Otherwise every assertion below passes vacuously if the file is ever restructured.
    const all = groups();
    expect(all.length).toBeGreaterThan(20);
    expect(all.some((g) => g.label === "Done")).toBe(true);
    expect(all.some((g) => g.label === "Open")).toBe(true);
  });

  it("declares a count that matches what the group holds", () => {
    const wrong = groups()
      .filter((g) => g.declared !== g.marks.length)
      .map((g) => `${HANDOFF}:${g.line} "${g.label} (${g.declared})" holds ${g.marks.length}`);
    expect(wrong).toEqual([]);
  });

  it("puts every task in the group its checkbox says it belongs to", () => {
    // The drift that actually happened: a box gets ticked in place and stays under `Open`.
    const misfiled: string[] = [];
    for (const group of groups()) {
      for (const mark of group.marks) {
        const belongs = LABEL[mark] as string;
        if (belongs !== group.label) {
          misfiled.push(
            `${HANDOFF}:${group.line} (${group.section}) — "${group.label}" group holds a [${mark}] item, which is "${belongs}"`,
          );
        }
      }
    }
    expect([...new Set(misfiled)]).toEqual([]);
  });

  it("adds the per-milestone rows up to the total row", () => {
    // The rows are a fourth copy of the same fact and the Total check below does not cover them --
    // an off-by-one in a single milestone row still sums wrong, which is exactly what happened when
    // six tasks were moved between milestones by hand.
    const text = readFileSync(HANDOFF, "utf8");
    // `3+` as well as `0`, hence the optional plus -- the row it labels is the one my first
    // version of this silently skipped, which would have let exactly the drift it guards slip by.
    const numeric = /^\|\s*(\d+\+?)\s*—[^|]*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|/gm;
    let done = 0;
    let inProgress = 0;
    let open = 0;
    let seen = 0;
    for (const row of text.matchAll(numeric)) {
      done += Number(row[2]);
      inProgress += Number(row[3]);
      open += Number(row[4]);
      seen += 1;
    }
    // Four milestone rows: 0, 1, 2 and 3+.
    expect(seen).toBe(4);

    const total =
      /\|\s*\*\*Total\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*/.exec(
        text,
      ) as RegExpExecArray;
    expect({ done, inProgress, open }).toEqual({
      done: Number(total[1]),
      inProgress: Number(total[2]),
      open: Number(total[3]),
    });
  });

  it("keeps the milestone summary table agreeing with the file", () => {
    // The table at the top is a third copy of the same fact.
    const text = readFileSync(HANDOFF, "utf8");
    const total =
      /\|\s*\*\*Total\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*/.exec(
        text,
      );
    expect(total).not.toBeNull();

    const counts = { x: 0, "~": 0, " ": 0 } as Record<string, number>;
    for (const line of text.split("\n")) {
      const item = /^- \[([x~ ])\]/.exec(line);
      if (item !== null) counts[item[1] as string] = (counts[item[1] as string] as number) + 1;
    }

    const [, done, inProgress, open] = total as RegExpExecArray;
    expect({
      done: Number(done),
      inProgress: Number(inProgress),
      open: Number(open),
    }).toEqual({ done: counts["x"], inProgress: counts["~"], open: counts[" "] });
  });
});
