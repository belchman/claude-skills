#!/bin/sh
# between.sh — the deterministic "human" between the two legs: approve the
# pending plan. No model involved.
set -u
WT="${1:?worktree path required}"
PLUGIN=$(cd "$(dirname "$0")/../../../../plugins/agent-loop" && pwd)
export CLAUDE_PROJECT_DIR="$WT"
STATUS=$("$PLUGIN/bin/al-state" get plan.status 2>/dev/null || echo none)
if [ "$STATUS" != "awaiting-human" ]; then
  echo "between.sh: expected a plan awaiting approval, got plan.status=$STATUS" >&2
  exit 1
fi
"$PLUGIN/bin/al-state" plan-approve
