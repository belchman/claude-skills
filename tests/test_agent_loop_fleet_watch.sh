#!/bin/sh
# test_agent_loop_fleet_watch.sh — model-free tests for the fleet registry
# ($AL_FLEET_REGISTRY: a plain file of repo roots that al-state init /
# lease-acquire and al-loop.sh append to, grep-dedup'd, physical paths,
# ONLY when the state file sits under */.claude/agent-loop/) and for
# fleet-mode al-watch (bare `al-watch --port 0`, NO repo arg: /api/fleet,
# SSE `event: fleet`, /events?repo=, /api/archive?repo=, repo-addressed
# POST /api/approve with a mandatory application/json Content-Type).
#
# Servers run in the background; readiness is a poll on the startup line
# ("http://127.0.0.1:<port>"), never a bare sleep. A fake `claude` first on
# PATH keeps al-loop.sh model-free.
#
# Skip (exit 0) ONLY when python3 is absent. NEVER skip when fleet mode is
# missing — this suite must be RED before the implementation exists.
#
# Run: sh tests/test_agent_loop_fleet_watch.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$REPO_ROOT/plugins/agent-loop/bin"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { # $1=description, $2=exit code, $3=expected code
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (exit $2, wanted $3)"; fi
}

command -v python3 >/dev/null 2>&1 || { echo "fleet tests: skipped (python3 absent)"; exit 0; }

SANDBOX=$(mktemp -d); SANDBOX=$(cd "$SANDBOX" && pwd -P)
STUB_BIN=$(mktemp -d);  STUB_BIN=$(cd "$STUB_BIN" && pwd -P)
PLAIN=$(mktemp -d);     PLAIN=$(cd "$PLAIN" && pwd -P)
SERVER_PIDS=""
cleanup() {
  for _p in $SERVER_PIDS; do kill "$_p" 2>/dev/null; done
  for _p in $SERVER_PIDS; do wait "$_p" 2>/dev/null; done
  rm -r "$SANDBOX" "$STUB_BIN" "$PLAIN" 2>/dev/null
}
trap cleanup EXIT
unset AL_STATE_FILE AL_GOAL_FILE 2>/dev/null || true

# The registry under test lives in the sandbox; opt-out must NOT be inherited
# from the caller's environment. CLAUDE_PROJECT_DIR points at an empty neutral
# dir so a bare al-watch can never fall back onto a real repo's loop state.
export AL_FLEET_REGISTRY="$SANDBOX/fleet.list"
unset AL_NO_FLEET_REGISTER 2>/dev/null || true
NEUTRAL="$SANDBOX/neutral"; mkdir -p "$NEUTRAL"
export CLAUDE_PROJECT_DIR="$NEUTRAL"

# --- claude stub (al-loop.sh must never reach a real model) -------------------
cat > "$STUB_BIN/claude" <<'EOF'
#!/bin/sh
{ echo "INVOKE"; printf 'ARG %s\n' "$@"; } >> "${CLAUDE_STUB_LOG:?}"
printf '%s' "${CLAUDE_STUB_OUTPUT:-}"
EOF
chmod +x "$STUB_BIN/claude"
PATH="$STUB_BIN:$PATH"; export PATH
export CLAUDE_STUB_LOG="$STUB_BIN/calls.log"
GOOD_RESULT='{"type":"result","subtype":"success","is_error":false,"num_turns":2,"result":"iteration done","session_id":"x","total_cost_usd":0.1,"usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":4}}'

# --- fixture repos -------------------------------------------------------------
mkrepo() { # $1=root, $2=goal id
  mkdir -p "$1/.claude/agent-loop"
  cat > "$1/.claude/agent-loop/GOAL.md" <<'EOF'
# Goal: fleet fixture

## Done means
- [ ] works: the fleet dashboard sees this repo
EOF
  cat > "$1/.claude/agent-loop/goal.json" <<EOF
{"id":"$2","status":"active","plan_approval":"always","max_iterations":5,"context_budget":50000,"verify":[{"cmd":"true","expect":"exit0"}],"verifier_rubric":["r"]}
EOF
}
REPO_A="$SANDBOX/repo-a"; mkrepo "$REPO_A" t-fleet-a
REPO_B="$SANDBOX/repo-b"; mkrepo "$REPO_B" t-fleet-b
STATE_A="$REPO_A/.claude/agent-loop/state.json"
STATE_B="$REPO_B/.claude/agent-loop/state.json"

reg_count() { # occurrences of $1 as an exact registry line (0 when no file)
  [ -f "$AL_FLEET_REGISTRY" ] || { echo 0; return 0; }
  grep -cxF "$1" "$AL_FLEET_REGISTRY" 2>/dev/null || true
}

echo "# fleet registry: al-state init / lease-acquire append (dedup'd)"
"$BIN/al-state" --state "$STATE_A" init t-fleet-a >/dev/null
check "fixture: al-state init repo A" $? 0
[ "$(reg_count "$REPO_A")" = "1" ] \
  && ok "init registers repo A's physical root exactly once" \
  || bad "init registers repo A's physical root exactly once (count $(reg_count "$REPO_A"))"

"$BIN/al-state" --state "$STATE_A" init t-fleet-a >/dev/null
[ "$(reg_count "$REPO_A")" = "1" ] \
  && ok "re-init dedupes (still exactly one line for A)" \
  || bad "re-init dedupes (count $(reg_count "$REPO_A"))"

AL_NO_FLEET_REGISTER=1 "$BIN/al-state" --state "$STATE_B" init t-fleet-b >/dev/null
check "fixture: al-state init repo B (opt-out)" $? 0
[ "$(reg_count "$REPO_B")" = "0" ] \
  && ok "AL_NO_FLEET_REGISTER=1 keeps repo B out of the registry" \
  || bad "AL_NO_FLEET_REGISTER=1 keeps repo B out of the registry"

"$BIN/al-state" --state "$PLAIN/state.json" init t-plain >/dev/null 2>&1
if [ -f "$AL_FLEET_REGISTRY" ] && grep -qF "$PLAIN" "$AL_FLEET_REGISTRY"; then
  bad "state path outside */.claude/agent-loop/ must not register"
else
  ok "state path outside */.claude/agent-loop/ must not register"
fi

"$BIN/al-state" --state "$STATE_B" lease-acquire >/dev/null
check "fixture: lease-acquire on repo B" $? 0
[ "$(reg_count "$REPO_B")" = "1" ] \
  && ok "lease-acquire (no opt-out) registers repo B" \
  || bad "lease-acquire (no opt-out) registers repo B (count $(reg_count "$REPO_B"))"
"$BIN/al-state" --state "$STATE_B" lease-release >/dev/null 2>&1

echo "# fleet registry: al-loop.sh registers only repos with goal.json"
: > "$CLAUDE_STUB_LOG"
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$REPO_A" >/dev/null 2>&1
check "loop tick on repo A exits 0" $? 0
[ "$(reg_count "$REPO_A")" = "1" ] \
  && ok "loop tick keeps A registered exactly once (no dup)" \
  || bad "loop tick keeps A registered exactly once (count $(reg_count "$REPO_A"))"

EMPTY="$SANDBOX/empty-repo"; mkdir -p "$EMPTY"
"$BIN/al-loop.sh" "$EMPTY" >/dev/null 2>&1
check "loop tick on goal-less dir exits 0" $? 0
if [ -f "$AL_FLEET_REGISTRY" ] && grep -qxF "$EMPTY" "$AL_FLEET_REGISTRY"; then
  bad "dir without goal.json never enters the registry"
else
  ok "dir without goal.json never enters the registry"
fi

# --- archived goal in repo A (for /api/archive) --------------------------------
ARCH="$REPO_A/.claude/agent-loop/archive/old-goal"
mkdir -p "$ARCH"
cat > "$ARCH/GOAL.md" <<'EOF'
# Goal: old goal (archived)

## Done means
- [x] done: it shipped
EOF
printf '{"goal_id":"old-goal","iteration":2}\n' > "$ARCH/state.json"
cat > "$ARCH/audit.jsonl" <<'EOF'
{"event":"goal_init","actor":"test","data":{"marker":"old-goal-journal-marker"}}
{"event":"iteration","actor":"test","data":{"n":1}}
EOF

# --- repo B: plan awaiting-human (fleet must surface needs_human) ---------------
"$BIN/al-state" --state "$STATE_B" plan-propose '{"tasks":[{"task":"t"}],"assumptions":["a1"]}' >/dev/null
check "fixture: plan-propose on repo B" $? 0
[ "$("$BIN/al-state" --state "$STATE_B" get plan.status)" = "awaiting-human" ] \
  && ok "fixture: repo B plan awaiting-human" || bad "fixture: repo B plan awaiting-human"

# --- registry hygiene: dedup-guarded manual lines + one dead path ---------------
# Mirrors the pinned write behavior (exact physical root per line, grep-dedup)
# so the server tests hold even while registration itself is still red.
reg_add() { grep -qxF "$1" "$AL_FLEET_REGISTRY" 2>/dev/null || echo "$1" >> "$AL_FLEET_REGISTRY"; }
reg_add "$REPO_A"
reg_add "$REPO_B"
DEAD=$(mktemp -d); DEAD=$(cd "$DEAD" && pwd -P); rmdir "$DEAD"
echo "$DEAD" >> "$AL_FLEET_REGISTRY"

# --- server helpers -----------------------------------------------------------
start_fleet() { # $1=stdout log; remaining args passed to al-watch. NO repo arg:
  # bare invocation IS the fleet-mode contract. Polls the log for the startup
  # URL (~10s budget) — fails fast when the binary dies before becoming ready.
  _log="$1"; shift
  "$BIN/al-watch" --port 0 "$@" > "$_log" 2>&1 &
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

echo "# fleet-mode al-watch (read-only)"
RO_LOG="$SANDBOX/fleet-ro.log"
if start_fleet "$RO_LOG"; then
  ok "bare al-watch --port 0 starts and prints http://127.0.0.1:<port>"
  PORT=$(port_from "$RO_LOG")
else
  bad "bare al-watch --port 0 starts (never became ready)"
  PORT=""
fi

if [ -n "$PORT" ]; then
  BASE="http://127.0.0.1:$PORT"
  cp "$AL_FLEET_REGISTRY" "$SANDBOX/fleet.list.before"

  STATEQ_OUT=$(curl -s -m 5 -G --data-urlencode "repo=$REPO_A" "$BASE/api/state")
  echo "$STATEQ_OUT" | grep -q 't-fleet-a' \
    && ok "GET /api/state?repo=A returns A's single-repo snapshot" \
    || bad "GET /api/state?repo=A returns A's single-repo snapshot (got: $(printf '%s' "$STATEQ_OUT" | head -c 120))"

  FLEET_OUT=$(curl -s -m 5 "$BASE/api/fleet")
  printf '%s' "$FLEET_OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert isinstance(d, list) and len(d) == 2, "want a 2-entry array, got %r" % (d,)
' 2>/dev/null \
    && ok "GET /api/fleet is a JSON array of 2 snapshots (dead path skipped)" \
    || bad "GET /api/fleet is a JSON array of 2 snapshots (got: $(printf '%s' "$FLEET_OUT" | head -c 120))"
  echo "$FLEET_OUT" | grep -q 't-fleet-a' && ok "/api/fleet carries repo A's goal id" || bad "/api/fleet repo A goal id"
  echo "$FLEET_OUT" | grep -q 't-fleet-b' && ok "/api/fleet carries repo B's goal id" || bad "/api/fleet repo B goal id"
  printf '%s' "$FLEET_OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
e = [x for x in d if "t-fleet-b" in json.dumps(x)]
assert e, "no snapshot for t-fleet-b"
e = e[0]
flags = e.get("flags") or {}
assert e.get("needs_human") or flags.get("needs_human"), "needs_human not set: %r" % (e,)
' 2>/dev/null \
    && ok "repo B snapshot flags needs_human (plan awaiting-human)" \
    || bad "repo B snapshot flags needs_human (plan awaiting-human)"
  if echo "$FLEET_OUT" | grep -q '"goal_md"\|"memory_md"'; then
    bad "fleet snapshots are slim (no goal_md/memory_md keys)"
  else
    ok "fleet snapshots are slim (no goal_md/memory_md keys)"
  fi
  cmp -s "$AL_FLEET_REGISTRY" "$SANDBOX/fleet.list.before" \
    && ok "registry file never rewritten by the server (byte-identical)" \
    || bad "registry file never rewritten by the server"

  # SSE: -m 3 cuts a healthy infinite stream, so curl exiting 28 is EXPECTED —
  # capture the output, never check curl's exit code here.
  SSE_OUT=$(curl -sN -m 3 "$BASE/events" 2>/dev/null || true)
  echo "$SSE_OUT" | grep -q 'event: fleet' && ok "/events emits fleet events" || bad "/events fleet event"

  SSE_A=$(curl -sN -m 3 -G --data-urlencode "repo=$REPO_A" "$BASE/events" 2>/dev/null || true)
  echo "$SSE_A" | grep -q 'event: journal'      && ok "/events?repo=A emits journal events"          || bad "/events?repo=A journal event"
  echo "$SSE_A" | grep -q '"event":"goal_init"' && ok "/events?repo=A replays A's goal_init verbatim" || bad "/events?repo=A goal_init replay"

  ARCH_LIST=$(curl -s -m 5 -G --data-urlencode "repo=$REPO_A" "$BASE/api/archive")
  echo "$ARCH_LIST" | grep -q 'old-goal' && ok "/api/archive?repo=A lists the archived goal" || bad "/api/archive list (got: $(printf '%s' "$ARCH_LIST" | head -c 120))"
  ARCH_DETAIL=$(curl -s -m 5 -G --data-urlencode "repo=$REPO_A" --data-urlencode "goal=old-goal" "$BASE/api/archive")
  echo "$ARCH_DETAIL" | grep -q 'old-goal-journal-marker' \
    && ok "/api/archive&goal=old-goal carries the archived journal lines" \
    || bad "/api/archive&goal=old-goal journal lines"

  RO_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -d "{\"repo\":\"$REPO_A\"}" "$BASE/api/approve")
  [ "$RO_CODE" = "403" ] && ok "read-only fleet server: POST /api/approve -> 403" \
                         || bad "read-only fleet server: POST /api/approve -> 403 (got $RO_CODE)"

  # --- fleet UI: grid page (GET /) and mandatory drill-down pin (GET /?repo=) ---
  GRID_OUT=$(curl -s -m 5 "$BASE/")
  printf '%s' "$GRID_OUT" | grep -qF 'id="fleetgrid"' \
    && ok 'fleet grid page carries id="fleetgrid"' \
    || bad 'fleet grid page carries id="fleetgrid"'
  printf '%s' "$GRID_OUT" | grep -qF 'needs-human' \
    && ok "fleet grid page carries the needs-human sort/lamp class" \
    || bad "fleet grid page carries the needs-human sort/lamp class"
  printf '%s' "$GRID_OUT" | grep -qF 'AGENT' \
    && ok "fleet grid page carries the AGENT wordmark" \
    || bad "fleet grid page carries the AGENT wordmark"
  printf '%s' "$GRID_OUT" | grep -qF 'archive' \
    && ok "fleet grid page carries the archive stats label" \
    || bad "fleet grid page carries the archive stats label"
  printf '%s' "$GRID_OUT" | grep -qF 'agent-loop' \
    && ok "fleet grid page still carries the agent-loop string" \
    || bad "fleet grid page still carries the agent-loop string"
  printf '%s' "$GRID_OUT" | grep -qF 'needsHuman' \
    && ok "fleet grid page JS carries the needsHuman alert-title marker" \
    || bad "fleet grid page JS carries the needsHuman alert-title marker"
  if printf '%s' "$GRID_OUT" | grep -qF 'id="view-overview"'; then
    bad 'fleet grid page (no ?repo=) must NOT carry id="view-overview"'
  else
    ok 'fleet grid page (no ?repo=) must NOT carry id="view-overview"'
  fi

  DRILL_OUT=$(curl -s -m 5 -G --data-urlencode "repo=$REPO_A" "$BASE/")
  printf '%s' "$DRILL_OUT" | grep -qF 'id="view-overview"' \
    && ok 'GET /?repo=A serves the console page (id="view-overview")' \
    || bad 'GET /?repo=A serves the console page (id="view-overview")'
  printf '%s' "$DRILL_OUT" | grep -qF 'back-to-fleet' \
    && ok "GET /?repo=A console carries the back-to-fleet control" \
    || bad "GET /?repo=A console carries the back-to-fleet control"
  printf '%s' "$DRILL_OUT" | grep -qF 'location.search' \
    && ok "GET /?repo=A console shim reads location.search" \
    || bad "GET /?repo=A console shim reads location.search"
else
  bad "GET /api/fleet is a JSON array of 2 snapshots (no server)"
  bad "/api/fleet carries repo A's goal id (no server)"
  bad "/api/fleet carries repo B's goal id (no server)"
  bad "repo B snapshot flags needs_human (no server)"
  bad "fleet snapshots are slim (no server)"
  bad "registry file never rewritten by the server (no server)"
  bad "/events emits fleet events (no server)"
  bad "/events?repo=A emits journal events (no server)"
  bad "/events?repo=A replays A's goal_init verbatim (no server)"
  bad "/api/archive?repo=A lists the archived goal (no server)"
  bad "/api/archive&goal=old-goal carries the archived journal lines (no server)"
  bad "read-only fleet server: POST /api/approve -> 403 (no server)"
  bad 'fleet grid page carries id="fleetgrid" (no server)'
  bad "fleet grid page carries the needs-human sort/lamp class (no server)"
  bad "fleet grid page carries the AGENT wordmark (no server)"
  bad "fleet grid page carries the archive stats label (no server)"
  bad "fleet grid page still carries the agent-loop string (no server)"
  bad "fleet grid page JS carries the needsHuman alert-title marker (no server)"
  bad 'fleet grid page (no ?repo=) must NOT carry id="view-overview" (no server)'
  bad 'GET /?repo=A serves the console page (id="view-overview") (no server)'
  bad "GET /?repo=A console carries the back-to-fleet control (no server)"
  bad "GET /?repo=A console shim reads location.search (no server)"
fi

echo "# fleet-mode al-watch (--allow-actions): repo-addressed approve"
ACT_LOG="$SANDBOX/fleet-act.log"
if start_fleet "$ACT_LOG" --allow-actions; then
  ok "fleet actions server starts"
  APORT=$(port_from "$ACT_LOG")
  ABASE="http://127.0.0.1:$APORT"

  APP_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -d "{\"repo\":\"$REPO_B\"}" "$ABASE/api/approve")
  [ "$APP_CODE" = "200" ] && ok "POST /api/approve {repo: B} -> 200" \
                          || bad "POST /api/approve {repo: B} -> 200 (got $APP_CODE)"
  PSTATUS=$("$BIN/al-state" --state "$STATE_B" get plan.status 2>/dev/null || echo error)
  [ "$PSTATUS" = "approved" ] && ok "approve moves B's plan.status to approved" \
                              || bad "approve moves B's plan.status to approved (got $PSTATUS)"
  grep '"event":"plan_approved"' "$REPO_B/.claude/agent-loop/audit.jsonl" 2>/dev/null \
      | grep -q '"actor":"[^"]*@al-watch"' \
    && ok "B's plan_approved journaled with actor *@al-watch" \
    || bad "B's plan_approved journaled with actor *@al-watch"

  # reject SUCCESS path, repo-addressed (repo A has a fresh awaiting plan)
  "$BIN/al-state" --state "$STATE_A" plan-propose '{"tasks":[{"task":"t"}],"assumptions":[]}' >/dev/null 2>&1
  REJOK_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -d "{\"repo\":\"$REPO_A\",\"reason\":\"scope creep\"}" "$ABASE/api/reject")
  [ "$REJOK_CODE" = "200" ] && ok "POST /api/reject {repo: A, reason} -> 200" \
                            || bad "POST /api/reject {repo: A, reason} -> 200 (got $REJOK_CODE)"
  [ "$("$BIN/al-state" --state "$STATE_A" get plan.status 2>/dev/null)" = "none" ] \
    && ok "reject resets A's plan.status to none" || bad "reject resets A's plan.status to none"
  [ "$("$BIN/al-state" --state "$STATE_A" get plan.rejected_reason 2>/dev/null)" = "scope creep" ] \
    && ok "reject stores A's rejection reason" || bad "reject stores A's rejection reason"
  grep '"event":"plan_rejected"' "$REPO_A/.claude/agent-loop/audit.jsonl" 2>/dev/null \
      | grep -q '"actor":"[^"]*@al-watch"' \
    && ok "A's plan_rejected journaled with actor *@al-watch" \
    || bad "A's plan_rejected journaled with actor *@al-watch"

  UNREG_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -d '{"repo":"/tmp"}' "$ABASE/api/approve")
  case "$UNREG_CODE" in
    4??) ok "approve for an unregistered repo -> 4xx" ;;
    *)   bad "approve for an unregistered repo -> 4xx (got $UNREG_CODE)" ;;
  esac

  # -H 'Content-Type:' strips curl's default header: the request carries NONE.
  NOCT_CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type:' -d "{\"repo\":\"$REPO_A\"}" "$ABASE/api/approve")
  case "$NOCT_CODE" in
    4??) ok "approve without Content-Type: application/json -> 4xx" ;;
    *)   bad "approve without Content-Type: application/json -> 4xx (got $NOCT_CODE)" ;;
  esac
else
  bad "fleet actions server starts (never became ready)"
  bad "POST /api/approve {repo: B} -> 200 (no server)"
  bad "approve moves B's plan.status to approved (no server)"
  bad "B's plan_approved journaled with actor *@al-watch (no server)"
  bad "POST /api/reject {repo: A, reason} -> 200 (no server)"
  bad "reject resets A's plan.status to none (no server)"
  bad "reject stores A's rejection reason (no server)"
  bad "A's plan_rejected journaled with actor *@al-watch (no server)"
  bad "approve for an unregistered repo -> 4xx (no server)"
  bad "approve without Content-Type: application/json -> 4xx (no server)"
fi

echo
echo "fleet tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
