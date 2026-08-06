// Content loading errors.
//
// docs/20-ecs-and-content.md:153: "Content errors must fail loudly at load, never silently
// at hour thirty", and :143 requires failures to name "the file, the entry, and the field".
//
// Errors accumulate rather than throwing on the first one. Someone who has just added
// twenty affixes wants all twenty mistakes in one pass, not twenty edit-run cycles.

export type ContentIssue = {
  /** Path of the file the problem is in, relative to the content root. */
  readonly file: string;
  /** Content id of the offending entry, when the entry parsed far enough to have one. */
  readonly entry?: string;
  /** Dotted path to the field, e.g. `tiers[1].modifiers[0].stat`. */
  readonly field?: string;
  readonly message: string;
};

/** Formats one issue as `file > entry > field: message`, skipping what isn't known. */
export function formatIssue(issue: ContentIssue): string {
  const location = [issue.file, issue.entry, issue.field].filter((p) => p !== undefined);
  return `${location.join(" > ")}: ${issue.message}`;
}

export class ContentError extends Error {
  constructor(readonly issues: readonly ContentIssue[]) {
    const lines = issues.map((i) => `  ${formatIssue(i)}`).join("\n");
    super(`Content failed to load (${issues.length} problem(s)):\n${lines}`);
    this.name = "ContentError";
  }
}

/** Collects issues across a whole load, then throws once. */
export class IssueCollector {
  private readonly issues: ContentIssue[] = [];

  add(issue: ContentIssue): void {
    this.issues.push(issue);
  }

  get count(): number {
    return this.issues.length;
  }

  get all(): readonly ContentIssue[] {
    return this.issues;
  }

  /**
   * Throw if anything was collected. Issues are sorted by location so the report reads the
   * same way every run -- the same reason everything else in the kernel sorts.
   */
  throwIfAny(): void {
    if (this.issues.length === 0) return;
    const sorted = [...this.issues].sort((a, b) =>
      formatIssue(a) < formatIssue(b) ? -1 : formatIssue(a) > formatIssue(b) ? 1 : 0,
    );
    throw new ContentError(sorted);
  }
}
