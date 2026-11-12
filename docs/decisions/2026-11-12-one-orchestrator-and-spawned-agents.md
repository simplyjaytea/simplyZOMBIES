# One orchestrator and spawned agents replace the three seats

Replaces [Three seats, and GitHub is the record](2026-11-11-three-seats-and-github-as-the-record.md)
in who does the work. GitHub stays the record.

- **Date:** 2026-11-12
- **Decided by:** the owner (the direction); engineering (the shape)
- **Systems:** the workflow (CLAUDE.md, `.claude/agents/`, `scripts/new-piece.sh`)

**Decision.** The owner: "revamp the playbook ... spin up sub-agents, do whatever you want." The
standing architect and builder terminals are gone. One orchestrator session runs a job in four
passes: scouts map what it touches, the orchestrator cuts it into pieces with their files, gate
and done, one builder per piece builds in parallel in its own worktree, and nobody checks their
own work: a critic judges a visible change from pictures it makes itself, a reviewer reads the
diff and reruns the gates and plants. The agents are spawned for the job and gone after it. A
piece too long for a session may still run in its own terminal, under the same limits.

Pieces that are judged together land together: the orchestrator merges the piece branches into
one integration branch, verifies it as a whole, leaves out a piece that fails, and opens one pull
request. A piece cut and landed inside one session needs no issue of its own; its brief is its
spec and its pull request says what the issue would have said.

**Why.** The first job under this decision was the first-person look: six pieces that make one
picture and had to be built in one evening. Two standing terminals could not fan out that wide,
and each seat was a hand-off of its own: a brief to write, a terminal to relaunch, a pause to
run. The backlog showed the same imbalance: at the last pause the pinned issue counted 27 open
pieces labelled for the architect and 4 for the builder. What the seats got right is kept: reports are reproduced, review is independent, only the
orchestrator merges, and no file carries status.

One measured fact shaped the rules: the session and its agents share one usage pool, and when
it ran out mid-run, four of six agents were cut off with nothing to show. So builders commit as
they go, a brief tells a relaunched builder to continue from its branch, and the passes are
separate so a finished one is never repeated.

**Instead of.**

- Keeping the seats and spawning agents under them: two layers of hand-off for the same work.
- One pull request per piece for a pass: six pieces are six CI runs, each merge sends the
  others round again, and the pictures can only be judged together. The earlier objection to a
  rollup, that one red member blocks all, is met by verifying the integration branch before it
  is pushed and leaving the red member out.
- An issue for every piece of a pass: the brief and the pull request carry the same four
  things, and the pinned issue names what is open.

The `architect`, `builder` and `orchestrator` labels on open issues assign nothing any more.
They come off as the backlog is next cut; an issue's milestone still says which goal it serves.
