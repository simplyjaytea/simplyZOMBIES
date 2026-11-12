#!/usr/bin/env bash
#
# A worktree and a branch for one piece, ready to run Godot (CLAUDE.md, The workflow).
#
#   bash scripts/new-piece.sh <piece> [--base=<ref>] [--from=<worktree>]
#
# Makes .claude/worktrees/<piece> on branch claude/<piece> from origin/main (or --base), links
# node_modules from the main checkout, and gives the worktree its Godot import state: copied from
# --from=<worktree> when one is named (about a second), otherwise imported (about a minute).
# The import's by-products are ignored by .gitignore, so the new worktree's `git status` is clean.

set -euo pipefail

piece=""
base="origin/main"
from=""
for arg in "$@"; do
  case "$arg" in
    --base=*) base="${arg#--base=}" ;;
    --from=*) from="${arg#--from=}" ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) piece="$arg" ;;
  esac
done
if [ -z "$piece" ]; then
  echo "usage: bash scripts/new-piece.sh <piece> [--base=<ref>] [--from=<worktree>]" >&2
  exit 2
fi

# The main checkout is where the shared .git directory lives, whichever worktree this runs from.
common="$(git rev-parse --path-format=absolute --git-common-dir)"
root="$(dirname "$common")"
tree="$root/.claude/worktrees/$piece"
if [ -e "$tree" ]; then
  echo "already there: $tree" >&2
  exit 1
fi

git -C "$root" worktree add -q -b "claude/$piece" "$tree" "$base"
ln -s "$root/node_modules" "$tree/node_modules"

if [ -n "$from" ]; then
  # Everything untracked under godot/ in the source worktree is import state: godot/.godot and the
  # sidecars beside the sources.
  (cd "$from" && git ls-files --others -z -- godot | tar --null -T - -cf -) | tar -C "$tree" -xf -
else
  godot_bin="${GODOT_BIN:-godot}"
  (cd "$tree" && "$godot_bin" --headless --path godot --import >/dev/null 2>&1) || {
    echo "the Godot import failed in $tree; run it by hand: godot --headless --path godot --import" >&2
    exit 1
  }
fi
echo "$tree"
