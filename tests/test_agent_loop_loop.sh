#!/bin/sh
# test_agent_loop_loop.sh — model-free unit tests for bin/al-loop.sh.
# A fake `claude` first on PATH records its argv and emits canned result
# JSON from $CLAUDE_STUB_OUTPUT — no model calls, no network.
# Run: sh tests/test_agent_loop_loop.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$REPO_ROOT/plugins/agent-loop/bin"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { # $1=description, $2=exit code, $3=expected code
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (exit $2, wanted $3)"; fi
}

SANDBOX=$(mktemp -d); SANDBOX=$(cd "$SANDBOX" && pwd -P)
export AL_FLEET_REGISTRY="$SANDBOX/fleet.list"   # keep make test away from the real registry
STUB_BIN=$(mktemp -d)
trap 'rm -rf "$SANDBOX" "$STUB_BIN"' EXIT
export CLAUDE_PROJECT_DIR="$SANDBOX"
unset AL_STATE_FILE AL_GOAL_FILE 2>/dev/null || true

# --- claude stub -------------------------------------------------------------
cat > "$STUB_BIN/claude" <<'EOF'
#!/bin/sh
{ echo "INVOKE"; printf 'ARG %s\n' "$@"; } >> "${CLAUDE_STUB_LOG:?}"
printf '%s' "${CLAUDE_STUB_OUTPUT:-}"
EOF
chmod +x "$STUB_BIN/claude"
PATH="$STUB_BIN:$PATH"; export PATH

export CLAUDE_STUB_LOG="$STUB_BIN/calls.log"
calls() { # grep -c prints the count even when it exits 1 (zero matches)
  [ -f "$CLAUDE_STUB_LOG" ] || { echo 0; return 0; }
  grep -c '^INVOKE' "$CLAUDE_STUB_LOG" 2>/dev/null || true
}
reset_calls() { : > "$CLAUDE_STUB_LOG"; }

AL="$SANDBOX/.claude/agent-loop"
mkdir -p "$AL"
GOOD_RESULT='{"type":"result","subtype":"success","is_error":false,"num_turns":2,"result":"iteration done","session_id":"x","total_cost_usd":0.1,"usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":4}}'

seed_state() { # fresh valid state at iteration $1, plan status ${2:-none}
  cat > "$AL/state.json" <<EOF
{"goal_id":"t","iteration":$1,"done_means":{},"last_verdict":null,"progress_hash":null,"stall_count":0,"paused_by_stall":false,"stall_report":null,"run_in_progress":false,"interrupted_at":null,"context_tokens_last_iter":null,"plan":{"status":"${2:-none}","tasks":[],"assumptions":["the file name is unpinned — spec silent"],"proposed_at":null,"approved_at":null,"approved_by":null,"rejected_reason":null},"history":[]}
EOF
}
seed_goal() { # status=$1
  cat > "$AL/goal.json" <<EOF
{"id":"t","status":"$1","max_iterations":3,"context_budget":50000,"root":null,"verify":[{"cmd":"true","expect":"exit0"}],"verifier_rubric":[]}
EOF
}

echo "# al-loop.sh token-free gates (no claude call)"
reset_calls
rm -f "$AL/goal.json" "$AL/state.json"
"$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1; check "no goal.json -> exit 0" $? 0
[ "$(calls)" = "0" ] && ok "no goal.json -> no claude call" || bad "no goal.json -> no claude call"

reset_calls
seed_goal paused; seed_state 0
"$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1; check "status!=active -> exit 0" $? 0
[ "$(calls)" = "0" ] && ok "status!=active -> no claude call" || bad "status!=active -> no claude call"

reset_calls
seed_goal active; seed_state 1
"$BIN/al-json" set "$AL/state.json" paused_by_stall true >/dev/null
"$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1; check "paused_by_stall -> exit 0" $? 0
[ "$(calls)" = "0" ] && ok "paused_by_stall -> no claude call" || bad "paused_by_stall -> no claude call"

reset_calls
seed_goal active; seed_state 3   # iteration == max_iterations
CEIL_OUT=$("$BIN/al-loop.sh" "$SANDBOX" 2>&1); check "iteration ceiling -> exit 0 (not an error)" $? 0
[ "$(calls)" = "0" ] && ok "iteration ceiling -> no claude call" || bad "iteration ceiling -> no claude call"
echo "$CEIL_OUT" | grep -q "iteration ceiling reached (3/3)" && ok "ceiling message names N/M" || bad "ceiling message ($CEIL_OUT)"

reset_calls
seed_goal active; seed_state 1 awaiting-human
GATE_OUT=$("$BIN/al-loop.sh" "$SANDBOX" 2>&1); check "plan awaiting-human -> exit 0" $? 0
[ "$(calls)" = "0" ] && ok "plan awaiting-human -> no claude call (zero-token tick)" || bad "awaiting-human -> no claude call"
echo "$GATE_OUT" | grep -q "AWAITING HUMAN APPROVAL" && ok "awaiting gate says why" || bad "awaiting gate message"
echo "$GATE_OUT" | grep -q "file name is unpinned" && ok "awaiting gate lists the assumptions" || bad "awaiting gate assumptions"

echo "# al-loop.sh active run + usage backfill"
reset_calls
seed_goal active; seed_state 1
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "active goal -> exit 0" $? 0
[ "$(calls)" = "1" ] && ok "active goal -> exactly one claude call" || bad "claude calls ($(calls))"
grep -q '^ARG /agent-loop run$' "$CLAUDE_STUB_LOG" && ok "stub received /agent-loop run" || bad "stub argv"
[ "$("$BIN/al-json" get "$AL/state.json" context_tokens_last_iter)" = "600" ] \
  && ok "context backfilled from usage (100+200+300)" || bad "context backfill"

echo "# al-loop.sh honest failure reporting"
reset_calls
seed_goal active; seed_state 1
CLAUDE_STUB_OUTPUT='{"is_error":false,"result":"Unknown command: /agent-loop","usage":{}}' \
  "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "Unknown command result -> nonzero exit" $? 1

reset_calls
seed_goal active; seed_state 1
CLAUDE_STUB_OUTPUT='{"is_error":true,"result":"boom","usage":{}}' \
  "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "is_error:true -> nonzero exit" $? 1

echo "# al-loop.sh usage-field sanitization"
reset_calls
seed_goal active; seed_state 1
CLAUDE_STUB_OUTPUT='{"is_error":false,"result":"ok","usage":{"input_tokens":null,"cache_creation_input_tokens":null,"cache_read_input_tokens":null}}' \
  "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "null usage fields -> no crash (exit 0)" $? 0
[ "$("$BIN/al-json" get "$AL/state.json" context_tokens_last_iter)" = "null" ] \
  && ok "zero-token result leaves context untouched" || bad "context untouched on null usage"

echo "# al-loop.sh cost ledger + budget ceiling"
reset_calls
seed_goal active; seed_state 1
"$BIN/al-json" set "$AL/state.json" tokens_total 1000 >/dev/null
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
[ "$("$BIN/al-json" get "$AL/state.json" tokens_total)" = "1600" ] \
  && ok "tokens_total accumulates (1000+600)" || bad "ledger accumulation"
reset_calls
"$BIN/al-json" set "$AL/goal.json" budget_tokens 1500 >/dev/null
BUD_OUT=$("$BIN/al-loop.sh" "$SANDBOX" 2>&1); check "budget ceiling -> exit 0" $? 0
[ "$(calls)" = "0" ] && ok "budget ceiling -> no claude call" || bad "budget gate calls ($(calls))"
echo "$BUD_OUT" | grep -q "token budget reached (1600/1500)" && ok "budget message names spend/budget" || bad "budget message ($BUD_OUT)"
reset_calls
"$BIN/al-json" set "$AL/goal.json" budget_tokens 99999 >/dev/null
printf '{"budget_tokens":1200}' > "$AL/policy.json"
"$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
[ "$(calls)" = "0" ] && ok "org policy budget (the smaller) enforced" || bad "policy budget"
rm -f "$AL/policy.json"

echo "# al-loop.sh notifications (AL_LOOP_NOTIFY_CMD)"
NOTES="$SANDBOX/notes.jsonl"
reset_calls
seed_goal active; seed_state 1 awaiting-human
rm -f "$AL/logs/last_notify" "$NOTES"
AL_LOOP_NOTIFY_CMD="cat >> $NOTES" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
grep -q '"event":"plan_awaiting"' "$NOTES" 2>/dev/null && ok "awaiting-human notifies" || bad "awaiting notify"
grep -q '"goal_id":"t"' "$NOTES" 2>/dev/null && ok "notification carries the goal id" || bad "notify payload"
AL_LOOP_NOTIFY_CMD="cat >> $NOTES" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
[ "$(grep -c plan_awaiting "$NOTES")" = "1" ] && ok "repeat tick deduped (no page storm)" || bad "notify dedupe"
rm -f "$NOTES" "$AL/logs/last_notify"
"$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1; check "no notify channel -> still exit 0" $? 0

echo "# al-loop.sh circuit breaker"
reset_calls
seed_goal active; seed_state 1
rm -f "$AL/logs/consecutive_errors" "$AL/logs/last_notify"
for i in 1 2 3; do
  CLAUDE_STUB_OUTPUT='{"is_error":true,"result":"boom","usage":{}}' "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1 || true
done
[ "$(cat "$AL/logs/consecutive_errors" 2>/dev/null)" = "3" ] && ok "three consecutive failures counted" || bad "error counter"
reset_calls
"$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1; check "breaker open -> exit 0 (silenced tick)" $? 0
[ "$(calls)" = "0" ] && ok "breaker open -> no claude call" || bad "breaker calls ($(calls))"
rm -f "$AL/logs/consecutive_errors"
reset_calls
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
[ "$(calls)" = "1" ] && ok "re-armed after counter removal" || bad "re-arm"
[ -f "$AL/logs/consecutive_errors" ] && bad "success must clear the counter" || ok "success clears the counter"

echo "# al-loop.sh run lease (harness-level mutual exclusion)"
HOSTN=$(hostname 2>/dev/null || echo unknown)
# a LIVE durable owner (this test process) blocks the whole tick
reset_calls
seed_goal active; seed_state 1
rm -rf "$AL/.lease"; mkdir -p "$AL/.lease"
printf '{"pid":%s,"pid_durable":true,"host":"%s","session_id":"","acquired_at":"t","expires_epoch":9999999999}' "$$" "$HOSTN" > "$AL/.lease/owner.json"
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "live lease held elsewhere -> exit 0 (skipped tick)" $? 0
[ "$(calls)" = "0" ] && ok "live lease -> no claude call (no double-run)" || bad "live lease calls ($(calls))"
# a DEAD durable owner (crashed tick) is taken over; the tick proceeds and
# releases the lease on exit
reset_calls
sh -c ':' & LDEAD=$!
wait "$LDEAD" 2>/dev/null
printf '{"pid":%s,"pid_durable":true,"host":"%s","session_id":"","acquired_at":"t","expires_epoch":9999999999}' "$LDEAD" "$HOSTN" > "$AL/.lease/owner.json"
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "dead-owner lease -> tick proceeds" $? 0
[ "$(calls)" = "1" ] && ok "dead-owner lease taken over -> claude ran" || bad "dead-owner calls ($(calls))"
[ -f "$AL/.lease/owner.json" ] && bad "lease released after tick" || ok "lease released after tick"
grep -q '"event":"lease_takeover"' "$AL/audit.jsonl" 2>/dev/null && ok "dead-owner takeover journaled" || bad "dead-owner takeover journaled"
rm -rf "$AL/.lease"

echo "# al-loop.sh post-run backstop (inner session died mid-iteration)"
reset_calls
seed_goal active; seed_state 1
"$BIN/al-json" set "$AL/state.json" run_in_progress true >/dev/null
CLAUDE_STUB_OUTPUT="$GOOD_RESULT" "$BIN/al-loop.sh" "$SANDBOX" >/dev/null 2>&1
check "backstop tick exits 0" $? 0
[ "$("$BIN/al-json" get "$AL/state.json" run_in_progress)" = "false" ] && ok "phantom run flag cleared after tick" || bad "phantom run flag cleared after tick"
[ "$("$BIN/al-json" get "$AL/state.json" interrupted_at)" != "null" ] && ok "interrupted_at stamped by backstop" || bad "interrupted_at stamped by backstop"

echo
echo "loop tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
