#!/usr/bin/env bash
#
# PreToolUse hook on Bash: the three git rules of CLAUDE.md's workflow, made mechanical.
#
#   1. Nobody force-pushes.
#   2. Nobody pushes to main.
#   3. Only the orchestrator merges a pull request. A seat is a session started with SZ_SEAT set
#      (architect, builder); its subagents inherit it. A session with no SZ_SEAT is the owner's
#      own or the orchestrator's, and may merge.
#
# Exit 2 blocks the call and hands stderr to the model. Any other outcome lets the call through,
# so a broken hook never stops work; it only stops guarding.

set -uo pipefail

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

block() {
  echo "Blocked by .claude/hooks/guard-git.sh: $1 (CLAUDE.md, The workflow)." >&2
  exit 2
}

if grep -Eq 'git[[:space:]]+([^;&|]*[[:space:]])?push\b' <<<"$cmd"; then
  if grep -Eq 'push\b[^;&|]*[[:space:]](--force(-with-lease|-if-includes)?(=[^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)' <<<"$cmd"; then
    block "never force-push"
  fi
  if grep -Eq 'push\b[^;&|]*[[:space:]]\+[^[:space:]]+' <<<"$cmd"; then
    block "never force-push (a +refspec is a force-push)"
  fi
  if grep -Eq 'push\b[^;&|]*[[:space:]]([^[:space:]]*:)?(refs/heads/)?main([[:space:]]|$)' <<<"$cmd"; then
    block "never push to main; open a pull request"
  fi
fi

seat="${SZ_SEAT:-}"
if [ -n "$seat" ] && [ "$seat" != "orchestrator" ]; then
  if grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge\b' <<<"$cmd"; then
    block "the $seat seat does not merge; say on the issue that the head is ready"
  fi
fi

exit 0
