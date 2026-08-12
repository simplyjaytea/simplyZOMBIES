// Re-file HANDOFF.md's backlog groups from the checkboxes themselves.
//
// Every section groups its tasks under `**Done (n):**` / `**In progress (n):**` / `**Open (n):**`,
// which makes those headers a second copy of a fact -- and `test/unit/handoff.test.ts` asserts the
// two agree, because the first version of them disagreed within a session of being written.
//
// This is the fixer for when that test goes red: tick a box, run `npm run handoff:regroup`, and the
// item moves to the right group and every count follows. Idempotent, so running it on a correct file
// changes nothing -- which is what makes it safe to run without reading the diff first.
//
// It deliberately does *not* reorder tasks within a group, or touch anything outside a group. A
// group owns every top-level checkbox until the next group header or the next heading, whichever
// comes first -- and that heading boundary is load-bearing, because "Beyond the slice" lists tasks
// with no group header at all.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HANDOFF = resolve(dirname(fileURLToPath(import.meta.url)), "../HANDOFF.md");

const HEADING = /^#{1,6}\s/;
const GROUP = /^\*\*(Done|In progress|Open) \((\d+)\):\*\*$/;
const ITEM = /^- \[([x~ ])\]/;
const LABEL = { x: "Done", "~": "In progress", " ": "Open" };
const ORDER = ["Done", "In progress", "Open"];

const lines = readFileSync(HANDOFF, "utf8").split(/\r?\n/);
const out = [];
let i = 0;

while (i < lines.length) {
  if (!GROUP.test(lines[i])) {
    out.push(lines[i]);
    i += 1;
    continue;
  }

  const started = i;
  const buckets = { Done: [], "In progress": [], Open: [] };

  // Consume every consecutive group under this heading into one set of buckets.
  while (i < lines.length && GROUP.test(lines[i])) {
    i += 1;
    while (i < lines.length && lines[i].trim() === "") i += 1;

    while (i < lines.length && !GROUP.test(lines[i]) && !HEADING.test(lines[i])) {
      const item = ITEM.exec(lines[i]);
      if (item === null) {
        i += 1;
        continue;
      }
      // An item is its first line plus every indented continuation, blank lines included, so a
      // multi-paragraph note travels with the task it belongs to.
      const chunk = [lines[i]];
      i += 1;
      while (i < lines.length && (lines[i].startsWith("      ") || lines[i].trim() === "")) {
        chunk.push(lines[i]);
        i += 1;
      }
      while (chunk.length > 0 && chunk[chunk.length - 1].trim() === "") chunk.pop();
      buckets[LABEL[item[1]]].push(chunk.join("\n"));
    }
    while (i < lines.length && lines[i].trim() === "") i += 1;
  }

  for (const label of ORDER) {
    if (buckets[label].length === 0) continue;
    out.push(`**${label} (${buckets[label].length}):**`, "");
    out.push(...buckets[label]);
    out.push("");
  }

  // Guard against a malformed group header spinning forever.
  if (started === i) i += 1;
}

const next = out.join("\n");
const changed = next !== readFileSync(HANDOFF, "utf8");
writeFileSync(HANDOFF, next);
console.log(changed ? "HANDOFF.md regrouped." : "HANDOFF.md already correct; nothing changed.");
