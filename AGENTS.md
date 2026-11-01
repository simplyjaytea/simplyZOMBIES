# AGENTS.md

Any agent, whatever its assistant: read [PLAYBOOK.md](PLAYBOOK.md) first, top to bottom. It holds the
rules of this repository, the team and the Orca workflow, and how the project runs. Its
[routing table](PLAYBOOK.md#routing-table) maps every system to its code, its gate and where its
record is written, and [docs/23](docs/23-roadmap.md) is the live list of what is open. Before you
touch the sim, read [docs/37, the traps](docs/37-traps.md) and search [docs/30, the decisions](docs/30-decisions.md)
by system name.

## First commands

```bash
bash scripts/setup-web-session.sh   # install or verify the pinned engine and npm packages
npm run godot:smoke                 # the project boots
npm run check:routing               # the routing table and every gate reachable
npm run godot:m2 -- --shard=1/4     # one of CI's four shards of the full chain
npx vitest run test/unit/<file>     # one file of the frozen oracle
```
