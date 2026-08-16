#!/usr/bin/env bash
#
# SessionStart hook: give a fresh Claude Code on the web session a working engine.
#
# The container starts from a bare clone. Without this, no `godot:*` gate can run, and a
# session is left verifying the product with whatever else happens to execute -- which is
# how work drifts away from the thing that actually ships.
#
# The install itself lives in scripts/setup-web-session.sh so it can also be run by hand.

set -euo pipefail

# Local machines and the Cursor Cloud snapshot already have their toolchain (AGENTS.md);
# only the remote container starts empty.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

readonly ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

bash "$ROOT/scripts/setup-web-session.sh"

# The symlink in the installer is what makes `godot` resolve for run-godot.mjs, but export
# GODOT_BIN too: it is the first candidate that script probes, and it keeps working if
# /usr/local/bin was not writable.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -x "$ROOT/.ci-tools/godot/Godot_v4.7.1-stable_linux.x86_64" ]; then
  echo "export GODOT_BIN=\"$ROOT/.ci-tools/godot/Godot_v4.7.1-stable_linux.x86_64\"" >> "$CLAUDE_ENV_FILE"
fi
