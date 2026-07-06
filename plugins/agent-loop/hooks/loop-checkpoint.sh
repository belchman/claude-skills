#!/bin/sh
# loop-checkpoint.sh — agent-loop Stop hook. Backstop for a session dying
# mid-iteration: if state says run_in_progress, stamp interrupted_at and
# clear the flag so the next wake knows the last iteration didn't finish
# (al-state record-iter is the belt; this is the suspenders).
# Self-gates like guard-destructive.sh; must cost <10ms when gating out
# because Stop fires in EVERY session.
set -u

REPO="${CLAUDE_PROJECT_DIR:-.}"
STATE="$REPO/.claude/agent-loop/state.json"
[ -f "$STATE" ] || exit 0
REPO_COPY="$REPO/.claude/hooks/loop-checkpoint.sh"
case "$0" in
  "$REPO_COPY") : ;;
  *) [ -f "$REPO_COPY" ] && exit 0 ;;
esac

grep -q '"run_in_progress" *: *true' "$STATE" || exit 0

# find al-json: repo bin? plugin root? PATH?
ALJSON=""
for cand in "${CLAUDE_PLUGIN_ROOT:-}/bin/al-json" "$(command -v al-json 2>/dev/null)"; do
  [ -n "$cand" ] && [ -x "$cand" ] && ALJSON="$cand" && break
done
[ -n "$ALJSON" ] || exit 0

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"$ALJSON" set "$STATE" interrupted_at "\"$NOW\"" >/dev/null 2>&1 || exit 0
"$ALJSON" set "$STATE" run_in_progress false >/dev/null 2>&1 || exit 0
# release the run lease the dying session held so the next wake isn't locked out
LEASE="$REPO/.claude/agent-loop/.lease"
rm -f "$LEASE/owner.json" 2>/dev/null
rmdir "$LEASE" 2>/dev/null
exit 0
