#!/bin/sh
# al-loop.sh — the external trigger (loop step 4). Deliberately dumb: all
# intelligence lives behind /agent-loop run; this script only wakes it.
# Wire it to cron / launchd / systemd / CI (recipes in the plugin README).
#
#   al-loop.sh [<repo-dir>]     # default: cwd
#
# Gates BEFORE spending any tokens:
#   - goal.json exists and status == "active"
#   - state.json paused_by_stall != true   (a stalled loop costs $0/tick)
#   - state.json iteration < goal.json max_iterations (ceiling-stop, exit 0)
# Then runs one headless iteration and backfills
# state.json.context_tokens_last_iter from the result JSON usage block
# (field names pinned by tests/test_agent_loop_bin.sh).
#
# NOTE on permissions: headless runs cannot approve prompts. Either allowlist
# what the loop needs in .claude/settings.json (init's merge covers the al-*
# tools; add your build/test commands), or run with a broader
# --permission-mode via AL_LOOP_PERMISSION_MODE (default: acceptEdits).
set -eu

BIN_DIR=$(cd "$(dirname "$0")" && pwd)
ALJSON="$BIN_DIR/al-json"

REPO="${1:-$(pwd)}"
REPO=$(cd "$REPO" && pwd -P)
AL_DIR="$REPO/.claude/agent-loop"
GOAL_JSON="$AL_DIR/goal.json"
STATE="$AL_DIR/state.json"

[ -f "$GOAL_JSON" ] || exit 0                       # nothing to do

# fleet registry (PULL model): a repo with a goal announces its root once —
# BEFORE the status gates, so paused/awaiting repos still appear on the fleet.
# Append-only grep-dedup'd, best-effort: registration never fails the tick.
if [ -z "${AL_NO_FLEET_REGISTER:-}" ]; then
  _REG="${AL_FLEET_REGISTRY:-${HOME:-}/.claude/agent-loop/fleet.list}"
  mkdir -p "$(dirname "$_REG")" 2>/dev/null || true
  grep -qxF -- "$REPO" "$_REG" 2>/dev/null || printf '%s\n' "$REPO" >> "$_REG" 2>/dev/null || true
fi

mkdir -p "$AL_DIR/logs"
LOG="$AL_DIR/logs/loop.log"
ERRF="$AL_DIR/logs/consecutive_errors"
NOTIFYF="$AL_DIR/logs/last_notify"
GOAL_ID=$("$ALJSON" get "$GOAL_JSON" id 2>/dev/null || echo unknown)

json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }

# Fanout for "the loop is blocked on a human" moments. Channels:
#   AL_LOOP_WEBHOOK     — curl POST of the JSON payload
#   AL_LOOP_NOTIFY_CMD  — shell command receiving the JSON on stdin
# Deduped per event (last_notify) so a paused loop doesn't page every tick;
# a successful iteration clears the dedupe so future pauses re-notify.
notify_once() { # $1=event $2=detail
  [ "$(cat "$NOTIFYF" 2>/dev/null || true)" = "$1" ] && return 0
  printf '%s' "$1" > "$NOTIFYF"
  _pl=$(printf '{"repo":"%s","goal_id":"%s","event":"%s","detail":"%s","at":"%s"}' \
    "$(json_esc "$REPO")" "$(json_esc "$GOAL_ID")" "$1" "$(json_esc "$2")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
  if [ -n "${AL_LOOP_WEBHOOK:-}" ] && command -v curl >/dev/null 2>&1; then
    curl -fsS -m 10 -X POST -H 'Content-Type: application/json' -d "$_pl" "$AL_LOOP_WEBHOOK" >/dev/null 2>&1 || true
  fi
  if [ -n "${AL_LOOP_NOTIFY_CMD:-}" ]; then
    printf '%s' "$_pl" | sh -c "$AL_LOOP_NOTIFY_CMD" >/dev/null 2>&1 || true
  fi
  return 0
}

bump_errors() { # $1=detail — consecutive-failure counter; trips the breaker
  _e=$(cat "$ERRF" 2>/dev/null || echo 0)
  case "$_e" in ''|*[!0-9]*) _e=0 ;; esac
  _e=$((_e + 1))
  printf '%s' "$_e" > "$ERRF"
  if [ "$_e" -ge "${AL_LOOP_MAX_ERRORS:-3}" ]; then
    echo "al-loop: circuit breaker TRIPPED after $_e consecutive errored ticks — rm $ERRF to re-arm" >> "$LOG"
    notify_once circuit_breaker "tripped after $_e consecutive errored ticks: $1"
  fi
  return 0
}

# Circuit breaker: after AL_LOOP_MAX_ERRORS (default 3) consecutive errored
# ticks, stop burning ticks until a human re-arms (rm the counter file).
# Distinct from the stall detector — this catches API/install failures, not
# no-progress iterations.
ERRS=$(cat "$ERRF" 2>/dev/null || echo 0)
case "$ERRS" in ''|*[!0-9]*) ERRS=0 ;; esac
if [ "$ERRS" -ge "${AL_LOOP_MAX_ERRORS:-3}" ]; then
  echo "al-loop: circuit breaker open ($ERRS consecutive errors) — skipping tick; rm $ERRF to re-arm" >&2
  exit 0
fi

STATUS=$("$ALJSON" get "$GOAL_JSON" status 2>/dev/null || echo none)
[ "$STATUS" = "active" ] || exit 0                  # paused/done/abandoned
if [ -f "$STATE" ]; then
  PAUSED=$("$ALJSON" get "$STATE" paused_by_stall 2>/dev/null || echo false)
  if [ "$PAUSED" = "true" ]; then
    echo "al-loop: loop is stall-paused; a human must intervene (see /agent-loop status). Skipping." >&2
    notify_once stall_paused "loop auto-paused by the stall detector; see /agent-loop status"
    exit 0
  fi
  # Guard 4: a plan awaiting human approval costs $0 per tick
  PSTATUS=$("$ALJSON" get "$STATE" plan.status 2>/dev/null || echo none)
  if [ "$PSTATUS" = "awaiting-human" ]; then
    echo "al-loop: a proposed plan is AWAITING HUMAN APPROVAL — no tokens spent."
    NA=$("$ALJSON" len "$STATE" plan.assumptions 2>/dev/null || echo 0)
    if [ "$NA" -gt 0 ]; then
      echo "al-loop: assumptions needing decisions:"
      ai=0
      while [ "$ai" -lt "$NA" ]; do
        echo "  - $("$ALJSON" get "$STATE" "plan.assumptions.$ai")"
        ai=$((ai + 1))
      done
    fi
    echo "al-loop: approve with '/agent-loop approve' (or al-state plan-approve); reject with '/agent-loop reject <reason>'."
    notify_once plan_awaiting "a proposed plan awaits human approval ($NA assumption(s))"
    exit 0
  fi
fi

# iteration ceiling: never spend tokens past max_iterations (a ceiling-stop
# is not an error — exit 0 and ask for human review)
if [ -f "$STATE" ]; then
  ITER=$("$ALJSON" get "$STATE" iteration 2>/dev/null || echo 0)
  MAXI=$("$ALJSON" get "$GOAL_JSON" max_iterations 2>/dev/null || echo 0)
  case "$ITER" in ''|*[!0-9]*) ITER=0;; esac
  case "$MAXI" in ''|*[!0-9]*) MAXI=0;; esac
  if [ "$MAXI" -gt 0 ] && [ "$ITER" -ge "$MAXI" ]; then
    MSG="al-loop: iteration ceiling reached ($ITER/$MAXI) — human review needed"
    echo "$MSG" >> "$LOG"
    echo "$MSG"
    notify_once iteration_ceiling "$ITER of $MAXI iterations used"
    exit 0
  fi
fi

# token budget ceiling: cumulative spend (state.tokens_total) may never pass
# the goal's budget_tokens — or the org policy's, whichever is smaller
if [ -f "$STATE" ]; then
  TT=$("$ALJSON" get "$STATE" tokens_total 2>/dev/null || echo 0)
  BG=$("$ALJSON" get "$GOAL_JSON" budget_tokens 2>/dev/null || echo 0)
  BP=$("$ALJSON" get "$AL_DIR/policy.json" budget_tokens 2>/dev/null || echo 0)
  case "$TT" in ''|*[!0-9]*) TT=0;; esac
  case "$BG" in ''|*[!0-9]*) BG=0;; esac
  case "$BP" in ''|*[!0-9]*) BP=0;; esac
  BUDGET="$BG"
  if [ "$BP" -gt 0 ] && { [ "$BUDGET" -eq 0 ] || [ "$BP" -lt "$BUDGET" ]; }; then BUDGET="$BP"; fi
  if [ "$BUDGET" -gt 0 ] && [ "$TT" -ge "$BUDGET" ]; then
    MSG="al-loop: token budget reached ($TT/$BUDGET) — human review needed"
    echo "$MSG" >> "$LOG"
    echo "$MSG"
    notify_once budget_ceiling "$TT of $BUDGET budgeted tokens spent"
    exit 0
  fi
fi
# Run lease: the tick itself holds the repo's run lease for its whole
# lifetime, so overlapping cron/launchd ticks are mutually exclusive at the
# harness level — not just by model behavior inside the skill. AL_LEASE_PID
# marks the recorded owner pid as durable (this process, alive for the whole
# tick) and is inherited by the claude run below, so the skill's own
# lease-acquire becomes a re-entrant refresh instead of a self-collision.
# A crashed previous tick leaves a dead durable owner, which lease-acquire
# takes over immediately (no TTL wait).
AL_LEASE_PID=$$
export AL_LEASE_PID
HAVE_LEASE=0
release_lease() {
  [ "${HAVE_LEASE:-0}" = "1" ] || return 0
  "$BIN_DIR/al-state" --state "$STATE" lease-release >/dev/null 2>&1 || true
  HAVE_LEASE=0
}
if [ -f "$STATE" ]; then
  if "$BIN_DIR/al-state" --state "$STATE" lease-acquire "${AL_LOOP_LEASE_TTL:-3600}" >/dev/null 2>&1; then
    HAVE_LEASE=1
  else
    echo "al-loop: another session holds the run lease — skipping tick" >&2
    exit 0
  fi
fi

OUT=$(mktemp)
trap 'rm -f "$OUT"; release_lease' EXIT

# the plugin providing /agent-loop is this script's own parent dir — pass it
# explicitly so the tick works whether or not the plugin is installed
# globally. Override: AL_LOOP_PLUGIN_DIR=<path>, or "none" to rely on a
# global install only.
PLUGIN_ROOT=$(cd "$BIN_DIR/.." && pwd)
PLUGIN_FLAG="--plugin-dir ${AL_LOOP_PLUGIN_DIR:-$PLUGIN_ROOT}"
[ "${AL_LOOP_PLUGIN_DIR:-}" = "none" ] && PLUGIN_FLAG=""

echo "=== al-loop tick $(date -u +%Y-%m-%dT%H:%M:%SZ) repo=$REPO ===" >> "$LOG"
# shellcheck disable=SC2086  # PLUGIN_FLAG is intentionally word-split
( cd "$REPO" && claude \
    -p "/agent-loop run" \
    $PLUGIN_FLAG \
    --permission-mode "${AL_LOOP_PERMISSION_MODE:-acceptEdits}" \
    --max-turns "${AL_LOOP_MAX_TURNS:-80}" \
    --output-format json ) > "$OUT" 2>>"$LOG" || true
cat "$OUT" >> "$LOG"

if ! "$ALJSON" check "$OUT" 2>/dev/null; then
  echo "al-loop: run produced no parseable result JSON (see $LOG)" >&2
  bump_errors "no parseable result JSON"
  exit 1
fi

# honest failure reporting: never claim an iteration happened when it didn't
IS_ERR=$("$ALJSON" get "$OUT" is_error 2>/dev/null || echo false)
RESULT=$("$ALJSON" get "$OUT" result 2>/dev/null || true)
case "$RESULT" in
  "Unknown command"*|"Unknown skill"*)
    echo "al-loop: /agent-loop did not resolve — is the plugin installed? ($RESULT)" >&2
    bump_errors "/agent-loop did not resolve"
    exit 1 ;;
esac
if [ "$IS_ERR" = "true" ]; then
  echo "al-loop: run errored: $(printf '%s' "$RESULT" | head -c 200) (see $LOG)" >&2
  bump_errors "run errored: $(printf '%s' "$RESULT" | head -c 120)"
  exit 1
fi

# healthy tick: re-arm the breaker and the notification dedupe
rm -f "$ERRF" "$NOTIFYF"

# backfill context spend from the pinned usage fields (approximate context =
# fresh input + cache creation + cache reads at the last request)
if [ -f "$STATE" ]; then
  IN=$("$ALJSON" get "$OUT" usage.input_tokens 2>/dev/null || echo 0)
  CC=$("$ALJSON" get "$OUT" usage.cache_creation_input_tokens 2>/dev/null || echo 0)
  CR=$("$ALJSON" get "$OUT" usage.cache_read_input_tokens 2>/dev/null || echo 0)
  # sanitize: null/absent/garbage usage fields must not crash the arithmetic
  case "$IN" in ''|*[!0-9]*) IN=0;; esac
  case "$CC" in ''|*[!0-9]*) CC=0;; esac
  case "$CR" in ''|*[!0-9]*) CR=0;; esac
  TOTAL=$((IN + CC + CR))
  [ "$TOTAL" -gt 0 ] && "$ALJSON" set "$STATE" context_tokens_last_iter "$TOTAL" >/dev/null 2>&1 || true
  # cost ledger: cumulative spend for the budget ceiling above
  TT=$("$ALJSON" get "$STATE" tokens_total 2>/dev/null || echo 0)
  case "$TT" in ''|*[!0-9]*) TT=0;; esac
  [ "$TOTAL" -gt 0 ] && "$ALJSON" set "$STATE" tokens_total "$((TT + TOTAL))" >/dev/null 2>&1 || true
fi
# post-run backstop: if the inner session died mid-iteration its Stop hook
# may never have fired — clear the run flag here so the next tick isn't
# stuck behind a phantom run (the lease releases via the EXIT trap)
if [ -f "$STATE" ] && [ "$("$ALJSON" get "$STATE" run_in_progress 2>/dev/null || echo false)" = "true" ]; then
  "$ALJSON" set "$STATE" interrupted_at "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >/dev/null 2>&1 || true
  "$ALJSON" set "$STATE" run_in_progress false >/dev/null 2>&1 || true
fi
echo "al-loop: iteration done (context≈${TOTAL:-?} tokens): $(printf '%s' "$RESULT" | head -c 200)"
