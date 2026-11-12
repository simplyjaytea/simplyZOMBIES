#!/usr/bin/env bash
#
# A worktree and a branch for one piece, ready to run Godot (CLAUDE.md, The workflow).
#
#   bash scripts/new-piece.sh <piece> [--base=<ref>] [--from=<worktree>]
#
# Makes .claude/worktrees/<piece> on branch claude/<piece> from origin/main (fetched first) or from
# --base, links node_modules from the main checkout, and gives the worktree its Godot import
# state: copied from --from=<worktree> when one is named (about a second), otherwise imported
# (about a minute). Only what git ignores under godot/ is copied, which is the import state and
# never a source file. If any step fails, the half-made worktree and its branch are removed, so
# the command can simply be run again.

set -euo pipefail

piece=""
base="origin/main"
from=""
for arg in "$@"; do
  case "$arg" in
    --base=*) base="${arg#--base=}" ;;
    --from=*) from="${arg#--from=}" ;;
    -*)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
    *) piece="$arg" ;;
  esac
done
if [ -z "$piece" ]; then
  echo "usage: bash scripts/new-piece.sh <piece> [--base=<ref>] [--from=<worktree>]" >&2
  exit 2
fi
if [ -n "$from" ] && [ ! -d "$from/godot" ]; then
  echo "--from is not a worktree of this project: $from" >&2
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
if git -C "$root" show-ref --verify --quiet "refs/heads/claude/$piece"; then
  echo "the branch claude/$piece already exists" >&2
  exit 1
fi

if [ "$base" = "origin/main" ]; then
  git -C "$root" fetch --quiet origin main || echo "could not fetch origin; using the local origin/main" >&2
fi

made=""
undo() {
  if [ -n "$made" ]; then
    git -C "$root" worktree remove --force "$tree" >/dev/null 2>&1 || true
    git -C "$root" branch -D "claude/$piece" >/dev/null 2>&1 || true
    echo "removed the half-made worktree and branch for $piece" >&2
  fi
}
trap undo ERR

git -C "$root" worktree add -q -b "claude/$piece" "$tree" "$base"
made="yes"
ln -s "$root/node_modules" "$tree/node_modules"

if [ -n "$from" ]; then
  (cd "$from" && git ls-files --others --ignored --exclude-standard -z -- godot | tar --null -T - -cf -) |
    tar -C "$tree" -xf -
fi
if [ ! -d "$tree/godot/.godot" ]; then
  "${GODOT_BIN:-godot}" --headless --path "$tree/godot" --import >/dev/null 2>&1
  [ -d "$tree/godot/.godot" ]
fi

trap - ERR
echo "$tree"
