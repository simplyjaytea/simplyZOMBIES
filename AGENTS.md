# AGENTS.md

The fast on-ramp for any agent or person. The rules of the repository are in
[CLAUDE.md](CLAUDE.md): what the project is, the commands, how the code fits together, how a
change is verified, and the standing bans. [ROUTING.md](ROUTING.md) maps every system to its
code and its gate. This file carries no rules and no status, so it cannot drift.

## First commands

```bash
bash scripts/setup-web-session.sh   # install or verify the pinned engine and npm packages
npm run godot:smoke                 # the project boots
npm run check:routing               # the routing table and every gate reachable
npm run godot:m2 -- --shard=1/4     # one of CI's four shards of the full chain
npx vitest run test/unit/<file>     # one file of the frozen oracle
```

Before touching the sim: [docs/37, the traps](docs/37-traps.md), then the
[docs/30](docs/30-decisions.md) entries for the system you touch.
