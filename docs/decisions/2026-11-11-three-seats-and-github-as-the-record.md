# Three seats, and GitHub is the record

- **Date:** 2026-11-11
- **Decided by:** the owner
- **Systems:** the workflow (CLAUDE.md, `.claude/agents/`, `.claude/hooks/guard-git.sh`)

**Decision.** The root `PLAYBOOK.md` and the shared folder outside the repository are gone.
`CLAUDE.md` holds the rules and `ROUTING.md` the routing table. Three standing seats do the
work: an orchestrator that plans, writes issues, reads the final diff and merges; an architect
for shared sim modules, the save format, new gates, art builders and hard design; a builder for
everything else, which hands well-specified pieces to worker subagents and reruns their gates
itself. One issue per piece is its spec and the pull request is its report. At most three pull
requests are open for merge. Decisions are one file each in this folder.

**Why.** The nine-terminal roster's recorded failures were all coordination costs: workers
reported work done when it was not three times in one session, two agents started the same
merge in one worktree twice, and the 800-line playbook lagged the roster it described. Status
kept in files (`docs/23`'s what's left, the session log, handoff notes) drifted and conflicted
on every parallel branch.

**Instead of.**

- Keeping the nine terminals with a shorter playbook: the cost was the hand-offs, not the text.
- One session with subagents only: no standing strong tier for a piece that needs a day.
- A rollup pull request when several pieces wait: one red member blocks all of them (#396).
