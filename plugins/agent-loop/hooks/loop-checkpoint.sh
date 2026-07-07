#!/bin/sh
# loop-checkpoint.sh — agent-loop Stop hook. Backstop for a session dying
# mid-iteration: if state says run_in_progress, stamp interrupted_at and
# clear the flag so the next wake knows the last iteration didn't finish
# (al-state record-iter is the belt; this is the suspenders).
# Ownership-aware: Stop fires in EVERY session in the repo, so before
# touching anything it checks the run lease — a bystander session must
# never yank a LIVE run's flag/lease out from under the loop that owns it.
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

# stdin is the Stop event JSON; keep it for the session_id ownership check
INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

# find al-json: repo bin? plugin root? PATH?
ALJSON=""
for cand in "${CLAUDE_PLUGIN_ROOT:-}/bin/al-json" "$(command -v al-json 2>/dev/null)"; do
  [ -n "$cand" ] && [ -x "$cand" ] && ALJSON="$cand" && break
done
[ -n "$ALJSON" ] || exit 0

# Ownership: clean up only runs that are OURS or DEAD.
#   - lease session_id == this Stop event's session_id -> ours, clean
#   - owner pid alive on this host -> a live run owned elsewhere, leave it
#   - owner on another host with an unexpired lease -> can't probe, leave it
#   - otherwise (no lease, dead pid, expired remote) -> orphaned, clean
OWNER="$REPO/.claude/agent-loop/.lease/owner.json"
if [ -f "$OWNER" ]; then
  OSID=$("$ALJSON" get "$OWNER" session_id 2>/dev/null || echo "")
  SID=$("$ALJSON" get "$INPUT_FILE" session_id 2>/dev/null || echo "")
  if [ -z "$OSID" ] || [ "$OSID" = "null" ] || [ "$OSID" != "$SID" ]; then
    OPID=$("$ALJSON" get "$OWNER" pid 2>/dev/null || echo "")
    OHOST=$("$ALJSON" get "$OWNER" host 2>/dev/null || echo "")
    HOST=$(hostname 2>/dev/null || echo unknown)
    case "$OPID" in
      ''|*[!0-9]*) : ;;                          # no/garbage pid -> treat as dead
      *)
        if [ "$OHOST" = "$HOST" ]; then
          kill -0 "$OPID" 2>/dev/null && exit 0  # live run, not ours to clean
        else
          EXP=$("$ALJSON" get "$OWNER" expires_epoch 2>/dev/null || echo 0)
          case "$EXP" in ''|*[!0-9]*) EXP=0 ;; esac
          [ "$(date +%s)" -le "$EXP" ] && exit 0 # unexpired lease on another host
        fi
        ;;
    esac
  fi
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"$ALJSON" set "$STATE" interrupted_at "\"$NOW\"" >/dev/null 2>&1 || exit 0
"$ALJSON" set "$STATE" run_in_progress false >/dev/null 2>&1 || exit 0
# release the run lease the dying session held so the next wake isn't locked out
LEASE="$REPO/.claude/agent-loop/.lease"
rm -f "$LEASE/owner.json" 2>/dev/null
rmdir "$LEASE" 2>/dev/null
exit 0
