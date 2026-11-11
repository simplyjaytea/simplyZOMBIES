# The session's unread map handle is deleted

- **Date:** 2026-11-12
- **Decided by:** engineering
- **Systems:** the title and session shell (`godot/presentation/session.gd`)

**Decision.** `Session.map`, the map object `SimBoot` hands back beside the world, is removed. Nothing
reads it; the game reaches the same map through `world.tilemap`.

**Why.** It was `main.gd`'s `_map`, written on every boot and read by no line of the game, and was
carried into `session.gd` as a named socket in the alpha shell. A grep of `godot/` finds no reader.
Dead-socket rule (CLAUDE.md): a mechanism nothing reaches is deleted or gets an assertion that
something reads it, and there is nothing here to read.

**Instead of.** Giving it a reader: the map is already one field away on the world.
