#!/bin/sh
# test_agent_loop_watch.sh — model-free tests for bin/al-watch, the
# python3-stdlib local dashboard (`al-watch <repo> --port 0 [--allow-actions]`).
# Servers run in the background against a mktemp fixture repo; readiness is a
# poll on the startup line ("http://127.0.0.1:<port>"), never a bare sleep.
#
# Skip (exit 0) ONLY when python3 is absent. NEVER skip when al-watch is
# missing — before the implementation exists this suite must be RED (that
# failing run is the TDD gate's evidence).
#
# Run: sh tests/test_agent_loop_watch.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$REPO_ROOT/plugins/agent-loop/bin"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { # $1=description, $2=exit code, $3=expected code
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (exit $2, wanted $3)"; fi
}

command -v python3 >/dev/null 2>&1 || { echo "watch tests: skipped (python3 absent)"; exit 0; }

SANDBOX=$(mktemp -d); SANDBOX=$(cd "$SANDBOX" && pwd -P)
export AL_FLEET_REGISTRY="$SANDBOX/fleet.list"   # keep make test away from the real registry
SERVER_PIDS=""
cleanup() {
  for _p in $SERVER_PIDS; do kill "$_p" 2>/dev/null; done
  for _p in $SERVER_PIDS; do wait "$_p" 2>/dev/null; done
  rm -rf "$SANDBOX"
}
trap cleanup EXIT
unset AL_STATE_FILE AL_GOAL_FILE CLAUDE_PROJECT_DIR 2>/dev/null || true

# --- fixture repo -------------------------------------------------------------
AL="$SANDBOX/.claude/agent-loop"
mkdir -p "$AL/logs"
echo 0 > "$AL/logs/consecutive_errors"
cat > "$AL/GOAL.md" <<'EOF'
# Goal: watch fixture

## Done means
- [ ] works: the dashboard serves loop state
EOF
cat > "$AL/goal.json" <<'EOF'
{"id":"t-watch","status":"active","plan_approval":"always","verify":[{"cmd":"true","expect":"exit0"}],"verifier_rubric":["r"]}
EOF
"$BIN/al-state" --state "$AL/state.json" init t-watch >/dev/null
check "fixture: al-state init" $? 0
"$BIN/al-state" --state "$AL/state.json" plan-propose '{"tasks":[{"task":"t"}],"assumptions":[]}' >/dev/null
check "fixture: plan-propose" $? 0
[ "$("$BIN/al-state" --state "$AL/state.json" get plan.status)" = "awaiting-human" ] \
  && ok "fixture: plan awaiting-human" || bad "fixture: plan awaiting-human"

# archived past loop: the console must let a human browse closed goals
mkdir -p "$AL/archive/old-run"
printf '# Goal: old run\n\n# Done means\n- [x] shipped: it shipped\n' > "$AL/archive/old-run/GOAL.md"
printf '{"goal_id":"old-run","iteration":2,"done_means":{"shipped":true},"tokens_total":42}\n' > "$AL/archive/old-run/state.json"
printf '{"event":"goal_init","at":"t0"}\n{"event":"iteration","at":"t1","payload":{"iter":2}}\n' > "$AL/archive/old-run/audit.jsonl"

# --- server helpers -----------------------------------------------------------
start_watch() { # $1=stdout log; remaining args passed to al-watch. Polls the
  # log for the startup URL (~10s budget) — fails fast when the binary is
  # absent or dies before becoming ready.
  _log="$1"; shift
  "$BIN/al-watch" "$SANDBOX" --port 0 "$@" > "$_log" 2>&1 &
  _pid=$!
  SERVER_PIDS="$SERVER_PIDS $_pid"
  _i=0
  while [ "$_i" -lt 50 ]; do
    grep -q 'http://127\.0\.0\.1:[0-9]' "$_log" 2>/dev/null && return 0
    kill -0 "$_pid" 2>/dev/null || return 1
    sleep 0.2
    _i=$((_i + 1))
  done
  return 1
}
port_from() { sed -n 's|.*http://127\.0\.0\.1:\([0-9][0-9]*\).*|\1|p' "$1" | head -1; }

echo "# al-watch read-only server"
RO_LOG="$SANDBOX/ro.log"
if start_watch "$RO_LOG"; then
  ok "server starts and prints http://127.0.0.1:<port>"
  PORT=$(port_from "$RO_LOG")
else
  bad "server starts and prints http://127.0.0.1:<port> (al-watch missing or never ready)"
  PORT=""
fi

if [ -n "$PORT" ]; then
  BASE="http://127.0.0.1:$PORT"
  STATE_OUT=$(curl -s -m 5 "$BASE/api/state")
  echo "$STATE_OUT" | grep -q 't-watch'      && ok "GET /api/state carries the goal id" || bad "GET /api/state goal id"
  echo "$STATE_OUT" | grep -q '"iteration"'  && ok "GET /api/state carries iteration"   || bad "GET /api/state iteration"

  HTML_OUT=$(curl -s -m 5 "$BASE/")
  echo "$HTML_OUT" | grep -qi 'agent-loop' && ok "GET / serves the dashboard HTML" || bad "GET / dashboard HTML"
  echo "$HTML_OUT" | grep -q 'id="view-archive"' && ok "GET / carries the ARCHIVE view (past loops)" || bad "GET / archive view"

  ARCH_OUT=$(curl -s -m 5 "$BASE/api/archive")
  echo "$ARCH_OUT" | grep -q '"old-run"' && ok "GET /api/archive lists past loops (single-repo)" || bad "GET /api/archive list"
  ARCHD_OUT=$(curl -s -m 5 "$BASE/api/archive?goal=old-run")
  # journal lines ride as JSON-encoded strings, so inner quotes are escaped
  echo "$ARCHD_OUT" | grep -q '"journal"' && echo "$ARCHD_OUT" | grep -q 'goal_init' \
    && ok "GET /api/archive?goal= returns the past loop journal" || bad "GET /api/archive detail"

  # SSE stream: -m 3 cuts a healthy infinite stream, so curl exiting 28 is
  # EXPECTED — capture the output, never check curl's exit code here.
  SSE_OUT=$(curl -sN -m 3 "$BASE/events" 2>/dev/null || true)
  echo "$SSE_OUT" | grep -q 'event: journal'        && ok "/events emits journal events"        || bad "/events journal event"
  echo "$SSE_OUT" | grep -q '"event":"goal_init"'   && ok "/events replays journal history (goal_init)" || bad "/events history replay (goal_init)"
  echo "$SSE_OUT" | grep -q 'event: state'          && ok "/events emits state events"          || bad "/events state event"

  RO_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' "$BASE/api/approve")
  [ "$RO_CODE" = "403" ] && ok "read-only server: POST /api/approve -> 403" \
                         || bad "read-only server: POST /api/approve -> 403 (got $RO_CODE)"
else
  bad "GET /api/state carries the goal id (no server)"
  bad "GET /api/state carries iteration (no server)"
  bad "GET / serves the dashboard HTML (no server)"
  bad "GET / carries the ARCHIVE view (past loops) (no server)"
  bad "GET /api/archive lists past loops (single-repo) (no server)"
  bad "GET /api/archive?goal= returns the past loop journal (no server)"
  bad "/events emits journal events (no server)"
  bad "/events replays journal history (goal_init) (no server)"
  bad "/events emits state events (no server)"
  bad "read-only server: POST /api/approve -> 403 (no server)"
fi

echo "# al-watch actions server (--allow-actions)"
ACT_LOG="$SANDBOX/act.log"
if start_watch "$ACT_LOG" --allow-actions; then
  ok "actions server starts"
  APORT=$(port_from "$ACT_LOG")
  ABASE="http://127.0.0.1:$APORT"

  # empty JSON body: the pinned 400 stays the missing-reason check
  REJ_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' "$ABASE/api/reject")
  [ "$REJ_CODE" = "400" ] && ok "POST /api/reject with no reason -> 400" \
                          || bad "POST /api/reject with no reason -> 400 (got $REJ_CODE)"

  APP_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' "$ABASE/api/approve")
  [ "$APP_CODE" = "200" ] && ok "POST /api/approve -> 200" \
                          || bad "POST /api/approve -> 200 (got $APP_CODE)"

  PSTATUS=$("$BIN/al-state" --state "$AL/state.json" get plan.status 2>/dev/null || echo error)
  [ "$PSTATUS" = "approved" ] && ok "approve moves plan.status to approved" \
                              || bad "approve moves plan.status to approved (got $PSTATUS)"

  grep '"event":"plan_approved"' "$AL/audit.jsonl" 2>/dev/null | grep -q '"actor":"[^"]*@al-watch"' \
    && ok "plan_approved journaled with actor *@al-watch" \
    || bad "plan_approved journaled with actor *@al-watch"
else
  bad "actions server starts (al-watch missing or never ready)"
  bad "POST /api/reject with no reason -> 400 (no server)"
  bad "POST /api/approve -> 200 (no server)"
  bad "approve moves plan.status to approved (no server)"
  bad "plan_approved journaled with actor *@al-watch (no server)"
fi

echo
echo "watch tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
