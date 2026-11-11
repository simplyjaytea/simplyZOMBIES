# Decisions

One file per decision, from 2026-11-12 on. A decision is a call that shapes the game or the
code and that someone will later want the reason for: an owner's ruling, or an engineering call
taken from a measurement.

Earlier decisions are in [docs/30](../30-decisions.md), oldest first. That file is closed: it
gains no new entries, because every parallel branch appended to its tail and every merge
conflicted there. Search it by system name before changing anything that looks arbitrary.

## Writing one

Name the file `YYYY-MM-DD-short-slug.md`. Keep it short:

```markdown
# The title, as a statement of what was decided

- **Date:** 2026-11-12
- **Decided by:** the owner | engineering
- **Systems:** the systems it binds, by the names ROUTING.md uses

**Decision.** What holds from now on.

**Why.** The reason, with the measurement or the fault that forced it.

**Instead of.** What was considered and set aside, in a line each.
```

A decision that replaces an earlier one says so in its first line and links it. The earlier
file is not edited.
